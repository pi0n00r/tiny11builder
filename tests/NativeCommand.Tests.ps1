$ErrorActionPreference = 'Stop'
$maker = Join-Path (Split-Path -Parent $PSScriptRoot) 'tiny11maker.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($maker, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw 'tiny11maker.ps1 has a parse error' }
$definition = $ast.Find({
    param ($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Invoke-NativeCommand'
}, $true)
if (-not $definition) { throw 'Invoke-NativeCommand is missing' }
Invoke-Expression $definition.Extent.Text

$testCommand = Join-Path $env:TEMP "tiny11-native-stderr-$PID.cmd"
try {
    Set-Content -LiteralPath $testCommand -Encoding Ascii -Value @(
        '@echo off',
        'echo ordinary output',
        'echo progress on stderr 1>&2',
        'exit /b %1'
    )
    $output = @(Invoke-NativeCommand -FilePath $testCommand -ArgumentList @('0') -CaptureOutput)
    if (($output -join "`n") -notmatch 'ordinary output') { throw 'stdout was lost' }
    if (($output -join "`n") -notmatch 'progress on stderr') { throw 'stderr was lost' }

    $failed = $false
    try {
        Invoke-NativeCommand -FilePath $testCommand -ArgumentList @('7') | Out-Null
    } catch {
        $failed = $_.Exception.Message -match 'failed with exit code 7'
    }
    if (-not $failed) { throw 'Nonzero native exit code was not rejected' }
    Write-Host 'Native command stderr and exit-code checks passed.'
} finally {
    Remove-Item -LiteralPath $testCommand -Force -ErrorAction SilentlyContinue
}
