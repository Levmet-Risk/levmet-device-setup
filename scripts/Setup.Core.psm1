Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-JsonFile {
    param([string]$Path, $Value)
    $parent = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 80) + "`n", [Text.UTF8Encoding]::new($false))
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporary, $Path, [System.Management.Automation.Language.NullString]::Value) }
    else { [IO.File]::Move($temporary, $Path) }
}

function Resolve-SetupPath {
    param([string]$Path, [string]$Base)
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if ($expanded -match '[%\r\n\x00"]') { throw 'A configured path contains an unresolved environment variable or invalid character.' }
    if (-not [IO.Path]::IsPathRooted($expanded)) { $expanded = Join-Path $Base $expanded }
    return [IO.Path]::GetFullPath($expanded).TrimEnd('\')
}

function Read-SetupConfig {
    param([string]$Path, [string]$RepositoryRoot)
    $full = [IO.Path]::GetFullPath($Path)
    if ([IO.Path]::GetFileName($full) -ne 'config.local.json') { throw 'Use a file named config.local.json. The example template is never used as live input.' }
    if ((Get-Item -LiteralPath $full).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'The input config must be a regular file, not a link.' }
    try { $config = Get-Content -LiteralPath $full -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw 'config.local.json is not valid JSON. Check its syntax without pasting its contents into chat.' }
    $fields = @('schemaVersion','email','instanceConnectionName','instanceIp','usePrivateIp','database','localPort','connectionName','installRoot','caCertificatePath','gcloudPath','gcloudConfigDirectory','codexPath','dbeaverPath','dbeaverWorkspace')
    foreach ($name in $fields) { if (-not $config.PSObject.Properties[$name]) { throw "Missing config field: $name" } }
    foreach ($property in $config.PSObject.Properties) { if ($property.Name -notin ($fields + @('dbeaverDriverSource'))) { throw 'The config has unsupported fields. Passwords, tokens, and service-account keys are not used by this IAM setup.' } }
    if (-not $config.PSObject.Properties['dbeaverDriverSource']) { $config | Add-Member -NotePropertyName dbeaverDriverSource -NotePropertyValue 'artifactory' }
    if ($config.dbeaverDriverSource -notin @('artifactory','offline')) { throw 'dbeaverDriverSource must be artifactory or offline.' }
    if ($config.schemaVersion -ne 1) { throw 'Unsupported config schemaVersion.' }
    if ($config.email -notmatch '^[A-Za-z0-9._+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$') { throw 'Set email to your work Google/IAM email address.' }
    if ($config.instanceConnectionName -notmatch '^[a-z][a-z0-9-]+:[a-z0-9-]+:[a-z0-9-]+$') { throw 'instanceConnectionName must be project:region:instance.' }
    $address = $null
    if (-not [Net.IPAddress]::TryParse([string]$config.instanceIp, [ref]$address)) { throw 'instanceIp must be the Cloud SQL instance IP supplied by IT.' }
    if ($config.usePrivateIp -isnot [bool]) { throw 'usePrivateIp must be true or false.' }
    if ($config.localPort -isnot [int] -or $config.localPort -lt 1024 -or $config.localPort -gt 65535) { throw 'localPort must be an integer from 1024 through 65535.' }
    foreach ($name in @('database','connectionName')) {
        if ([string]::IsNullOrWhiteSpace($config.$name) -or $config.$name -match '[|\r\n\x00]') { throw "Invalid config field: $name" }
    }
    foreach ($name in @('installRoot','dbeaverWorkspace','gcloudConfigDirectory')) {
        $config.$name = Resolve-SetupPath $config.$name $RepositoryRoot
        if ($config.$name.Length -lt 8 -or $config.$name -eq [IO.Path]::GetPathRoot($config.$name)) { throw "Choose a specific directory for $name." }
    }
    foreach ($name in @('caCertificatePath','gcloudPath','codexPath','dbeaverPath')) {
        if ($config.$name) { $config.$name = Resolve-SetupPath $config.$name $RepositoryRoot }
    }
    if (-not $config.caCertificatePath -or -not (Test-Path -LiteralPath $config.caCertificatePath -PathType Leaf)) { throw 'The corporate PEM CA file in caCertificatePath is missing.' }
    $config | Add-Member -NotePropertyName configPath -NotePropertyValue $full
    $config | Add-Member -NotePropertyName configSha256 -NotePropertyValue (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
    return $config
}

function Add-UserPath {
    param([string[]]$Directories, [switch]$ProcessOnly)
    $scope = if ($ProcessOnly) { 'Process' } else { 'User' }
    $old = [Environment]::GetEnvironmentVariable('Path', $scope)
    $entries = @($old -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    foreach ($directory in $Directories) {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "PATH directory does not exist: $directory" }
        if (-not @($entries | Where-Object { [Environment]::ExpandEnvironmentVariables($_).Trim().Trim('"').TrimEnd('\') -ieq $directory.TrimEnd('\') }).Count) { $entries += $directory }
    }
    [Environment]::SetEnvironmentVariable('Path', ($entries -join ';'), $scope)
    if (-not $ProcessOnly) {
        # Fresh child shells inherit this now; already-open applications need restarting.
        Add-UserPath -Directories $Directories -ProcessOnly
    }
}

function Set-UserSetting {
    param([string]$Name, [string]$Value, [switch]$ProcessOnly)
    if (-not $ProcessOnly) { [Environment]::SetEnvironmentVariable($Name, $Value, 'User') }
    [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
}

function Test-AssetHash {
    param([string]$Path, [string]$Expected)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing packaged asset: $Path" }
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ine $Expected) { throw "Checksum failed for $Path. Obtain a clean copy of the repository." }
}

function Expand-VerifiedPackage {
    param([string]$RepositoryRoot, [string]$Id, [string]$ToolsDirectory)
    $manifest = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'assets\packages.json') -Raw | ConvertFrom-Json
    $package = @($manifest.packages | Where-Object id -eq $Id)
    if ($package.Count -ne 1) { throw "Unknown packaged application: $Id" }
    $package = $package[0]
    $destination = Join-Path $ToolsDirectory ($Id + '-' + $package.version)
    $marker = Join-Path $destination '.levmet-package.json'
    if (Test-Path -LiteralPath $marker) {
        $installed = Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
        if ($installed.sha256 -eq $package.sha256) { return (Join-Path $destination $package.archiveRoot) }
        throw "A different package already occupies $destination. Choose a new installRoot."
    }
    if (Test-Path -LiteralPath $destination) { throw "An incomplete installation exists at $destination. Preserve or rename it before retrying." }
    [IO.Directory]::CreateDirectory($ToolsDirectory) | Out-Null
    $stage = Join-Path $ToolsDirectory ('.stage-' + [guid]::NewGuid().ToString('N').Substring(0,8))
    [IO.Directory]::CreateDirectory($stage) | Out-Null
    $archivePath = Join-Path $stage 'package.zip'
    $output = [IO.File]::Create($archivePath)
    try {
        foreach ($part in $package.parts) {
            $partPath = Resolve-SetupPath $part.path $RepositoryRoot
            if (-not $partPath.StartsWith($RepositoryRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Package part is outside the repository.' }
            Test-AssetHash $partPath $part.sha256
            $inputFile = [IO.File]::OpenRead($partPath)
            try { $inputFile.CopyTo($output) } finally { $inputFile.Dispose() }
        }
    } finally { $output.Dispose() }
    Test-AssetHash $archivePath $package.sha256
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
    $extract = Join-Path $stage 'expanded'
    [IO.Directory]::CreateDirectory($extract) | Out-Null
    try {
        foreach ($entry in $archive.Entries) {
            $target = [IO.Path]::GetFullPath((Join-Path $extract $entry.FullName))
            if (-not $target.StartsWith($extract + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe path in application archive.' }
            # .NET Framework used by Windows PowerShell 5.1 still has MAX_PATH
            # limitations unless long local paths use the Windows extended form.
            $ioTarget = if ($target.StartsWith('\\')) { '\\?\UNC\' + $target.Substring(2) } else { '\\?\' + $target }
            if ($entry.FullName.EndsWith('/')) { [IO.Directory]::CreateDirectory($ioTarget) | Out-Null; continue }
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($ioTarget)) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $ioTarget, $false)
        }
    } finally { $archive.Dispose() }
    Write-JsonFile (Join-Path $extract '.levmet-package.json') @{id=$Id;version=$package.version;sha256=$package.sha256}
    # Both source and destination are explicit children of ToolsDirectory.
    if (-not ([IO.Path]::GetFullPath($destination).StartsWith([IO.Path]::GetFullPath($ToolsDirectory).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase))) { throw 'Invalid install destination.' }
    if (-not ([IO.Path]::GetFullPath($extract).StartsWith([IO.Path]::GetFullPath($ToolsDirectory).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase))) { throw 'Invalid staging source.' }
    $ioSource = if ($extract.StartsWith('\\')) { '\\?\UNC\' + $extract.Substring(2) } else { '\\?\' + $extract }
    $ioDestination = if ($destination.StartsWith('\\')) { '\\?\UNC\' + $destination.Substring(2) } else { '\\?\' + $destination }
    # Rename the directory atomically without PowerShell enumerating long children.
    for ($renameAttempt = 0; ; $renameAttempt++) {
        try { [IO.Directory]::Move($ioSource, $ioDestination); break }
        catch {
            # Endpoint scanners may briefly hold newly extracted executable files.
            # Retry the same rename without changing ACLs or scanner settings.
            if ($renameAttempt -ge 14) { throw }
            Start-Sleep -Seconds 1
        }
    }
    Remove-Item -LiteralPath $archivePath
    Remove-Item -LiteralPath $stage
    return (Join-Path $destination $package.archiveRoot)
}

function Get-WorkingCodex {
    param([string]$ExplicitPath)
    $candidates = @()
    if ($ExplicitPath) { $candidates += $ExplicitPath }
    else {
        $candidates += @(Get-Command codex.exe,codex.cmd -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
        $candidates += @((Join-Path $env:USERPROFILE '.local\bin\codex.exe'), (Join-Path $env:APPDATA 'npm\codex.cmd'))
        foreach ($extensions in @('.vscode\extensions','.vscode-insiders\extensions')) {
            $base = Join-Path $env:USERPROFILE $extensions
            if (Test-Path -LiteralPath $base) {
                $candidates += @(Get-ChildItem -LiteralPath $base -Directory -Filter 'openai.chatgpt-*' | Sort-Object LastWriteTime -Descending | ForEach-Object { Join-Path $_.FullName 'bin\windows-x86_64\codex.exe' })
            }
        }
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            try { $version = & $candidate --version 2>$null; if ($LASTEXITCODE -eq 0 -and ($version -join '') -match 'codex') { return $candidate } } catch { }
        }
    }
    if ($ExplicitPath) { throw 'The configured codexPath does not run successfully. Correct it or leave it empty for the packaged fallback.' }
    return $null
}

function Backup-SetupFile {
    param([string]$Path, [string]$BackupDirectory)
    if (Test-Path -LiteralPath $Path) {
        [IO.Directory]::CreateDirectory($BackupDirectory) | Out-Null
        Copy-Item -LiteralPath $Path -Destination (Join-Path $BackupDirectory ([guid]::NewGuid().ToString('N') + '-' + [IO.Path]::GetFileName($Path)))
    }
}

function Assert-DBeaverWorkspaceClosed {
    param([string]$Workspace)
    $lockPath = Join-Path $Workspace '.metadata\.lock'
    if (Test-Path -LiteralPath $lockPath) {
        try { $handle = [IO.File]::Open($lockPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None); $handle.Dispose() }
        catch { throw 'Save your work and close DBeaver for the target workspace, then rerun Install. Setup never force-closes DBeaver.' }
    }
    foreach ($process in @(Get-Process dbeaver -ErrorAction SilentlyContinue)) {
        $details = Get-CimInstance Win32_Process -Filter "ProcessId = $($process.Id)" -ErrorAction SilentlyContinue
        if (-not $details -or -not $details.CommandLine) { throw 'A running DBeaver workspace could not be identified. Close DBeaver before installing.' }
        $match = [regex]::Match($details.CommandLine,'(?:^|\s)-data\s+(?:"([^"]+)"|(\S+))')
        $activeWorkspace = if ($match.Success) { if ($match.Groups[1].Success) { $match.Groups[1].Value } else { $match.Groups[2].Value } } else { Join-Path $env:APPDATA 'DBeaverData\workspace6' }
        if ([IO.Path]::GetFullPath($activeWorkspace).TrimEnd('\') -ieq $Workspace.TrimEnd('\')) { throw 'Save your work and close DBeaver for the target workspace, then rerun Install.' }
    }
}

function Get-DBeaverDriverSource {
    param($Settings)
    # Installed settings predating the Artifactory workflow used the offline driver.
    if (-not $Settings.PSObject.Properties['dbeaverDriverSource']) { return 'offline' }
    if ($Settings.dbeaverDriverSource -notin @('artifactory','offline')) { throw 'Unknown DBeaver driver source. Rerun Install with a valid config.' }
    return $Settings.dbeaverDriverSource
}

function Get-DBeaverDriverId {
    param($Settings)
    if ((Get-DBeaverDriverSource $Settings) -eq 'offline') { return 'levmet-postgres-offline' }
    return 'postgres-jdbc'
}

function Set-DBeaverOfflineDriver {
    param($Settings, [string]$BackupDirectory)
    # A running Eclipse application can overwrite externally edited workspace files.
    $workspace = $Settings.dbeaverWorkspace
    Assert-DBeaverWorkspaceClosed $workspace
    $driversPath = Join-Path $workspace '.metadata\.config\drivers.xml'
    $document = [xml]::new()
    $document.XmlResolver = $null
    if (Test-Path -LiteralPath $driversPath) {
        $xmlSettings = [Xml.XmlReaderSettings]::new()
        $xmlSettings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
        $xmlSettings.XmlResolver = $null
        $reader = [Xml.XmlReader]::Create($driversPath, $xmlSettings)
        try { $document.Load($reader) } finally { $reader.Dispose() }
    } else { $document.LoadXml('<?xml version="1.0" encoding="UTF-8"?><drivers/>') }
    # DBeaver 26.2 reliably loads the flat driver form with an explicit provider.
    # Keep other providers/drivers, including legacy nested definitions, intact.
    foreach ($previous in @($document.SelectNodes('/drivers/driver[@provider="postgresql" and @id="levmet-postgres-offline"] | /drivers/provider[@id="postgresql"]/driver[@id="levmet-postgres-offline"]'))) {
        $previous.ParentNode.RemoveChild($previous) | Out-Null
    }
    $driver = $document.CreateElement('driver')
    $attributes = @{id='levmet-postgres-offline';provider='postgresql';name='Levmet PostgreSQL (offline)';class='org.postgresql.Driver';custom='true';embedded='false';port='5432';url='jdbc:postgresql://{host}[:{port}]/[{database}]';description='Pinned local PostgreSQL driver libraries for Levmet IAM connections'}
    foreach ($key in $attributes.Keys) { $driver.SetAttribute($key,$attributes[$key]) }
    foreach ($jar in Get-ChildItem -LiteralPath $Settings.driverDirectory -Filter '*.jar' -File | Sort-Object Name) {
        $library = $document.CreateElement('library'); $library.SetAttribute('type','jar'); $library.SetAttribute('path',$jar.FullName); $library.SetAttribute('custom','true')
        $driver.AppendChild($library) | Out-Null
    }
    $document.DocumentElement.AppendChild($driver) | Out-Null
    Backup-SetupFile $driversPath $BackupDirectory
    [IO.Directory]::CreateDirectory((Split-Path -Parent $driversPath)) | Out-Null
    # DBeaver reads this XML through a character Reader. A UTF-8 BOM silently
    # prevented driver loading in the bundled 26.2 build; emit UTF-8 without BOM.
    $writerSettings = [Xml.XmlWriterSettings]::new()
    $writerSettings.Encoding = [Text.UTF8Encoding]::new($false)
    $writerSettings.Indent = $true
    $writer = [Xml.XmlWriter]::Create($driversPath,$writerSettings)
    try { $document.Save($writer) } finally { $writer.Dispose() }
}

function Set-DBeaverProfile {
    param($Settings, [string]$BackupDirectory)
    Assert-DBeaverWorkspaceClosed $Settings.dbeaverWorkspace
    if ((Get-DBeaverDriverSource $Settings) -eq 'offline') { Set-DBeaverOfflineDriver $Settings $BackupDirectory }
    $sourcesPath = Join-Path $Settings.dbeaverWorkspace 'General\.dbeaver\data-sources.json'
    $sources = if (Test-Path -LiteralPath $sourcesPath) { Get-Content -LiteralPath $sourcesPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { [PSCustomObject]@{connections=[PSCustomObject]@{}} }
    if (-not $sources.PSObject.Properties['connections']) { $sources | Add-Member -NotePropertyName connections -NotePropertyValue ([PSCustomObject]@{}) }
    # Only the deterministic setup-owned ID is updated. Other profiles are preserved.
    $profile = [ordered]@{
        provider='postgresql'; driver=(Get-DBeaverDriverId $Settings); name=$Settings.connectionName; 'save-password'=$true
        configuration=[ordered]@{
            host='127.0.0.1';port=[string]$Settings.localPort;database=$Settings.database;configurationType='MANUAL';type='dev';user=$Settings.email
            properties=@{sslmode='disable';ssl='false';connectTimeout='20'}
            'auth-model'='native';'auth-properties'=@{userName=$Settings.email;userPassword=''}
        }
    }
    $sources.connections | Add-Member -NotePropertyName $Settings.connectionId -NotePropertyValue $profile -Force
    Backup-SetupFile $sourcesPath $BackupDirectory
    Write-JsonFile $sourcesPath $sources
}

function Test-DBeaverProfile {
    param($Settings)
    $sources = Get-Content -LiteralPath (Join-Path $Settings.dbeaverWorkspace 'General\.dbeaver\data-sources.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $property = $sources.connections.PSObject.Properties[$Settings.connectionId]
    if (-not $property) { throw 'The managed DBeaver connection profile is missing.' }
    $profile = $property.Value
    if ($profile.provider -ne 'postgresql' -or $profile.driver -ne (Get-DBeaverDriverId $Settings) -or $profile.configuration.host -ne '127.0.0.1' -or $profile.configuration.port -ne [string]$Settings.localPort -or $profile.configuration.database -ne $Settings.database -or $profile.configuration.user -ne $Settings.email -or $profile.configuration.properties.sslmode -ne 'disable') { throw 'The DBeaver profile no longer matches the setup settings.' }
    # Maven resolution/JDBC loading is verified by the user's DBeaver Test Connection.
    if ((Get-DBeaverDriverSource $Settings) -eq 'artifactory') { return $true }
    $drivers = [xml](Get-Content -LiteralPath (Join-Path $Settings.dbeaverWorkspace '.metadata\.config\drivers.xml') -Raw)
    $libraries = @($drivers.SelectNodes('/drivers/driver[@provider="postgresql" and @id="levmet-postgres-offline"]/library[not(@disabled="true")]'))
    if ($libraries.Count -ne 11) { throw 'DBeaver must have all eleven local driver libraries configured.' }
    foreach ($library in $libraries) {
        if ($library.path.StartsWith('maven:') -or -not (Test-Path -LiteralPath $library.path -PathType Leaf)) { throw 'A DBeaver driver entry requires a download or references a missing file.' }
    }
    return $true
}

function Set-RuntimeEnvironment {
    param($Settings)
    $env:SSL_CERT_FILE = $Settings.caBundlePath
    $env:CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE = $Settings.caBundlePath
    # Pin SDK Python for these commands only; do not change other Python installations.
    $env:CLOUDSDK_PYTHON = $Settings.pythonPath
    $env:CLOUDSDK_CONFIG = $Settings.gcloudConfigDirectory
    $env:GOOGLE_APPLICATION_CREDENTIALS = Join-Path $Settings.gcloudConfigDirectory 'application_default_credentials.json'
}

function Test-InstalledEnvironment {
    param($Settings, [switch]$ProcessOnly)
    $scope = if ($ProcessOnly) { 'Process' } else { 'User' }
    $path = [Environment]::GetEnvironmentVariable('Path',$scope)
    foreach ($directory in @((Split-Path -Parent $Settings.gcloudPath),(Split-Path -Parent $Settings.codexPath),(Split-Path -Parent $Settings.proxyPath))) {
        if (-not @($path -split ';' | Where-Object { [Environment]::ExpandEnvironmentVariables($_).Trim().Trim('"').TrimEnd('\') -ieq $directory.TrimEnd('\') }).Count) { throw 'A required directory is missing from PATH. Rerun Install.' }
    }
    foreach ($name in @('SSL_CERT_FILE','CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE')) {
        if ([Environment]::GetEnvironmentVariable($name,$scope) -ine $Settings.caBundlePath) { throw "The $name environment setting changed. Rerun Install." }
    }
    if (-not (Test-Path -LiteralPath $Settings.caBundlePath -PathType Leaf)) { throw 'The installed CA bundle is missing.' }
    if (-not (Test-Path -LiteralPath $Settings.dbeaverPath -PathType Leaf)) { throw 'The DBeaver application is missing.' }
}

function Get-ProxyArguments {
    param($Settings)
    $arguments = @('--auto-iam-authn','--address','127.0.0.1','--port',[string]$Settings.localPort)
    if ($Settings.usePrivateIp) { $arguments += '--private-ip' }
    $arguments += $Settings.instanceConnectionName
    return $arguments
}

function Test-LocalPort {
    param([int]$Port)
    $client = [Net.Sockets.TcpClient]::new()
    try { $task = $client.ConnectAsync('127.0.0.1',$Port); return ($task.Wait(500) -and $client.Connected) }
    catch { return $false } finally { $client.Dispose() }
}

function Invoke-DatabaseVerification {
    param($Settings)
    Set-RuntimeEnvironment $Settings
    $process = $null
    $logDirectory = Join-Path $Settings.installRoot 'logs'
    [IO.Directory]::CreateDirectory($logDirectory) | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $stdout = Join-Path $logDirectory "proxy-$stamp.stdout.log"
    $stderr = Join-Path $logDirectory "proxy-$stamp.stderr.log"
    if (Test-LocalPort $Settings.localPort) {
        $listener = @(Get-NetTCPConnection -LocalPort $Settings.localPort -State Listen -ErrorAction SilentlyContinue)
        if ($listener.Count -eq 0) { throw 'The local port is occupied, but its process could not be checked.' }
        foreach ($owner in @($listener.OwningProcess | Select-Object -Unique)) {
            $running = Get-CimInstance Win32_Process -Filter "ProcessId = $owner" -ErrorAction Stop
            if (-not $running.CommandLine -or $running.Name -notlike '*cloud-sql-proxy*' -or -not $running.CommandLine.Contains($Settings.instanceConnectionName) -or -not $running.CommandLine.Contains('--auto-iam-authn')) {
                throw 'The configured local port belongs to another process. Choose a free localPort; setup will not stop it.'
            }
        }
    } else {
        $process = Start-Process -FilePath $Settings.proxyPath -ArgumentList (Get-ProxyArguments $Settings) -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $ready = $false
        for ($attempt=0; $attempt -lt 40; $attempt++) {
            if ($process.HasExited) { throw "The proxy exited. See $stderr" }
            if (Test-LocalPort $Settings.localPort) { $ready=$true; break }
            Start-Sleep -Milliseconds 250
        }
        if (-not $ready) { if (-not $process.HasExited) { $process.Kill() }; throw "The proxy did not start. See $stderr" }
    }
    try {
        & $Settings.pythonPath (Join-Path $Settings.installRoot 'scripts\db_probe.py') --settings (Join-Path $Settings.installRoot 'settings.json')
        if ($LASTEXITCODE -ne 0) { throw "The database query failed. Config retained. Proxy logs: $logDirectory" }
    } finally {
        # Stop only the temporary process this invocation created. Never stop an existing tunnel.
        if ($process -and -not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    }
}

function Remove-CompletedConfig {
    param($Config, $Report, [switch]$DBeaverConfirmed)
    if (-not $DBeaverConfirmed) { throw 'Keep config.local.json until the user confirms Test Connection succeeds for the saved DBeaver profile.' }
    if (-not $Report.allChecksPassed -or $Report.configSha256 -ne $Config.configSha256) { throw 'The config does not have a matching successful verification. It has not been deleted.' }
    if ([DateTime]::UtcNow - [DateTime]::Parse($Report.verifiedAtUtc).ToUniversalTime() -gt [TimeSpan]::FromMinutes(15)) { throw 'Verification is older than 15 minutes. Run Verify again before deleting the config.' }
    Test-AssetHash $Config.configPath $Config.configSha256
    Remove-Item -LiteralPath $Config.configPath -ErrorAction Stop
    if (Test-Path -LiteralPath $Config.configPath) { throw 'Could not remove config.local.json.' }
}

Export-ModuleMember -Function *
