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
Write-Host "PASS: fresh offline packages, repeated installation, commands outside the repo, and unchanged user environment. Fixture: $fixture"
