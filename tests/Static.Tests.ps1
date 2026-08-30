[CmdletBinding()]
param (
    [string]$RepositoryRoot = (Split-Path -Path $PSScriptRoot -Parent)
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Assert-Condition {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [bool]$Condition,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

$scriptPaths = @(
    (Join-Path -Path $RepositoryRoot -ChildPath 'tiny11maker.ps1'),
    (Join-Path -Path $RepositoryRoot -ChildPath 'tiny11Coremaker.ps1')
)

foreach ($scriptPath in $scriptPaths) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptPath,
        [ref]$tokens,
        [ref]$parseErrors
    ) | Out-Null

    Assert-Condition -Condition ($parseErrors.Count -eq 0) -Message (
        "PowerShell parser errors in ${scriptPath}: " +
        (($parseErrors | ForEach-Object Message) -join '; ')
    )
}

$makerPath = Join-Path -Path $RepositoryRoot -ChildPath 'tiny11maker.ps1'
$makerSource = Get-Content -LiteralPath $makerPath -Raw

$forbiddenPatterns = @{
    'mutable network download' = 'Invoke-(RestMethod|WebRequest)|System\.Net\.WebClient'
    'persistent execution-policy mutation' = 'Set-ExecutionPolicy'
    'argument-dropping self-elevation' = 'Start-Process[^\r\n]+-Verb\s+RunAs'
    'mutable main-branch input' = 'refs/heads/main|raw\.githubusercontent\.com'
}
foreach ($entry in $forbiddenPatterns.GetEnumerator()) {
    Assert-Condition -Condition ($makerSource -notmatch $entry.Value) -Message (
        "tiny11maker.ps1 contains forbidden $($entry.Key)."
    )
}

Assert-Condition -Condition ($makerSource -match 'function\s+Invoke-NativeCommand') -Message (
    'tiny11maker.ps1 must centralize checked native-command execution.'
)
Assert-Condition -Condition ($makerSource -match '\$LASTEXITCODE') -Message (
    'tiny11maker.ps1 must check native-command exit codes.'
)
Assert-Condition -Condition ($makerSource -match 'finally\s*\{') -Message (
    'tiny11maker.ps1 must retain a cleanup path for mounted images and registry hives.'
)
Assert-Condition -Condition ($makerSource -notmatch 'Remove-Item[^\r\n]+autounattend\.xml') -Message (
    'The reviewed answer file must not be deleted by the build.'
)

$tokens = $null
$parseErrors = $null
$makerAst = [System.Management.Automation.Language.Parser]::ParseFile(
    $makerPath,
    [ref]$tokens,
    [ref]$parseErrors
)
$packageAssignments = @(
    $makerAst.FindAll({
        param ($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $node.Left.VariablePath.UserPath -eq 'packagePrefixes'
    }, $true)
)
Assert-Condition -Condition ($packageAssignments.Count -eq 1) -Message (
    "Expected one packagePrefixes assignment, found $($packageAssignments.Count)."
)

$packagePrefixes = @(
    $packageAssignments[0].Right.FindAll({
        param ($node)
        $node -is [System.Management.Automation.Language.StringConstantExpressionAst]
    }, $true) | ForEach-Object Value
)
$duplicatePrefixes = @(
    $packagePrefixes |
        Group-Object |
        Where-Object Count -gt 1 |
        Select-Object -ExpandProperty Name
)
Assert-Condition -Condition ($packagePrefixes.Count -gt 0) -Message 'The package removal list is empty.'
Assert-Condition -Condition ($duplicatePrefixes.Count -eq 0) -Message (
    "Duplicate package prefixes: $($duplicatePrefixes -join ', ')"
)

$answerFilePath = Join-Path -Path $RepositoryRoot -ChildPath 'autounattend.xml'
[xml]$answerFile = Get-Content -LiteralPath $answerFilePath -Raw
$orphanComponents = @(
    $answerFile.SelectNodes("//*[local-name()='component']") |
        Where-Object { $_.ParentNode.LocalName -ne 'settings' }
)
Assert-Condition -Condition ($orphanComponents.Count -eq 0) -Message (
    'Every answer-file component must be contained by a settings configuration pass.'
)

$architectureNodes = @($answerFile.SelectNodes('//*[@processorArchitecture]'))
$architectures = @(
    $architectureNodes |
        ForEach-Object { $_.GetAttribute('processorArchitecture') } |
        Sort-Object -Unique
)
Assert-Condition -Condition ($architectures.Count -eq 1) -Message (
    'autounattend.xml must declare exactly one processor architecture.'
)

$productKeyNodes = @($answerFile.SelectNodes("//*[local-name()='ProductKey']/*[local-name()='Key']"))
$populatedKeys = @($productKeyNodes | Where-Object { -not [string]::IsNullOrWhiteSpace($_.InnerText) })
Assert-Condition -Condition ($populatedKeys.Count -eq 0) -Message (
    'autounattend.xml must not contain a populated product key.'
)

Write-Output 'Static source checks passed.'
