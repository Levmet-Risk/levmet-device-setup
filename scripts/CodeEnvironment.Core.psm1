Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not ('Levmet.Setup.EnvironmentEnvelope' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'EnvironmentTransfer.cs') }
Add-Type -AssemblyName System.Security

function Get-CodeEnvironmentCatalog {
    Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\code-environment.json') -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-CodeProperty($Object, [string]$Name, $Default = $null) {
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $Default
}

function Get-CodeEnvironmentValue([string]$Name) {
    # Persistent settings take precedence over stale values inherited by this shell.
    foreach ($scope in @('User','Machine','Process')) {
        $value = [Environment]::GetEnvironmentVariable($Name, $scope)
        if (-not [string]::IsNullOrEmpty($value)) { return $value }
    }
    return $null
}

function Resolve-CodePath([string]$Path, [string]$Base) {
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if ([string]::IsNullOrWhiteSpace($expanded) -or $expanded -match '[%\r\n\x00]') { throw [Levmet.Setup.EnvironmentSetupException]::new('A configured path is blank or contains an unresolved variable/control character.') }
    if (-not [IO.Path]::IsPathRooted($expanded)) { $expanded = Join-Path $Base $expanded }
    return [IO.Path]::GetFullPath($expanded).TrimEnd('\')
}

function Read-CodeEnvironmentContext {
    param([string]$ConfigPath, [string]$CodeRoot, [string]$Email, [string]$DeviceSetupRoot)
    $repo = Split-Path -Parent $PSScriptRoot
    $config = Get-Content -LiteralPath (Join-Path $repo 'code-environment.example.json') -Raw | ConvertFrom-Json
    if ($ConfigPath) {
        $inputConfig = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($property in $inputConfig.PSObject.Properties) {
            if (-not $config.PSObject.Properties[$property.Name]) { throw [Levmet.Setup.EnvironmentSetupException]::new('Unsupported code environment config field.') }
            $config.($property.Name) = $property.Value
        }
    }
    if ($config.schemaVersion -ne 1) { throw [Levmet.Setup.EnvironmentSetupException]::new('Unsupported code environment config version.') }
    if ($CodeRoot) { $config.codeRoot = $CodeRoot }
    if ($Email) { $config.email = $Email }
    if ($DeviceSetupRoot) { $config.deviceSetupRoot = $DeviceSetupRoot }
    $code = Resolve-CodePath $config.codeRoot $repo
    if (-not (Test-Path -LiteralPath $code -PathType Container)) { throw [Levmet.Setup.EnvironmentSetupException]::new('Code directory was not found. Set codeRoot in code-environment.local.json or pass -CodeRoot.') }
    $risk = if ($config.riskRoot) { Resolve-CodePath $config.riskRoot $repo } else { Split-Path -Parent $code }
    if (-not (Test-Path -LiteralPath (Join-Path $risk 'All trades') -PathType Container) -or -not (Test-Path -LiteralPath (Join-Path $risk 'FTP files') -PathType Container)) {
        throw [Levmet.Setup.EnvironmentSetupException]::new('riskRoot must contain the synced All trades and FTP files directories. Sync them locally or correct riskRoot.')
    }
    $deviceRoot = $config.deviceSetupRoot
    if (-not $deviceRoot) { $deviceRoot = Get-CodeEnvironmentValue 'LEVMET_SETUP_HOME' }
    if (-not $deviceRoot) { $deviceRoot = Join-Path $env:LOCALAPPDATA 'Levmet\DeviceSetup' }
    $deviceRoot = Resolve-CodePath $deviceRoot $repo
    $settingsPath = Join-Path $deviceRoot 'settings.json'
    $settings = if (Test-Path -LiteralPath $settingsPath -PathType Leaf) { Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
    $emailValue = $config.email
    if (-not $emailValue) { $emailValue = Get-CodeProperty $settings 'email' }
    if (-not $emailValue) { $emailValue = Get-CodeEnvironmentValue 'user_email' }
    if ($emailValue -and $emailValue -notmatch '^[A-Za-z0-9._+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$') { throw [Levmet.Setup.EnvironmentSetupException]::new('Set email to the Google/IAM identity used by device setup.') }
    $port = [string](Get-CodeProperty $settings 'localPort' 5433)
    if ($port -notmatch '^\d+$' -or [int]$port -lt 1024 -or [int]$port -gt 65535) { throw [Levmet.Setup.EnvironmentSetupException]::new('Invalid tunnel port in device settings.') }
    $database = [string](Get-CodeProperty $settings 'database' 'postgres')
    $oneDrive = $config.oneDriveRoot
    if (-not $oneDrive) {
        $candidate = Join-Path $env:USERPROFILE 'OneDrive - Levmet'
        if (Test-Path -LiteralPath $candidate -PathType Container) { $oneDrive = $candidate }
    }
    if ($oneDrive) { $oneDrive = Resolve-CodePath $oneDrive $repo }
    $roots = @{codeRoot=$code;riskRoot=$risk;oneDriveRoot=$oneDrive;userProfile=$env:USERPROFILE;localAppData=$env:LOCALAPPDATA}
    $dbUrl = if ($emailValue) { 'postgresql+psycopg2://' + [Uri]::EscapeDataString($emailValue) + '@127.0.0.1:' + $port + '/' + [Uri]::EscapeDataString($database) } else { $null }
    $derived = @{email=$emailValue;dbHost='127.0.0.1';dbPort=$port;dbName=$database;dbUrl=$dbUrl}
    $catalog = Get-CodeEnvironmentCatalog
    foreach ($field in @('pathOverrides','valueOverrides')) {
        if ($null -eq $config.$field -or $config.$field -isnot [PSCustomObject]) { throw [Levmet.Setup.EnvironmentSetupException]::new("$field must be a JSON object.") }
        foreach ($property in $config.$field.PSObject.Properties) {
            $entry = @($catalog.variables | Where-Object name -CEQ $property.Name)
            $allowedKind = if ($field -eq 'pathOverrides') { 'path' } else { 'setting' }
            if ($entry.Count -ne 1 -or $entry[0].kind -ne $allowedKind) { throw [Levmet.Setup.EnvironmentSetupException]::new("Unsupported $field name. Secret values belong in the encrypted transfer or masked SetSecret prompt.") }
            if ($property.Value -isnot [string] -or $property.Value.Length -gt 32766 -or $property.Value.Contains([char]0)) { throw [Levmet.Setup.EnvironmentSetupException]::new('Config overrides must be valid environment strings.') }
        }
    }
    [PSCustomObject]@{config=$config;roots=$roots;derived=$derived;settingsFound=($null -ne $settings);pythonPath=(Get-CodeProperty $settings 'pythonPath');repositoryRoot=$repo}
}

function ConvertTo-CodePortablePath([string]$Value, [hashtable]$Roots) {
    if (-not [IO.Path]::IsPathRooted([Environment]::ExpandEnvironmentVariables($Value))) { return [PSCustomObject]@{root='unmapped';relative=''} }
    $full = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Value)).TrimEnd('\')
    foreach ($key in @($Roots.Keys | Where-Object { $Roots[$_] } | Sort-Object { ([string]$Roots[$_]).Length } -Descending)) {
        $root = [IO.Path]::GetFullPath($Roots[$key]).TrimEnd('\')
        if ($full -ieq $root) { return [PSCustomObject]@{root=$key;relative=''} }
        if ($full.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { return [PSCustomObject]@{root=$key;relative=$full.Substring($root.Length + 1)} }
    }
    # An unrelated absolute path must be supplied explicitly on the destination.
    return [PSCustomObject]@{root='unmapped';relative=''}
}

function Resolve-CodePortablePath($Entry, [hashtable]$Roots) {
    if ($Entry.root -eq 'unmapped') { return $null }
    if (-not $Roots.ContainsKey([string]$Entry.root)) { throw [Levmet.Setup.EnvironmentSetupException]::new('Transfer contains an unknown path root.') }
    $relative = [string]$Entry.relative
    if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)|[:%\r\n\x00]') { throw [Levmet.Setup.EnvironmentSetupException]::new('Transfer contains an unsafe relative path.') }
    if (-not $Roots[$Entry.root]) { return $null }
    $root = [IO.Path]::GetFullPath($Roots[$Entry.root]).TrimEnd('\')
    $full = if ($relative) { [IO.Path]::GetFullPath((Join-Path $root $relative)) } else { $root }
    if ($full -ine $root -and -not $full.StartsWith($root + '\',[StringComparison]::OrdinalIgnoreCase)) { throw [Levmet.Setup.EnvironmentSetupException]::new('Transfer path escapes its destination root.') }
    return $full
}

function Get-CodeGraphSelectors([hashtable]$Values) {
    $service = if ($Values['MS_GRAPH_SECRET_SERVICE']) { $Values['MS_GRAPH_SECRET_SERVICE'] } else { 'ms_graph_secret' }
    $user = if ($Values['MS_GRAPH_SECRET_USER']) { $Values['MS_GRAPH_SECRET_USER'] } else { 'RiskReports' }
    foreach ($value in @($service,$user)) { if ($value.Length -gt 256 -or $value -match '[\r\n\x00]') { throw [Levmet.Setup.EnvironmentSetupException]::new('Invalid Graph credential selector.') } }
    [PSCustomObject]@{service=$service;user=$user}
}

function Get-CodeGraphCredential($Selectors) {
    $credential = [Levmet.Setup.CredentialStore]::Read($Selectors.service)
    if ($credential -and $credential.UserName -ceq $Selectors.user) { return $credential }
    $credential = [Levmet.Setup.CredentialStore]::Read($Selectors.user + '@' + $Selectors.service)
    if ($credential -and $credential.UserName -ceq $Selectors.user) { return $credential }
    return $null
}

function New-CodeEnvironmentTransfer {
    param($Context, [hashtable]$CurrentValues = $null, [switch]$SkipCredentialStore)
    $values = @{}
    $entries = @()
    $missing = @()
    foreach ($entry in (Get-CodeEnvironmentCatalog).variables) {
        if ($entry.kind -notin @('path','setting','secret')) { continue }
        $value = if ($null -ne $CurrentValues) { $CurrentValues[$entry.name] } else { Get-CodeEnvironmentValue $entry.name }
        if ($null -eq $value) {
            if ($entry.kind -eq 'secret') { $missing += $entry.name }
            continue
        }
        $values[$entry.name] = $value
        if ($entry.kind -eq 'path') {
            $portable = ConvertTo-CodePortablePath $value $Context.roots
            $entries += [PSCustomObject]@{name=$entry.name;kind='path';root=$portable.root;relative=$portable.relative}
        } else { $entries += [PSCustomObject]@{name=$entry.name;kind=$entry.kind;value=$value} }
    }
    $selectors = Get-CodeGraphSelectors $values
    $credential = if ($SkipCredentialStore) { $null } else { Get-CodeGraphCredential $selectors }
    $graph = if ($credential) { [PSCustomObject]@{service=$selectors.service;user=$selectors.user;blobBase64=$credential.BlobBase64} } else { $null }
    [PSCustomObject]@{schemaVersion=1;purpose='levmet-code-environment';entries=@($entries);graph=$graph;missingSecrets=@($missing)}
}

function Test-CodeTransferPayload($Payload) {
    if ($Payload.schemaVersion -ne 1 -or $Payload.purpose -ne 'levmet-code-environment') { throw [Levmet.Setup.EnvironmentSetupException]::new('Unexpected transfer payload.') }
    $catalog = Get-CodeEnvironmentCatalog
    $seen = @{}
    foreach ($item in $Payload.entries) {
        $entry = @($catalog.variables | Where-Object name -CEQ $item.name)
        if ($entry.Count -ne 1 -or $entry[0].kind -notin @('secret','setting','path') -or $entry[0].kind -ne $item.kind -or $seen.ContainsKey($item.name)) { throw [Levmet.Setup.EnvironmentSetupException]::new('Transfer contains an unsupported or duplicate variable.') }
        $seen[$item.name] = $true
        if ($item.kind -eq 'path') {
            Resolve-CodePortablePath $item @{codeRoot='C:\fixture';riskRoot='C:\fixture';oneDriveRoot='C:\fixture';userProfile='C:\fixture';localAppData='C:\fixture'} | Out-Null
        } elseif ($item.value -isnot [string] -or $item.value.Length -gt 32766 -or $item.value.Contains([char]0)) { throw [Levmet.Setup.EnvironmentSetupException]::new('Transfer contains an invalid environment value.') }
    }
    if ($Payload.graph) {
        Get-CodeGraphSelectors @{MS_GRAPH_SECRET_SERVICE=$Payload.graph.service;MS_GRAPH_SECRET_USER=$Payload.graph.user} | Out-Null
        if ([string]::IsNullOrEmpty($Payload.graph.service) -or [string]::IsNullOrEmpty($Payload.graph.user)) { throw [Levmet.Setup.EnvironmentSetupException]::new('Transfer has blank Graph credential selectors.') }
        $blob = [Convert]::FromBase64String($Payload.graph.blobBase64)
        if ($blob.Length -eq 0 -or $blob.Length -gt 2560) { throw [Levmet.Setup.EnvironmentSetupException]::new('Transfer has an invalid Graph credential.') }
        [Array]::Clear($blob,0,$blob.Length)
    }
}

function Write-CodeTransferFile($Payload, [string]$Path, [Security.SecureString]$Password) {
    Test-CodeTransferPayload $Payload
    if (Test-Path -LiteralPath $Path) { throw [Levmet.Setup.EnvironmentSetupException]::new('Transfer file already exists. Choose a new filename.') }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Payload | ConvertTo-Json -Depth 15 -Compress))
    try { $encrypted = [Levmet.Setup.EnvironmentEnvelope]::Protect($bytes,$Password) }
    finally { [Array]::Clear($bytes,0,$bytes.Length) }
    $full = [IO.Path]::GetFullPath($Path)
    [IO.Directory]::CreateDirectory((Split-Path -Parent $full)) | Out-Null
    $stream = [IO.File]::Open($full,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $outBytes = [Text.Encoding]::ASCII.GetBytes($encrypted); $stream.Write($outBytes,0,$outBytes.Length) } finally { $stream.Dispose() }
}

function Read-CodeTransferFile([string]$Path, [Security.SecureString]$Password) {
    if ((Get-Item -LiteralPath $Path).Length -gt 8MB) { throw [Levmet.Setup.EnvironmentSetupException]::new('Transfer file is too large.') }
    $bytes = [Levmet.Setup.EnvironmentEnvelope]::Unprotect([IO.File]::ReadAllText($Path),$Password)
    try { $payload = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json }
    finally { [Array]::Clear($bytes,0,$bytes.Length) }
    Test-CodeTransferPayload $payload
    return $payload
}

function New-CodeEnvironmentPlan {
    param($Context, $Transfer = $null, [hashtable]$CurrentValues = $null)
    if ($Transfer) { Test-CodeTransferPayload $Transfer }
    $imported = @{}
    if ($Transfer) { foreach ($item in $Transfer.entries) { $imported[$item.name] = $item } }
    $rows = @()
    foreach ($entry in (Get-CodeEnvironmentCatalog).variables) {
        $name = $entry.name
        $current = if ($null -ne $CurrentValues) { $CurrentValues[$name] } else { Get-CodeEnvironmentValue $name }
        $desired = $null; $source = 'code default'; $state = 'Uses code default / caller value'; $pathStatus = ''
        if ($entry.kind -eq 'derived') {
            $desired = $Context.derived[$entry.derive]; $source = 'device settings / target identity'
            $state = if ($desired) { 'Configured' } else { 'Needs IAM email or device settings' }
        } elseif ($entry.kind -eq 'path') {
            $override = Get-CodeProperty $Context.config.pathOverrides $name
            if ($override) { $desired = Resolve-CodePath $override $Context.repositoryRoot; $source = 'config' }
            elseif ($imported.ContainsKey($name)) { $desired = Resolve-CodePortablePath $imported[$name] $Context.roots; $source = 'rebased transfer' }
            elseif ($Context.roots[$entry.root]) { $desired = Resolve-CodePortablePath $entry $Context.roots; $source = 'target paths' }
            elseif ($current) { $desired = $current; $source = 'existing' }
            $state = if ($desired) { 'Configured' } else { 'Needs path override' }
            if ($desired) {
                if ($entry.pathType -eq 'output') { $pathStatus = 'Output/cache; app creates it' }
                elseif (Test-Path -LiteralPath $desired -PathType $(if ($entry.pathType -eq 'file') { 'Leaf' } else { 'Container' })) { $pathStatus = 'Present (contents not tested)' }
                else { $pathStatus = 'Missing input path' }
            }
        } elseif ($entry.kind -in @('setting','secret')) {
            $override = Get-CodeProperty $Context.config.valueOverrides $name
            if (-not [string]::IsNullOrEmpty($override)) { $desired = $override; $source = 'config' }
            elseif ($imported.ContainsKey($name)) { $desired = $imported[$name].value; $source = 'encrypted transfer' }
            elseif ($current) { $desired = $current; $source = 'existing' }
            if ($Transfer -and $Transfer.graph -and $name -in @('MS_GRAPH_SECRET_SERVICE','MS_GRAPH_SECRET_USER')) {
                $graphValue = if ($name -eq 'MS_GRAPH_SECRET_SERVICE') { $Transfer.graph.service } else { $Transfer.graph.user }
                if ($override -and $override -cne $graphValue) { throw [Levmet.Setup.EnvironmentSetupException]::new('Graph selectors in config differ from the transferred credential.') }
                $desired = $graphValue; $source = 'encrypted transfer'
            }
            if ($desired) { $state = 'Configured' }
            elseif ($entry.kind -eq 'secret') { $state = 'Missing credential' }
        } else {
            $state = switch ($entry.kind) {
                'run' { 'Per-run option; not persisted' }
                'runtime' { 'Provided by OS / launcher' }
                'app-local' { 'App-local option; not persisted globally' }
                'test' { 'Test-only; not persisted' }
            }
        }
        $action = if ($null -eq $desired) { 'None' } elseif ($current -ceq $desired) { 'Unchanged' } elseif ([string]::IsNullOrEmpty($current)) { 'Set' } else { 'Conflict' }
        $rows += [PSCustomObject]@{Name=$name;Kind=$entry.kind;Action=$action;State=$state;PathStatus=$pathStatus;Source=$source;Current=$current;Desired=$desired}
    }
    return $rows
}

function Get-CodeEnvironmentReport($Plan) {
    @($Plan | Select-Object Name,Kind,Action,State,PathStatus,Source)
}

function Save-CodeEnvironmentBackup($Snapshot, [string]$Directory) {
    [IO.Directory]::CreateDirectory($Directory) | Out-Null
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Snapshot | ConvertTo-Json -Depth 15 -Compress))
    try { $protected = [Security.Cryptography.ProtectedData]::Protect($bytes,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser) }
    finally { [Array]::Clear($bytes,0,$bytes.Length) }
    $path = Join-Path $Directory ('environment-' + [guid]::NewGuid().ToString('N') + '.dpapi')
    [IO.File]::WriteAllBytes($path,$protected)
    return $path
}

function Restore-CodeEnvironmentSnapshot($Snapshot, [switch]$ProcessOnly) {
    $allowed = @((Get-CodeEnvironmentCatalog).variables | Where-Object kind -in @('derived','path','setting','secret') | Select-Object -ExpandProperty name)
    foreach ($item in $Snapshot.environment) {
        if ($item.name -notin $allowed) { throw [Levmet.Setup.EnvironmentSetupException]::new('Backup contains an unsupported environment variable.') }
    }
    foreach ($item in $Snapshot.environment) {
        if (-not $ProcessOnly) { [Environment]::SetEnvironmentVariable($item.name,$item.value,'User') }
        [Environment]::SetEnvironmentVariable($item.name,$item.value,'Process')
    }
    if ($Snapshot.graphTarget) {
        if ($ProcessOnly) { throw [Levmet.Setup.EnvironmentSetupException]::new('Process-only restore cannot change Windows credentials.') }
        if ($Snapshot.graphPrevious) { [Levmet.Setup.CredentialStore]::Write($Snapshot.graphTarget,$Snapshot.graphPrevious.UserName,$Snapshot.graphPrevious.BlobBase64) }
        else { [Levmet.Setup.CredentialStore]::Delete($Snapshot.graphTarget) }
    }
}

function Restore-CodeEnvironmentBackup([string]$Path) {
    $bytes = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($Path),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    try { $snapshot = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json }
    finally { [Array]::Clear($bytes,0,$bytes.Length) }
    if ($snapshot.schemaVersion -ne 1 -or $snapshot.purpose -ne 'levmet-code-environment-backup') { throw [Levmet.Setup.EnvironmentSetupException]::new('Unexpected backup payload.') }
    Restore-CodeEnvironmentSnapshot $snapshot
}

function Set-CodeEnvironmentPlan {
    param($Plan, $Graph = $null, [string]$BackupDirectory, [switch]$ReplaceExisting, [switch]$ProcessOnly)
    $changes = @($Plan | Where-Object { $_.Action -in @('Set','Conflict') })
    if (-not $ReplaceExisting -and @($changes | Where-Object Action -eq 'Conflict').Count) { throw [Levmet.Setup.EnvironmentSetupException]::new('Existing values differ from the plan. Review the variable names and use -ReplaceExisting to replace them with a protected backup.') }
    foreach ($change in $changes) {
        if ($change.Desired -isnot [string] -or $change.Desired.Length -gt 32766 -or $change.Desired.Contains([char]0)) { throw [Levmet.Setup.EnvironmentSetupException]::new('Invalid proposed environment value.') }
    }
    $target = $null; $previous = $null; $writeGraph = $false
    if ($Graph) {
        if ($ProcessOnly) { throw [Levmet.Setup.EnvironmentSetupException]::new('Process-only tests cannot import Windows credentials.') }
        $main = [Levmet.Setup.CredentialStore]::Read($Graph.service)
        # Preserve another user's credential under the same service name.
        $target = if ($main -and $main.UserName -cne $Graph.user) { $Graph.user + '@' + $Graph.service } else { $Graph.service }
        $previous = [Levmet.Setup.CredentialStore]::Read($target)
        $writeGraph = -not ($previous -and $previous.UserName -ceq $Graph.user -and $previous.BlobBase64 -ceq $Graph.blobBase64)
        if ($writeGraph -and $previous -and -not $ReplaceExisting) { throw [Levmet.Setup.EnvironmentSetupException]::new('An existing Graph credential differs. Use -ReplaceExisting after reviewing the transfer source.') }
    }
    if ($changes.Count -eq 0 -and -not $writeGraph) { return [PSCustomObject]@{Changed=0;CredentialChanged=$false;BackupPath=$null} }
    $old = @(); $processBefore = @{}
    foreach ($change in $changes) {
        $scope = if ($ProcessOnly) { 'Process' } else { 'User' }
        $old += [PSCustomObject]@{name=$change.Name;value=[Environment]::GetEnvironmentVariable($change.Name,$scope)}
        $processBefore[$change.Name] = [Environment]::GetEnvironmentVariable($change.Name,'Process')
    }
    $snapshot = [PSCustomObject]@{schemaVersion=1;purpose='levmet-code-environment-backup';environment=@($old);graphTarget=$(if ($writeGraph) {$target} else {$null});graphPrevious=$previous}
    $backup = Save-CodeEnvironmentBackup $snapshot $BackupDirectory
    try {
        foreach ($change in $changes) {
            if (-not $ProcessOnly) { [Environment]::SetEnvironmentVariable($change.Name,$change.Desired,'User') }
            [Environment]::SetEnvironmentVariable($change.Name,$change.Desired,'Process')
        }
        if ($writeGraph) { [Levmet.Setup.CredentialStore]::Write($target,$Graph.user,$Graph.blobBase64) }
    } catch {
        try {
            Restore-CodeEnvironmentSnapshot $snapshot -ProcessOnly:$ProcessOnly
            foreach ($name in $processBefore.Keys) { [Environment]::SetEnvironmentVariable($name,$processBefore[$name],'Process') }
        } catch { throw [Levmet.Setup.EnvironmentSetupException]::new("Apply failed and rollback was incomplete. Restore from the protected backup: $backup") }
        throw [Levmet.Setup.EnvironmentSetupException]::new('Apply failed. The previous environment and credential were restored.')
    }
    [PSCustomObject]@{Changed=$changes.Count;CredentialChanged=$writeGraph;BackupPath=$backup}
}

function Set-CodeEnvironmentSecret([string]$Name, [Security.SecureString]$Secret, [string]$BackupDirectory, [switch]$ReplaceExisting) {
    if (-not @((Get-CodeEnvironmentCatalog).variables | Where-Object { $_.name -ceq $Name -and $_.kind -eq 'secret' }).Count) { throw [Levmet.Setup.EnvironmentSetupException]::new('Name is not a supported codebase secret variable.') }
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret)
    try { $value = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    if ([string]::IsNullOrEmpty($value)) { throw [Levmet.Setup.EnvironmentSetupException]::new('Secret cannot be empty.') }
    $current = Get-CodeEnvironmentValue $Name
    $action = if ($current -ceq $value) {'Unchanged'} elseif ($current) {'Conflict'} else {'Set'}
    Set-CodeEnvironmentPlan @([PSCustomObject]@{Name=$Name;Action=$action;Desired=$value}) -BackupDirectory $BackupDirectory -ReplaceExisting:$ReplaceExisting
}

Export-ModuleMember -Function *
