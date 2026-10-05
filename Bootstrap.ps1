[CmdletBinding()]
param([switch]$LaunchCodex)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'scripts\Setup.Core.psm1') -Force -DisableNameChecking
try {
    $configPath = Join-Path $PSScriptRoot 'config.local.json'
    if (-not (Test-Path -LiteralPath $configPath)) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'config.example.json') -Destination $configPath
        Write-Host 'Created config.local.json. Edit your work email and any machine-specific values, save it, then run Bootstrap.cmd again.'
        exit 0
    }
    $config = Read-SetupConfig $configPath $PSScriptRoot
    $codexPath = Get-WorkingCodex $config.codexPath
    if (-not $codexPath) {
        $codexHome = Expand-VerifiedPackage $PSScriptRoot 'codex' (Join-Path $config.installRoot 'tools')
        $codexPath = Join-Path $codexHome 'codex.exe'
    }
    & $codexPath --version
    if ($LASTEXITCODE -ne 0) { throw 'Codex could not start. Check the company application allowlist with IT.' }
    Add-UserPath @((Split-Path -Parent $codexPath))
    if ($LaunchCodex) {
        & $codexPath -C $PSScriptRoot 'Use $levmet-device-setup to configure this Windows PC using config.local.json. Keep the config until setup and the DBeaver connection are verified.'
        exit $LASTEXITCODE
    }
    Write-Host 'Codex is available. Open Codex in this repository and invoke $levmet-device-setup. New terminal windows will pick up PATH.'
} catch {
    Write-Error $_.Exception.Message -ErrorAction Continue
    exit 1
}
