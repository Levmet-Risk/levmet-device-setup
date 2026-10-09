[CmdletBinding()]
param(
    [ValidateSet('Install','Authenticate','Verify','Complete')][string]$Phase = 'Install',
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.local.json'),
    [switch]$DBeaverConfirmed,
    # Used by automated tests: never persists environment changes to this Windows user.
    [switch]$ProcessEnvironmentOnly
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'scripts\Setup.Core.psm1') -Force -DisableNameChecking
try {
    if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { throw 'This package supports Windows x64 PCs. ARM64 requires a separately tested package.' }
    $config = Read-SetupConfig -Path $ConfigPath -RepositoryRoot $PSScriptRoot
    $settingsPath = Join-Path $config.installRoot 'settings.json'
    $reportPath = Join-Path $config.installRoot 'verification.json'
    if ($Phase -eq 'Install') {
        Assert-DBeaverWorkspaceClosed $config.dbeaverWorkspace
        $dbeaverPath = $config.dbeaverPath
        if (-not $dbeaverPath) {
            $candidates = @((Join-Path $env:ProgramFiles 'DBeaver\dbeaver.exe'),(Join-Path $env:LOCALAPPDATA 'DBeaver\dbeaver.exe'))
            $dbeaverPath = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
        }
        if (-not $dbeaverPath -and $config.dbeaverDriverSource -eq 'artifactory') {
            throw 'Install DBeaver from Company Portal first. If it is not visible, update or create your Citizen Development registration ticket: https://help.marex.com/portal/203?createRequest=true&portalId=203&requestTypeId=927 . If already installed elsewhere, set dbeaverPath to its executable.'
        }
        if ($dbeaverPath -and -not (Test-Path -LiteralPath $dbeaverPath -PathType Leaf)) { throw 'The configured DBeaver executable does not exist. Install it from Company Portal and correct dbeaverPath.' }
        $toolsDirectory = Join-Path $config.installRoot 'tools'
        $binDirectory = Join-Path $config.installRoot 'bin'
        $driverDirectory = Join-Path $config.installRoot 'drivers\postgresql'
        $scriptDirectory = Join-Path $config.installRoot 'scripts'
        $backupDirectory = Join-Path $config.installRoot ('backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
        foreach ($directory in @($binDirectory,$scriptDirectory,$backupDirectory)) { [IO.Directory]::CreateDirectory($directory) | Out-Null }
        if ($config.dbeaverDriverSource -eq 'offline') { [IO.Directory]::CreateDirectory($driverDirectory) | Out-Null }
        Write-JsonFile (Join-Path $backupDirectory 'environment.json') @{
            Path=[Environment]::GetEnvironmentVariable('Path','User')
            SSL_CERT_FILE=[Environment]::GetEnvironmentVariable('SSL_CERT_FILE','User')
            CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE=[Environment]::GetEnvironmentVariable('CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE','User')
            LEVMET_SETUP_HOME=[Environment]::GetEnvironmentVariable('LEVMET_SETUP_HOME','User')
        }
        Write-Host 'Checking offline assets...'
        $assets = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'assets\files.json') -Raw | ConvertFrom-Json
        foreach ($asset in $assets.files) {
            if ($config.dbeaverDriverSource -eq 'artifactory' -and $asset.path -like 'assets/drivers/*.jar') { continue }
            Test-AssetHash (Join-Path $PSScriptRoot $asset.path) $asset.sha256
        }
        if ($config.gcloudPath) { $gcloudPath = $config.gcloudPath; $sdkHome = Split-Path -Parent (Split-Path -Parent $gcloudPath) }
        else {
            Write-Host 'Installing the bundled Google Cloud CLI and Python...'
            $sdkHome = Expand-VerifiedPackage $PSScriptRoot 'gcloud' $toolsDirectory
            $gcloudPath = Join-Path $sdkHome 'bin\gcloud.cmd'
        }
        $pythonPath = Join-Path $sdkHome 'platform\bundledpython\python.exe'
        if (-not (Test-Path -LiteralPath $gcloudPath -PathType Leaf) -or -not (Test-Path -LiteralPath $pythonPath -PathType Leaf)) { throw 'gcloudPath must refer to a complete portable SDK with bundled Python, or leave it empty to install the included SDK.' }
        $codexPath = Get-WorkingCodex $config.codexPath
        if (-not $codexPath) {
            Write-Host 'Installing the bundled Codex CLI...'
            $codexHome = Expand-VerifiedPackage $PSScriptRoot 'codex' $toolsDirectory
            $codexPath = Join-Path $codexHome 'codex.exe'
        }
        if (-not $dbeaverPath) {
            Write-Host 'Installing the bundled DBeaver Community application...'
            $dbeaverHome = Expand-VerifiedPackage $PSScriptRoot 'dbeaver' $toolsDirectory
            $dbeaverPath = Join-Path $dbeaverHome 'dbeaver.exe'
        }
        if (-not (Test-Path -LiteralPath $dbeaverPath -PathType Leaf)) { throw 'The configured DBeaver executable does not exist.' }
        $proxySource = Join-Path $PSScriptRoot 'assets\proxy\cloud-sql-proxy.exe'
        $proxyDestination = Join-Path $binDirectory 'cloud-sql-proxy.exe'
        if (-not (Test-Path -LiteralPath $proxyDestination) -or (Get-FileHash -LiteralPath $proxyDestination -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $proxySource -Algorithm SHA256).Hash) {
            Copy-Item -LiteralPath $proxySource -Destination $proxyDestination -Force
        }
        if ($config.dbeaverDriverSource -eq 'offline') {
            foreach ($asset in $assets.files | Where-Object { $_.path -like 'assets/drivers/*.jar' }) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $asset.path) -Destination $driverDirectory -Force }
        }
        foreach ($name in @('Setup.Core.psm1','Runtime.ps1','db_probe.py')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot "scripts\$name") -Destination $scriptDirectory -Force }
        $licenseDirectory = Join-Path $config.installRoot 'licenses'
        [IO.Directory]::CreateDirectory($licenseDirectory) | Out-Null
        Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'assets\licenses') -File | Copy-Item -Destination $licenseDirectory -Force
        $caText = [IO.File]::ReadAllText($config.caCertificatePath)
        if ($caText -match 'PRIVATE KEY' -or $caText -notmatch '-----BEGIN CERTIFICATE-----') { throw 'caCertificatePath must contain PEM public CA certificates, not a private key or DER certificate.' }
        foreach ($match in [regex]::Matches($caText,'(?s)-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----')) {
            $bytes = [Convert]::FromBase64String(($match.Groups[1].Value -replace '\s',''))
            $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($bytes)
            if ($certificate.NotAfter -lt (Get-Date)) { throw 'The supplied CA bundle contains an expired certificate. Obtain an updated bundle from IT.' }
            $certificate.Dispose()
        }
        $caBundlePath = Join-Path $config.installRoot 'certificates\ca-bundle.pem'
        [IO.Directory]::CreateDirectory((Split-Path -Parent $caBundlePath)) | Out-Null
        $publicRoots = [IO.File]::ReadAllText((Join-Path $sdkHome 'lib\third_party\certifi\cacert.pem'))
        [IO.File]::WriteAllText($caBundlePath, $publicRoots + "`n" + $caText, [Text.UTF8Encoding]::new($false))
        $hasher = [Security.Cryptography.SHA256]::Create()
        try { $idBytes = $hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($config.instanceConnectionName + '|' + $config.email + '|' + $config.localPort)) }
        finally { $hasher.Dispose() }
        $connectionId = 'levmet-iam-' + ([BitConverter]::ToString($idBytes) -replace '-','').Substring(0,16).ToLowerInvariant()
        # Explicit allowlist of operational values. Never persist the input config wholesale.
        $settings = [PSCustomObject][ordered]@{
            schemaVersion=1;installRoot=$config.installRoot;email=$config.email;instanceConnectionName=$config.instanceConnectionName
            instanceIp=$config.instanceIp;usePrivateIp=$config.usePrivateIp;database=$config.database;localPort=$config.localPort
            connectionName=$config.connectionName;connectionId=$connectionId;dbeaverWorkspace=$config.dbeaverWorkspace
            gcloudPath=$gcloudPath;pythonPath=$pythonPath;codexPath=$codexPath;dbeaverPath=$dbeaverPath
            dbeaverDriverSource=$config.dbeaverDriverSource
            gcloudConfigDirectory=$config.gcloudConfigDirectory;proxyPath=(Join-Path $binDirectory 'cloud-sql-proxy.exe')
            driverDirectory=$driverDirectory;caBundlePath=$caBundlePath;inputConfigSha256=$config.configSha256
        }
        Write-JsonFile $settingsPath $settings
        Set-DBeaverProfile $settings $backupDirectory
        $actions = @{'levmet-db-auth'='Auth';'levmet-db-tunnel'='Tunnel';'levmet-db-test'='Test';'levmet-dbeaver'='DBeaver'}
        foreach ($command in $actions.Keys) {
            $body = '@echo off' + "`r`n" + '"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\Runtime.ps1" -Action ' + $actions[$command] + "`r`nexit /b %errorlevel%`r`n"
            [IO.File]::WriteAllText((Join-Path $binDirectory ($command + '.cmd')),$body,[Text.UTF8Encoding]::new($false))
        }
        # Compatibility with the existing Levmet batch names without relying on cwd.
        foreach ($pair in @(@('re_auth.bat','levmet-db-auth.cmd'),@('run_tunnel.bat','levmet-db-tunnel.cmd'))) {
            [IO.File]::WriteAllText((Join-Path $binDirectory $pair[0]),('@echo off' + "`r`n" + 'call "%~dp0' + $pair[1] + '"' + "`r`nexit /b %errorlevel%`r`n"),[Text.UTF8Encoding]::new($false))
        }
        Add-UserPath @($binDirectory,(Split-Path -Parent $gcloudPath),(Split-Path -Parent $codexPath)) -ProcessOnly:$ProcessEnvironmentOnly
        Set-UserSetting 'SSL_CERT_FILE' $caBundlePath -ProcessOnly:$ProcessEnvironmentOnly
        Set-UserSetting 'CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE' $caBundlePath -ProcessOnly:$ProcessEnvironmentOnly
        Set-UserSetting 'LEVMET_SETUP_HOME' $config.installRoot -ProcessOnly:$ProcessEnvironmentOnly
        Set-RuntimeEnvironment $settings
        & $gcloudPath --version
        if ($LASTEXITCODE -ne 0) { throw 'The installed Google Cloud CLI did not pass its version check.' }
        & $codexPath --version
        if ($LASTEXITCODE -ne 0) { throw 'Codex did not pass its version check.' }
        & $settings.proxyPath --version
        if ($LASTEXITCODE -ne 0) { throw 'The Cloud SQL proxy did not pass its version check.' }
        Test-DBeaverProfile $settings | Out-Null
        if ($config.dbeaverDriverSource -eq 'artifactory') {
            Write-Host 'In this DBeaver workspace, open Window > Preferences > Connection > Drivers > Maven. Add https://artifactory.marex.com/artifactory/maven-virtual/ (URL only; no credentials), move it to the top, apply, and fully RESTART DBeaver before downloading drivers or testing the connection.'
        }
        Write-Host 'Install complete. Config retained. Next run Authenticate, then Verify, and test the saved DBeaver connection.'
        exit 0
    }
    if (-not (Test-Path -LiteralPath $settingsPath)) { throw 'Run the Install phase first.' }
    $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($settings.inputConfigSha256 -ne $config.configSha256) { throw 'The config changed since Install. Rerun Install to apply the new values before continuing.' }
    Set-RuntimeEnvironment $settings
    if ($Phase -eq 'Authenticate') {
        & (Join-Path $settings.installRoot 'scripts\Runtime.ps1') -Action Auth
        if ($LASTEXITCODE -ne 0) { throw 'ADC authentication did not complete.' }
        exit 0
    }
    if ($Phase -eq 'Complete' -and -not $DBeaverConfirmed) { throw 'Complete requires confirmation that the saved DBeaver profile passes Test Connection. Config retained.' }
    Write-Host 'Verifying tool executables, DBeaver profile, and live database access...'
    Test-InstalledEnvironment $settings -ProcessOnly:$ProcessEnvironmentOnly
    foreach ($program in @($settings.gcloudPath,$settings.codexPath,$settings.proxyPath)) {
        & $program --version
        if ($LASTEXITCODE -ne 0) { throw 'A required tool failed its version check.' }
    }
    $assets = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'assets\files.json') -Raw | ConvertFrom-Json
    if ((Get-DBeaverDriverSource $settings) -eq 'offline') {
        foreach ($asset in $assets.files | Where-Object { $_.path -like 'assets/drivers/*.jar' }) { Test-AssetHash (Join-Path $settings.driverDirectory ([IO.Path]::GetFileName($asset.path))) $asset.sha256 }
    }
    Test-DBeaverProfile $settings | Out-Null
    Invoke-DatabaseVerification $settings
    $report = [PSCustomObject]@{schemaVersion=1;allChecksPassed=$true;verifiedAtUtc=[DateTime]::UtcNow.ToString('o');configSha256=$config.configSha256;dbeaverConfirmed=[bool]$DBeaverConfirmed;configDeleted=$false}
    Write-JsonFile $reportPath $report
    if ($Phase -eq 'Complete') {
        Remove-CompletedConfig $config $report -DBeaverConfirmed:$DBeaverConfirmed
        $report.configDeleted = $true
        Write-JsonFile $reportPath $report
        Write-Host 'Setup verified and config.local.json deleted. Restart terminals to load the user PATH. Run levmet-db-tunnel, then levmet-dbeaver.'
    } else { Write-Host 'Database query passed. Config retained until DBeaver Test Connection is confirmed and Complete succeeds.' }
} catch {
    Write-Error $_.Exception.Message -ErrorAction Continue
    if (Test-Path -LiteralPath $ConfigPath) { Write-Host 'Setup did not complete. The input config has been retained.' }
    else { Write-Host 'The input config is absent. Check the installed verification report for the completed steps.' }
    exit 1
}
