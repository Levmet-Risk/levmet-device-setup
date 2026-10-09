param([string]$ReuseFixture)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repo 'scripts\Setup.Core.psm1') -Force -DisableNameChecking
$fixture = if ($ReuseFixture) { [IO.Path]::GetFullPath($ReuseFixture) } else { Join-Path $repo ('.cache\offline install ' + [guid]::NewGuid().ToString('N')) }
if (-not $fixture.StartsWith((Join-Path $repo '.cache\offline install '),[StringComparison]::OrdinalIgnoreCase)) { throw 'Test fixtures must be inside this repository cache.' }
$install = Join-Path $fixture 'installed'
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$userPath = [Environment]::GetEnvironmentVariable('Path','User')
$userCa = [Environment]::GetEnvironmentVariable('SSL_CERT_FILE','User')
$tools = Join-Path $install 'tools'
Write-Host 'Testing fresh offline extraction of DBeaver and Codex...'
$dbeaver = Expand-VerifiedPackage $repo 'dbeaver' $tools
$codex = Expand-VerifiedPackage $repo 'codex' $tools
$config = Get-Content -LiteralPath (Join-Path $repo 'config.example.json') -Raw | ConvertFrom-Json
$config.email = 'offline.test@example.com'
$config.installRoot = $install
$config.dbeaverWorkspace = Join-Path $fixture 'workspace'
$config.gcloudConfigDirectory = Join-Path $fixture 'gcloud-user-config'
$config.codexPath = Join-Path $codex 'codex.exe'
$config.dbeaverPath = Join-Path $dbeaver 'dbeaver.exe'
$config.dbeaverDriverSource = 'offline'
$path = Join-Path $fixture 'config.local.json'
Write-JsonFile $path $config
& (Join-Path $repo 'Setup.ps1') -Phase Install -ConfigPath $path -ProcessEnvironmentOnly
if ($LASTEXITCODE -ne 0) { throw 'Fresh offline installation failed.' }
& (Join-Path $repo 'Setup.ps1') -Phase Install -ConfigPath $path -ProcessEnvironmentOnly
if ($LASTEXITCODE -ne 0) { throw 'Repeated installation failed.' }
if ([Environment]::GetEnvironmentVariable('Path','User') -cne $userPath -or [Environment]::GetEnvironmentVariable('SSL_CERT_FILE','User') -cne $userCa) { throw 'Offline test changed the real user environment.' }
Push-Location $env:TEMP
try {
    foreach ($name in @('gcloud.cmd','cloud-sql-proxy.exe','codex.exe','levmet-db-auth.cmd','levmet-db-tunnel.cmd','levmet-db-test.cmd','levmet-dbeaver.cmd')) {
        if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "Command not on PATH: $name" }
    }
} finally { Pop-Location }
if (-not (Test-Path -LiteralPath $path)) { throw 'Install deleted an unverified config.' }

Write-Host 'Testing Artifactory setup with an existing DBeaver application fixture (no mirror download)...'
$offlineSettings = Get-Content -LiteralPath (Join-Path $install 'settings.json') -Raw | ConvertFrom-Json
$config.installRoot = Join-Path $fixture 'artifactory installed'
$config.dbeaverWorkspace = Join-Path $fixture 'artifactory workspace'
$config.gcloudPath = $offlineSettings.gcloudPath
$config.dbeaverDriverSource = 'artifactory'
$config.dbeaverPath = Join-Path $fixture 'missing-dbeaver.exe'
Write-JsonFile $path $config
& (Join-Path $repo 'Setup.ps1') -Phase Install -ConfigPath $path -ProcessEnvironmentOnly
if ($LASTEXITCODE -eq 0) { throw 'Artifactory setup accepted a missing DBeaver executable.' }
if (Test-Path -LiteralPath $config.installRoot) { throw 'Missing DBeaver caused installation side effects.' }
$config.dbeaverPath = Join-Path $dbeaver 'dbeaver.exe'
Write-JsonFile $path $config
& (Join-Path $repo 'Setup.ps1') -Phase Install -ConfigPath $path -ProcessEnvironmentOnly
if ($LASTEXITCODE -ne 0) { throw 'Fresh Artifactory installation failed.' }
& (Join-Path $repo 'Setup.ps1') -Phase Install -ConfigPath $path -ProcessEnvironmentOnly
if ($LASTEXITCODE -ne 0) { throw 'Repeated Artifactory installation failed.' }
$mirrorSettings = Get-Content -LiteralPath (Join-Path $config.installRoot 'settings.json') -Raw | ConvertFrom-Json
if ((Get-DBeaverDriverSource $mirrorSettings) -ne 'artifactory') { throw 'Artifactory mode was not persisted.' }
Test-DBeaverProfile $mirrorSettings | Out-Null
if (Test-Path -LiteralPath $mirrorSettings.driverDirectory) { throw 'Artifactory setup installed offline JARs.' }
if (Test-Path -LiteralPath (Join-Path $config.installRoot 'tools')) { throw 'Artifactory setup extracted an unnecessary application.' }
if (Test-Path -LiteralPath (Join-Path $config.dbeaverWorkspace '.metadata\.config\drivers.xml')) { throw 'Artifactory setup wrote an offline driver definition.' }
if (-not (Test-Path -LiteralPath $path)) { throw 'Artifactory Install deleted an unverified config.' }
if ([Environment]::GetEnvironmentVariable('Path','User') -cne $userPath -or [Environment]::GetEnvironmentVariable('SSL_CERT_FILE','User') -cne $userCa) { throw 'Artifactory test changed the real user environment.' }
Write-Host "PASS: offline and Artifactory installation, repeatability, missing-app handling, commands outside the repo, and unchanged user environment. Fixture: $fixture"
