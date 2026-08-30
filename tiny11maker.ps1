<#
.SYNOPSIS
    Builds a serviceable, trimmed Windows 11 installation image.

.DESCRIPTION
    This hardened variant keeps tiny11builder's regular removal policy while
    making inputs deterministic and critical failures terminating. It requires
    a local answer file and a signed oscdimg.exe from the Windows ADK or the
    script directory. It never downloads mutable build inputs at runtime.

.PARAMETER ISO
    Drive letter of the mounted Windows 11 source ISO, without a colon.

.PARAMETER SCRATCH
    Drive letter of a different, fixed local scratch volume, without a colon.

.PARAMETER ImageIndex
    Optional source image index. When omitted, the script prompts for it.

.PARAMETER OutputPath
    Optional output ISO path. The default is tiny11.iso beside this script.

.EXAMPLE
    .\tiny11maker.ps1 -ISO E -SCRATCH D -ImageIndex 6

.NOTES
    Upstream: https://github.com/ntdevlabs/tiny11builder
    Reliability hardening: 2026-08-30
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidatePattern('^[c-zC-Z]$')]
    [string]$ISO,

    [Parameter(Mandatory)]
    [ValidatePattern('^[c-zC-Z]$')]
    [string]$SCRATCH,

    [ValidateRange(1, 100)]
    [int]$ImageIndex,

    [string]$OutputPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$SourceDrive = "$($ISO.ToUpperInvariant()):"
$ScratchDrive = "$($SCRATCH.ToUpperInvariant()):"
$WorkPath = Join-Path -Path $ScratchDrive -ChildPath 'tiny11'
$MountPath = Join-Path -Path $ScratchDrive -ChildPath 'scratchdir'
$AnswerFilePath = Join-Path -Path $PSScriptRoot -ChildPath 'autounattend.xml'
$TranscriptPath = Join-Path -Path $PSScriptRoot -ChildPath "tiny11_$(Get-Date -Format yyyyMMdd_HHmmss)_$PID.log"
$OfflineHiveNames = @('zCOMPONENTS', 'zDEFAULT', 'zNTUSER', 'zSOFTWARE', 'zSYSTEM')

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path -Path $PSScriptRoot -ChildPath 'tiny11.iso'
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

$script:LoadedHives = @()
$script:MountedImagePath = $null
$script:TranscriptStarted = $false
$script:BuildSucceeded = $false

function Invoke-NativeCommand {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$ArgumentList = @(),

        [switch]$CaptureOutput
    )

    $commandOutput = & $FilePath @ArgumentList 2>&1
    $exitCode = $LASTEXITCODE

    if ($CaptureOutput) {
        $commandOutput
    } else {
        $commandOutput | ForEach-Object { Write-Output $_ }
    }

    if ($exitCode -ne 0) {
        throw "$FilePath failed with exit code $exitCode."
    }
}

function Write-OfflineRegistryValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('REG_DWORD', 'REG_SZ')]
        [string]$Type,

        [Parameter(Mandatory)]
        [string]$Value
    )

    Invoke-NativeCommand -FilePath 'reg.exe' -ArgumentList @(
        'add', $Path, '/v', $Name, '/t', $Type, '/d', $Value, '/f'
    ) | Out-Null
    Write-Output "Set registry value: $Path\$Name"
}

function Remove-OfflineRegistryKey {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    $providerPath = $Path -replace '^HKLM\\', 'Registry::HKEY_LOCAL_MACHINE\'
    $providerPath = $providerPath -replace '^HKEY_LOCAL_MACHINE\\', 'Registry::HKEY_LOCAL_MACHINE\'

    if (-not (Test-Path -LiteralPath $providerPath)) {
        Write-Output "Registry key already absent: $Path"
        return
    }

    if ($PSCmdlet.ShouldProcess($Path, 'Remove offline registry key')) {
        Invoke-NativeCommand -FilePath 'reg.exe' -ArgumentList @('delete', $Path, '/f') | Out-Null
        Write-Output "Removed registry key: $Path"
    }
}

function Import-OfflineRegistryHive {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateSet('zCOMPONENTS', 'zDEFAULT', 'zNTUSER', 'zSOFTWARE', 'zSYSTEM')]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$HivePath
    )

    Invoke-NativeCommand -FilePath 'reg.exe' -ArgumentList @('load', "HKLM\$Name", $HivePath) | Out-Null
    $script:LoadedHives += $Name
}

function Dismount-OfflineRegistryHive {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateSet('zCOMPONENTS', 'zDEFAULT', 'zNTUSER', 'zSOFTWARE', 'zSYSTEM')]
        [string]$Name
    )

    if ($script:LoadedHives -notcontains $Name) {
        return
    }

    Invoke-NativeCommand -FilePath 'reg.exe' -ArgumentList @('unload', "HKLM\$Name") | Out-Null
    $script:LoadedHives = @($script:LoadedHives | Where-Object { $_ -ne $Name })
}

function Import-OfflineRegistrySet {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$ImagePath
    )

    Import-OfflineRegistryHive -Name 'zCOMPONENTS' -HivePath (Join-Path $ImagePath 'Windows\System32\config\COMPONENTS')
    Import-OfflineRegistryHive -Name 'zDEFAULT' -HivePath (Join-Path $ImagePath 'Windows\System32\config\default')
    Import-OfflineRegistryHive -Name 'zNTUSER' -HivePath (Join-Path $ImagePath 'Users\Default\ntuser.dat')
    Import-OfflineRegistryHive -Name 'zSOFTWARE' -HivePath (Join-Path $ImagePath 'Windows\System32\config\SOFTWARE')
    Import-OfflineRegistryHive -Name 'zSYSTEM' -HivePath (Join-Path $ImagePath 'Windows\System32\config\SYSTEM')
}

function Dismount-OfflineRegistrySet {
    [CmdletBinding()]
    param ()

    foreach ($name in @('zSYSTEM', 'zSOFTWARE', 'zNTUSER', 'zDEFAULT', 'zCOMPONENTS')) {
        Dismount-OfflineRegistryHive -Name $name
    }
}

function Remove-OptionalPath {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$Recurse
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    if ($PSCmdlet.ShouldProcess($Path, 'Remove path')) {
        Remove-Item -LiteralPath $Path -Force -Recurse:$Recurse
    }
}

function Select-WindowsImageIndex {
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory)]
        [string]$ImagePath,

        [int]$RequestedIndex
    )

    $images = @(Get-WindowsImage -ImagePath $ImagePath)
    $availableIndexes = @($images | Select-Object -ExpandProperty ImageIndex)

    if ($RequestedIndex -gt 0) {
        if ($availableIndexes -notcontains $RequestedIndex) {
            throw "Image index $RequestedIndex is not present in $ImagePath."
        }
        return $RequestedIndex
    }

    $images | Format-Table -AutoSize ImageIndex, ImageName, Architecture, Version
    while ($true) {
        $response = Read-Host 'Please enter the image index'
        $parsedIndex = 0
        if ([int]::TryParse($response, [ref]$parsedIndex) -and $availableIndexes -contains $parsedIndex) {
            return $parsedIndex
        }
        Write-Warning 'Select one of the displayed image indexes.'
    }
}

function Get-ImageArchitecture {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [object]$Image
    )

    $architecture = ([string]$Image.Architecture).Trim()
    switch -Regex ($architecture) {
        '^(9|x64|amd64)$' { return 'amd64' }
        '^(12|arm64)$' { return 'arm64' }
        default { throw "Unsupported Windows image architecture: $architecture" }
    }
}

function Assert-AnswerFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateSet('amd64', 'arm64')]
        [string]$Architecture
    )

    [xml]$answerFile = Get-Content -LiteralPath $Path -Raw
    $architectureNodes = @($answerFile.SelectNodes('//*[@processorArchitecture]'))
    if ($architectureNodes.Count -eq 0) {
        throw 'The answer file contains no processorArchitecture declarations.'
    }

    $declaredArchitectures = @(
        $architectureNodes |
            ForEach-Object { $_.GetAttribute('processorArchitecture') } |
            Sort-Object -Unique
    )
    if ($declaredArchitectures.Count -ne 1 -or $declaredArchitectures[0] -ne $Architecture) {
        throw "Answer-file architecture '$($declaredArchitectures -join ',')' does not match image architecture '$Architecture'."
    }

    $productKeyNodes = @($answerFile.SelectNodes("//*[local-name()='ProductKey']/*[local-name()='Key']"))
    foreach ($node in $productKeyNodes) {
        if (-not [string]::IsNullOrWhiteSpace($node.InnerText)) {
            throw 'The answer file contains a populated product key.'
        }
    }
}

function Assert-SignedMicrosoftTool {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    $signature = Get-AuthenticodeSignature -FilePath $Path
    if ($null -eq $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch 'Microsoft') {
        throw "$Path is not signed by Microsoft."
    }
    if ([string]$signature.Status -ne 'Valid') {
        throw "$Path has unacceptable signature status: $($signature.Status)."
    }
    Write-Output "Using Microsoft-signed tool: $Path (signature status: $($signature.Status))"
}

function Assert-Preflight {
    [CmdletBinding()]
    param ()

    $adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole($adminRole)) {
        throw 'Open Windows PowerShell 5.1 as Administrator and run the command again.'
    }

    if ($SourceDrive -eq $ScratchDrive) {
        throw 'The mounted source ISO and scratch volume must use different drive letters.'
    }
    if (-not (Test-Path -LiteralPath "$SourceDrive\sources\boot.wim")) {
        throw "The source media has no sources\boot.wim: $SourceDrive"
    }
    if (-not (Test-Path -LiteralPath "$SourceDrive\sources\install.wim") -and
        -not (Test-Path -LiteralPath "$SourceDrive\sources\install.esd")) {
        throw "The source media has no sources\install.wim or install.esd: $SourceDrive"
    }
    if (-not (Test-Path -LiteralPath $AnswerFilePath)) {
        throw "Place the reviewed autounattend.xml beside this script: $AnswerFilePath"
    }
    if (Test-Path -LiteralPath $WorkPath) {
        throw "Existing work directory must be reconciled first: $WorkPath"
    }
    if (Test-Path -LiteralPath $MountPath) {
        throw "Existing mount directory must be reconciled first: $MountPath"
    }
    if (Test-Path -LiteralPath $OutputPath) {
        throw "Refusing to overwrite existing output: $OutputPath"
    }

    $scratchVolume = Get-Volume -DriveLetter $SCRATCH
    if ([string]$scratchVolume.DriveType -ne 'Fixed') {
        throw "Scratch must be a fixed local volume; $ScratchDrive is $($scratchVolume.DriveType)."
    }
    $scratchPsDrive = Get-PSDrive -Name $SCRATCH
    $minimumFreeBytes = 40GB
    if ($scratchPsDrive.Free -lt $minimumFreeBytes) {
        throw "Scratch requires at least 40 GiB free; $ScratchDrive has $([math]::Round($scratchPsDrive.Free / 1GB, 2)) GiB."
    }

    foreach ($command in @('dism.exe', 'reg.exe', 'takeown.exe', 'icacls.exe')) {
        if (-not (Get-Command -Name $command -ErrorAction SilentlyContinue)) {
            throw "Required Windows command is unavailable: $command"
        }
    }
    foreach ($hiveName in $OfflineHiveNames) {
        if (Test-Path -LiteralPath "Registry::HKEY_LOCAL_MACHINE\$hiveName") {
            throw "Offline registry hive is already loaded: HKLM\$hiveName"
        }
    }

    $outputDirectory = Split-Path -Path $OutputPath -Parent
    if (-not (Test-Path -LiteralPath $outputDirectory)) {
        throw "Output directory does not exist: $outputDirectory"
    }
}

function Save-MountedWindowsImage {
    [CmdletBinding()]
    param ()

    Dismount-WindowsImage -Path $MountPath -Save
    $script:MountedImagePath = $null
}

Assert-Preflight
Start-Transcript -Path $TranscriptPath
$script:TranscriptStarted = $true

try {
    Write-Output 'Copying Windows source media to local scratch...'
    New-Item -ItemType Directory -Path (Join-Path $WorkPath 'sources') -Force | Out-Null
    Copy-Item -Path "$SourceDrive\*" -Destination $WorkPath -Recurse -Force

    $copiedEsd = Join-Path $WorkPath 'sources\install.esd'
    $installWim = Join-Path $WorkPath 'sources\install.wim'
    if (Test-Path -LiteralPath $copiedEsd) {
        $sourceIndex = Select-WindowsImageIndex -ImagePath $copiedEsd -RequestedIndex $ImageIndex
        Write-Output "Converting source ESD image index $sourceIndex to WIM..."
        Export-WindowsImage -SourceImagePath $copiedEsd -SourceIndex $sourceIndex -DestinationImagePath $installWim -CompressionType Maximum -CheckIntegrity
        if (-not (Test-Path -LiteralPath $installWim)) {
            throw 'ESD conversion did not produce install.wim.'
        }
        Remove-Item -LiteralPath $copiedEsd -Force
        $workingImageIndex = 1
    } else {
        $workingImageIndex = Select-WindowsImageIndex -ImagePath $installWim -RequestedIndex $ImageIndex
    }

    Invoke-NativeCommand -FilePath 'takeown.exe' -ArgumentList @('/F', $installWim) | Out-Null
    $adminSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
    $adminGroup = $adminSid.Translate([System.Security.Principal.NTAccount])
    Invoke-NativeCommand -FilePath 'icacls.exe' -ArgumentList @($installWim, '/grant', "$($adminGroup.Value):(F)") | Out-Null
    Set-ItemProperty -LiteralPath $installWim -Name IsReadOnly -Value $false

    New-Item -ItemType Directory -Path $MountPath | Out-Null
    $script:MountedImagePath = $MountPath
    Mount-WindowsImage -ImagePath $installWim -Index $workingImageIndex -Path $MountPath

    $imageMetadata = Get-WindowsImage -ImagePath $installWim -Index $workingImageIndex
    $architecture = Get-ImageArchitecture -Image $imageMetadata
    Write-Output "Image: $($imageMetadata.ImageName); architecture: $architecture; version: $($imageMetadata.Version)"
    Assert-AnswerFile -Path $AnswerFilePath -Architecture $architecture

    $efiMarker = if ($architecture -eq 'amd64') { 'efi\boot\bootx64.efi' } else { 'efi\boot\bootaa64.efi' }
    if (-not (Test-Path -LiteralPath (Join-Path $WorkPath $efiMarker))) {
        throw "Source media does not contain the expected EFI marker: $efiMarker"
    }

    $imageIntl = Invoke-NativeCommand -FilePath 'dism.exe' -ArgumentList @(
        '/English', '/Get-Intl', "/Image:$MountPath"
    ) -CaptureOutput
    $languageMatch = [regex]::Match(($imageIntl -join "`n"), 'Default system UI language : ([a-zA-Z]{2}-[a-zA-Z]{2})')
    if (-not $languageMatch.Success) {
        throw 'Default system UI language was not found.'
    }
    Write-Output "Default system UI language: $($languageMatch.Groups[1].Value)"

    Write-Output 'Removing provisioned applications...'
    $packageOutput = Invoke-NativeCommand -FilePath 'dism.exe' -ArgumentList @(
        '/English', "/Image:$MountPath", '/Get-ProvisionedAppxPackages'
    ) -CaptureOutput
    $packages = @(
        $packageOutput | ForEach-Object {
            if ($_ -match 'PackageName : (.*)') { $matches[1] }
        }
    )
    $packagePrefixes = @(
        'AppUp.IntelManagementandSecurityStatus',
        'Clipchamp.Clipchamp',
        'DolbyLaboratories.DolbyAccess',
        'DolbyLaboratories.DolbyDigitalPlusDecoderOEM',
        'Microsoft.BingNews',
        'Microsoft.BingSearch',
        'Microsoft.BingWeather',
        'Microsoft.Copilot',
        'Microsoft.Windows.CrossDevice',
        'Microsoft.GamingApp',
        'Microsoft.GetHelp',
        'Microsoft.Getstarted',
        'Microsoft.Microsoft3DViewer',
        'Microsoft.MicrosoftOfficeHub',
        'Microsoft.MicrosoftSolitaireCollection',
        'Microsoft.MicrosoftStickyNotes',
        'Microsoft.MixedReality.Portal',
        'Microsoft.MSPaint',
        'Microsoft.Office.OneNote',
        'Microsoft.OfficePushNotificationUtility',
        'Microsoft.OutlookForWindows',
        'Microsoft.Paint',
        'Microsoft.People',
        'Microsoft.PowerAutomateDesktop',
        'Microsoft.SkypeApp',
        'Microsoft.StartExperiencesApp',
        'Microsoft.Todos',
        'Microsoft.Wallet',
        'Microsoft.Windows.DevHome',
        'Microsoft.Windows.Copilot',
        'Microsoft.Windows.Teams',
        'Microsoft.WindowsAlarms',
        'Microsoft.WindowsCamera',
        'microsoft.windowscommunicationsapps',
        'Microsoft.WindowsFeedbackHub',
        'Microsoft.WindowsMaps',
        'Microsoft.WindowsSoundRecorder',
        'Microsoft.WindowsTerminal',
        'Microsoft.Xbox.TCUI',
        'Microsoft.XboxApp',
        'Microsoft.XboxGameOverlay',
        'Microsoft.XboxGamingOverlay',
        'Microsoft.XboxIdentityProvider',
        'Microsoft.XboxSpeechToTextOverlay',
        'Microsoft.YourPhone',
        'Microsoft.ZuneMusic',
        'Microsoft.ZuneVideo',
        'MicrosoftCorporationII.MicrosoftFamily',
        'MicrosoftCorporationII.QuickAssist',
        'MSTeams',
        'MicrosoftTeams',
        'Microsoft.549981C3F5F10'
    )

    $packagesToRemove = @(
        $packages | Where-Object {
            $packageName = $_
            @($packagePrefixes | Where-Object { $packageName -like "$_*" }).Count -gt 0
        }
    )
    foreach ($package in $packagesToRemove) {
        Write-Output "Removing package: $package"
        Invoke-NativeCommand -FilePath 'dism.exe' -ArgumentList @(
            '/English', "/Image:$MountPath", '/Remove-ProvisionedAppxPackage', "/PackageName:$package"
        ) | Out-Null
    }

    foreach ($edgePath in @(
        (Join-Path $MountPath 'Program Files (x86)\Microsoft\Edge'),
        (Join-Path $MountPath 'Program Files (x86)\Microsoft\EdgeUpdate'),
        (Join-Path $MountPath 'Program Files (x86)\Microsoft\EdgeCore')
    )) {
        Remove-OptionalPath -Path $edgePath -Recurse
    }

    $webViewPath = Join-Path $MountPath 'Windows\System32\Microsoft-Edge-Webview'
    if (Test-Path -LiteralPath $webViewPath) {
        Invoke-NativeCommand -FilePath 'takeown.exe' -ArgumentList @('/F', $webViewPath, '/R') | Out-Null
        Invoke-NativeCommand -FilePath 'icacls.exe' -ArgumentList @($webViewPath, '/grant', "$($adminGroup.Value):(F)", '/T', '/C') | Out-Null
        Remove-OptionalPath -Path $webViewPath -Recurse
    }

    $oneDrivePath = Join-Path $MountPath 'Windows\System32\OneDriveSetup.exe'
    if (Test-Path -LiteralPath $oneDrivePath) {
        Invoke-NativeCommand -FilePath 'takeown.exe' -ArgumentList @('/F', $oneDrivePath) | Out-Null
        Invoke-NativeCommand -FilePath 'icacls.exe' -ArgumentList @($oneDrivePath, '/grant', "$($adminGroup.Value):(F)", '/C') | Out-Null
        Remove-OptionalPath -Path $oneDrivePath
    }

    Write-Output 'Loading offline registry hives...'
    Import-OfflineRegistrySet -ImagePath $MountPath

    Write-OfflineRegistryValue -Path 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' -Name 'SV1' -Type 'REG_DWORD' -Value '0'
    Write-OfflineRegistryValue -Path 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' -Name 'SV2' -Type 'REG_DWORD' -Value '0'
    Write-OfflineRegistryValue -Path 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' -Name 'SV1' -Type 'REG_DWORD' -Value '0'
    Write-OfflineRegistryValue -Path 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' -Name 'SV2' -Type 'REG_DWORD' -Value '0'
    Write-OfflineRegistryValue -Path 'HKLM\zSYSTEM\Setup\LabConfig' -Name 'BypassCPUCheck' -Type 'REG_DWORD' -Value '1'
    Write-OfflineRegistryValue -Path 'HKLM\zSYSTEM\Setup\LabConfig' -Name 'BypassRAMCheck' -Type 'REG_DWORD' -Value '1'
    Write-OfflineRegistryValue -Path 'HKLM\zSYSTEM\Setup\LabConfig' -Name 'BypassSecureBootCheck' -Type 'REG_DWORD' -Value '1'
    Write-OfflineRegistryValue -Path 'HKLM\zSYSTEM\Setup\LabConfig' -Name 'BypassStorageCheck' -Type 'REG_DWORD' -Value '1'
    Write-OfflineRegistryValue -Path 'HKLM\zSYSTEM\Setup\LabConfig' -Name 'BypassTPMCheck' -Type 'REG_DWORD' -Value '1'
    Write-OfflineRegistryValue -Path 'HKLM\zSYSTEM\Setup\MoSetup' -Name 'AllowUpgradesWithUnsupportedTPMOrCPU' -Type 'REG_DWORD' -Value '1'

    Write-OfflineRegistryValue -Path 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'OemPreInstalledAppsEnabled' -Type 'REG_DWORD' -Value '0'
    Write-OfflineRegistryValue -Path 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'PreInstalledAppsEnabled' -Type 'REG_DWORD' -Value '0'
    Write-OfflineRegistryValue -Path 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SilentInstalledAppsEnabled' -Type 'REG_DWORD' -Value '0'
    Write-OfflineRegistryValue -Path 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsConsumerFeatures' -Type 'REG_DWORD' -Value '1'
    Write-OfflineRegistryValue -Path 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'ContentDeliveryAllowed' -Type 'REG_DWORD' -Value '0'
    Write-OfflineRegistryValue -Path 'HKLM\zSOFTWARE\Microsoft\PolicyManager\current\device\Start' -Name 'ConfigureStartPins' -Type 'REG_SZ' -Value '{"pinnedList": [{}]}'
    Write-OfflineRegistryValue -Path 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'FeatureManagementEnabled' -Type 'REG_DWORD' -Value '0'
    Write-OfflineRegistryValue -Path 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'PreInstalledAppsEverEnabled' -Type 'REG_DWORD' -Value '0'
    Write-OfflineRegistryValue -Path 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SoftLandingEnabled' -Type 'REG_DWORD' -Value '0'
    Write-OfflineRegistryValue -Path 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SubscribedContentEnabled' -Type 'REG_DWORD' -Value '0'
    foreach ($contentId in @('310093', '338388', '338389', '338393', '353694', '353696')) {
        Write-OfflineRegistryValue -Path 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name "SubscribedContent-$($contentId)Enabled" -Type 'REG_DWORD' -Value '0'
    }
    Write-OfflineRegistryValue -Path 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SystemPaneSuggestionsEnabled' -Type 'REG_DWORD' -Value '0'
    Write-OfflineRegistryValue -Path 'HKLM\zSOFTWARE\Policies\Microsoft\PushToInstall' -Name 'DisablePushToInstall' -Type 'REG_DWORD' -Value '1'
    Write-OfflineRegistryValue -Path 'HKLM\zSOFTWARE\Policies\Microsoft\MRT' -Name 'DontOfferThroughWUAU' -Type 'REG_DWORD' -Value '1'
    Remove-OfflineRegistryKey -Path 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\Subscriptions'
    Remove-OfflineRegistryKey -Path 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SuggestedApps'
    Write-OfflineRegistryValue -Path 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableConsumerAccountStateContent' -Type 'REG_DWORD' -Value '1'
    Write-OfflineRegistryValue -Path 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableCloudOptimizedContent' -Type 'REG_DWORD' -Value '1'

    Write-OfflineRegistryValue -Path 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' -Name 'BypassNRO' -Type 'REG_DWORD' -Value '1'
    Copy-Item -LiteralPath $AnswerFilePath -Destination (Join-Path $MountPath 'Windows\System32\Sysprep\autounattend.xml') -Force
    Write-OfflineRegistryValue -Path 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' -Name 'ShippedWithReserves' -Type 'REG_DWORD' -Value '0'
    Write-OfflineRegistryValue -Path 'HKLM\zSYSTEM\ControlSet001\Control\BitLocker' -Name 'PreventDeviceEncryption' -Type 'REG_DWORD' -Value '1'
    Write-OfflineRegistryValue -Path 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Chat' -Name 'ChatIcon' -Type 'REG_DWORD' -Value '3'
    Write-OfflineRegistryValue -Path 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarMn' -Type 'REG_DWORD' -Value '0'
    Remove-OfflineRegistryKey -Path 'HKEY_LOCAL_MACHINE\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge'
    Remove-OfflineRegistryKey -Path 'HKEY_LOCAL_MACHINE\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update'
    Write-OfflineRegistryValue -Path 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\OneDrive' -Name 'DisableFileSyncNGSC' -Type 'REG_DWORD' -Value '1'

    Write-OfflineRegistryValue -Path 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -Name 'Enabled' -Type 'REG_DWORD' -Value '0'
    Write-OfflineRegistryValue -Path 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Privacy' -Name 'TailoredExperiencesWithDiagnosticDataEnabled' -Type 'REG_DWORD' -Value '0'
    Write-OfflineRegistryValue -Path 'HKLM\zNTUSER\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' -Name 'HasAccepted' -Type 'REG_DWORD' -Value '0'
    Write-OfflineRegistryValue -Path 'HKLM\zNTUSER\Software\Microsoft\Input\TIPC' -Name 'Enabled' -Type 'REG_DWORD' -Value '0'
    Write-OfflineRegistryValue -Path 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' -Name 'RestrictImplicitInkCollection' -Type 'REG_DWORD' -Value '1'
    Write-OfflineRegistryValue -Path 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' -Name 'RestrictImplicitTextCollection' -Type 'REG_DWORD' -Value '1'
    Write-OfflineRegistryValue -Path 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization\TrainedDataStore' -Name 'HarvestContacts' -Type 'REG_DWORD' -Value '0'
    Write-OfflineRegistryValue -Path 'HKLM\zNTUSER\Software\Microsoft\Personalization\Settings' -Name 'AcceptedPrivacyPolicy' -Type 'REG_DWORD' -Value '0'
    Write-OfflineRegistryValue -Path 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -Type 'REG_DWORD' -Value '0'
    Write-OfflineRegistryValue -Path 'HKLM\zSYSTEM\ControlSet001\Services\dmwappushservice' -Name 'Start' -Type 'REG_DWORD' -Value '4'

    Write-OfflineRegistryValue -Path 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate' -Name 'workCompleted' -Type 'REG_DWORD' -Value '1'
    Write-OfflineRegistryValue -Path 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate' -Name 'workCompleted' -Type 'REG_DWORD' -Value '1'
    Write-OfflineRegistryValue -Path 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate' -Name 'workCompleted' -Type 'REG_DWORD' -Value '1'
    Remove-OfflineRegistryKey -Path 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate'
    Remove-OfflineRegistryKey -Path 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate'
    Write-OfflineRegistryValue -Path 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' -Name 'TurnOffWindowsCopilot' -Type 'REG_DWORD' -Value '1'
    Write-OfflineRegistryValue -Path 'HKLM\zSOFTWARE\Policies\Microsoft\Edge' -Name 'HubsSidebarEnabled' -Type 'REG_DWORD' -Value '0'
    Write-OfflineRegistryValue -Path 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Explorer' -Name 'DisableSearchBoxSuggestions' -Type 'REG_DWORD' -Value '1'
    Write-OfflineRegistryValue -Path 'HKLM\zSOFTWARE\Policies\Microsoft\Teams' -Name 'DisableInstallation' -Type 'REG_DWORD' -Value '1'
    Write-OfflineRegistryValue -Path 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Mail' -Name 'PreventRun' -Type 'REG_DWORD' -Value '1'

    $tasksPath = Join-Path $MountPath 'Windows\System32\Tasks'
    foreach ($taskPath in @(
        (Join-Path $tasksPath 'Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser'),
        (Join-Path $tasksPath 'Microsoft\Windows\Customer Experience Improvement Program'),
        (Join-Path $tasksPath 'Microsoft\Windows\Application Experience\ProgramDataUpdater'),
        (Join-Path $tasksPath 'Microsoft\Windows\Chkdsk\Proxy'),
        (Join-Path $tasksPath 'Microsoft\Windows\Windows Error Reporting\QueueReporting')
    )) {
        Remove-OptionalPath -Path $taskPath -Recurse
    }

    Dismount-OfflineRegistrySet
    Write-Output 'Cleaning the component store...'
    Invoke-NativeCommand -FilePath 'dism.exe' -ArgumentList @(
        "/Image:$MountPath", '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase'
    )
    Save-MountedWindowsImage

    $exportedWim = Join-Path $WorkPath 'sources\install2.wim'
    Write-Output 'Exporting the selected image with recovery compression...'
    Invoke-NativeCommand -FilePath 'dism.exe' -ArgumentList @(
        '/Export-Image', "/SourceImageFile:$installWim", "/SourceIndex:$workingImageIndex",
        "/DestinationImageFile:$exportedWim", '/Compress:recovery', '/CheckIntegrity'
    )
    if (-not (Test-Path -LiteralPath $exportedWim)) {
        throw 'DISM did not produce the exported install image.'
    }
    $exportedImages = @(Get-WindowsImage -ImagePath $exportedWim)
    if ($exportedImages.Count -ne 1) {
        throw "Expected one exported image, found $($exportedImages.Count)."
    }
    Remove-Item -LiteralPath $installWim -Force
    Move-Item -LiteralPath $exportedWim -Destination $installWim

    $bootWim = Join-Path $WorkPath 'sources\boot.wim'
    Invoke-NativeCommand -FilePath 'takeown.exe' -ArgumentList @('/F', $bootWim) | Out-Null
    Invoke-NativeCommand -FilePath 'icacls.exe' -ArgumentList @($bootWim, '/grant', "$($adminGroup.Value):(F)") | Out-Null
    Set-ItemProperty -LiteralPath $bootWim -Name IsReadOnly -Value $false
    $script:MountedImagePath = $MountPath
    Mount-WindowsImage -ImagePath $bootWim -Index 2 -Path $MountPath
    Import-OfflineRegistrySet -ImagePath $MountPath

    Write-OfflineRegistryValue -Path 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' -Name 'SV1' -Type 'REG_DWORD' -Value '0'
    Write-OfflineRegistryValue -Path 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' -Name 'SV2' -Type 'REG_DWORD' -Value '0'
    Write-OfflineRegistryValue -Path 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' -Name 'SV1' -Type 'REG_DWORD' -Value '0'
    Write-OfflineRegistryValue -Path 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' -Name 'SV2' -Type 'REG_DWORD' -Value '0'
    Write-OfflineRegistryValue -Path 'HKLM\zSYSTEM\Setup\LabConfig' -Name 'BypassCPUCheck' -Type 'REG_DWORD' -Value '1'
    Write-OfflineRegistryValue -Path 'HKLM\zSYSTEM\Setup\LabConfig' -Name 'BypassRAMCheck' -Type 'REG_DWORD' -Value '1'
    Write-OfflineRegistryValue -Path 'HKLM\zSYSTEM\Setup\LabConfig' -Name 'BypassSecureBootCheck' -Type 'REG_DWORD' -Value '1'
    Write-OfflineRegistryValue -Path 'HKLM\zSYSTEM\Setup\LabConfig' -Name 'BypassStorageCheck' -Type 'REG_DWORD' -Value '1'
    Write-OfflineRegistryValue -Path 'HKLM\zSYSTEM\Setup\LabConfig' -Name 'BypassTPMCheck' -Type 'REG_DWORD' -Value '1'
    Write-OfflineRegistryValue -Path 'HKLM\zSYSTEM\Setup\MoSetup' -Name 'AllowUpgradesWithUnsupportedTPMOrCPU' -Type 'REG_DWORD' -Value '1'

    Dismount-OfflineRegistrySet
    Save-MountedWindowsImage

    Copy-Item -LiteralPath $AnswerFilePath -Destination (Join-Path $WorkPath 'autounattend.xml') -Force

    $hostArchitecture = $Env:PROCESSOR_ARCHITECTURE.ToLowerInvariant()
    $adkPath = Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath "Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$hostArchitecture\Oscdimg\oscdimg.exe"
    $localOscdimgPath = Join-Path -Path $PSScriptRoot -ChildPath 'oscdimg.exe'
    if (Test-Path -LiteralPath $adkPath) {
        $oscdimgPath = $adkPath
    } elseif (Test-Path -LiteralPath $localOscdimgPath) {
        $oscdimgPath = $localOscdimgPath
    } else {
        throw 'oscdimg.exe is unavailable. Install the Windows ADK Deployment Tools or place a reviewed Microsoft-signed copy beside the script.'
    }
    Assert-SignedMicrosoftTool -Path $oscdimgPath

    Write-Output "Creating ISO: $OutputPath"
    Invoke-NativeCommand -FilePath $oscdimgPath -ArgumentList @(
        '-m', '-o', '-u2', '-udfver102',
        "-bootdata:2#p0,e,b$WorkPath\boot\etfsboot.com#pEF,e,b$WorkPath\efi\microsoft\boot\efisys.bin",
        $WorkPath, $OutputPath
    )
    if (-not (Test-Path -LiteralPath $OutputPath)) {
        throw 'ISO creation returned success but no output file exists.'
    }
    $outputFile = Get-Item -LiteralPath $OutputPath
    if ($outputFile.Length -lt 1MB) {
        throw "Output ISO is implausibly small: $($outputFile.Length) bytes."
    }

    $script:BuildSucceeded = $true
    Write-Output "Creation completed: $OutputPath ($($outputFile.Length) bytes)"
} finally {
    for ($index = $script:LoadedHives.Count - 1; $index -ge 0; $index--) {
        $hiveName = $script:LoadedHives[$index]
        try {
            Invoke-NativeCommand -FilePath 'reg.exe' -ArgumentList @('unload', "HKLM\$hiveName") | Out-Null
        } catch {
            Write-Warning "Failed to unload HKLM\$hiveName during cleanup: $_"
        }
    }
    $script:LoadedHives = @()

    if ($null -ne $script:MountedImagePath) {
        try {
            Dismount-WindowsImage -Path $script:MountedImagePath -Discard
            $script:MountedImagePath = $null
        } catch {
            Write-Warning "Failed to discard mounted image at $($script:MountedImagePath): $_"
        }
    }

    if ($script:BuildSucceeded) {
        foreach ($path in @($WorkPath, $MountPath)) {
            try {
                Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            } catch {
                Write-Warning "Build succeeded, but cleanup failed for ${path}: $_"
            }
        }
    } else {
        Write-Warning "Build failed. Scratch evidence was retained at $WorkPath and $MountPath."
    }

    if ($script:TranscriptStarted) {
        try {
            Stop-Transcript | Out-Null
        } catch {
            Write-Warning "Failed to stop transcript: $_"
        }
    }
}
