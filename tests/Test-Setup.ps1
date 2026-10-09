$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repo 'scripts\Setup.Core.psm1') -Force -DisableNameChecking
$testRoot = Join-Path $repo ('.cache\tests-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$script:checks = 0
function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:checks++
}
function Assert-Throws([scriptblock]$Action, [string]$Message) {
    $caught = $false
    try { & $Action | Out-Null } catch { $caught = $true }
    Assert $caught $Message
}
$configPath = Join-Path $testRoot 'config.local.json'
$inputConfig = Get-Content -LiteralPath (Join-Path $repo 'config.example.json') -Raw | ConvertFrom-Json
$inputConfig.email = 'test.user@example.com'
$inputConfig.installRoot = Join-Path $testRoot 'installed'
$inputConfig.dbeaverWorkspace = Join-Path $testRoot 'workspace with spaces'
Write-JsonFile $configPath $inputConfig
$config = Read-SetupConfig $configPath $repo
Assert ($config.email -eq 'test.user@example.com') 'Valid config was rejected.'
Assert ($config.dbeaverDriverSource -eq 'artifactory') 'New configurations must use Artifactory.'
$inputConfig.PSObject.Properties.Remove('dbeaverDriverSource')
Write-JsonFile $configPath $inputConfig
Assert ((Read-SetupConfig $configPath $repo).dbeaverDriverSource -eq 'artifactory') 'Older input configs must default to Artifactory on reinstall.'
$inputConfig | Add-Member -NotePropertyName dbeaverDriverSource -NotePropertyValue 'invalid'
Write-JsonFile $configPath $inputConfig
Assert-Throws { Read-SetupConfig $configPath $repo } 'Invalid driver source was accepted.'
$inputConfig.dbeaverDriverSource = 'artifactory'
Assert-Throws { Read-SetupConfig (Join-Path $repo 'config.example.json') $repo } 'Example config must not be accepted as live input.'
$inputConfig | Add-Member -NotePropertyName password -NotePropertyValue 'not-a-real-secret'
Write-JsonFile $configPath $inputConfig
Assert-Throws { Read-SetupConfig $configPath $repo } 'Unexpected secret field was accepted.'
$inputConfig.PSObject.Properties.Remove('password')
Write-JsonFile $configPath $inputConfig
$config = Read-SetupConfig $configPath $repo
$originalPath = $env:Path
$userPathBefore = [Environment]::GetEnvironmentVariable('Path','User')
try {
    Add-UserPath @($testRoot,$testRoot.ToUpperInvariant()) -ProcessOnly
    Assert (@($env:Path -split ';' | Where-Object { $_ -ieq $testRoot }).Count -eq 1) 'PATH added a duplicate entry.'
    Assert ([Environment]::GetEnvironmentVariable('Path','User') -ceq $userPathBefore) 'Process-only test changed persistent PATH.'
} finally { $env:Path = $originalPath }
$driverDir = Join-Path $testRoot 'drivers'
[IO.Directory]::CreateDirectory($driverDir) | Out-Null
Get-ChildItem -LiteralPath (Join-Path $repo 'assets\drivers') -File -Filter '*.jar' | Copy-Item -Destination $driverDir
$sourcesFile = Join-Path $config.dbeaverWorkspace 'General\.dbeaver\data-sources.json'
Write-JsonFile $sourcesFile @{connections=@{existing=@{name='Preserve me';driver='sqlite'}};folders=@{team=@{name='Existing folder'}}}
$driversFile = Join-Path $config.dbeaverWorkspace '.metadata\.config\drivers.xml'
[IO.Directory]::CreateDirectory((Split-Path -Parent $driversFile)) | Out-Null
[IO.File]::WriteAllText($driversFile,'<drivers><driver id="existing-sqlite" provider="generic" name="Existing SQLite" class="org.sqlite.JDBC" /></drivers>')
$settings = [PSCustomObject]@{dbeaverWorkspace=$config.dbeaverWorkspace;driverDirectory=$driverDir;connectionId='levmet-iam-test';connectionName='Managed test';email=$config.email;localPort=15433;database='postgres'}
Set-DBeaverProfile $settings (Join-Path $testRoot 'backups')
Set-DBeaverProfile $settings (Join-Path $testRoot 'backups')
$saved = Get-Content -LiteralPath $sourcesFile -Raw | ConvertFrom-Json
Assert ($saved.connections.existing.name -eq 'Preserve me') 'Existing profile was changed.'
Assert ($saved.folders.team.name -eq 'Existing folder') 'Existing folder was changed.'
Assert (@($saved.connections.PSObject.Properties).Count -eq 2) 'Repeated install duplicated the managed profile.'
Assert (Test-DBeaverProfile $settings) 'Managed profile validation failed.'
Assert ($saved.connections.('levmet-iam-test').configuration.user -eq $config.email) 'Native authentication username was not populated.'
[xml]$savedDrivers = Get-Content -LiteralPath $driversFile -Raw
Assert ($null -ne $savedDrivers.SelectSingleNode('/drivers/driver[@id="existing-sqlite"]')) 'Existing non-PostgreSQL driver was changed.'
Assert ([IO.File]::ReadAllBytes($driversFile)[0] -eq 60) 'DBeaver XML must start with <, not a UTF-8 byte order mark.'
Assert ((Get-DBeaverDriverSource $settings) -eq 'offline') 'Existing installed settings lost offline compatibility.'
$driverHash = (Get-FileHash -LiteralPath $driversFile).Hash
$settings | Add-Member -NotePropertyName dbeaverDriverSource -NotePropertyValue 'artifactory'
Set-DBeaverProfile $settings (Join-Path $testRoot 'backups')
Set-DBeaverProfile $settings (Join-Path $testRoot 'backups')
$saved = Get-Content -LiteralPath $sourcesFile -Raw | ConvertFrom-Json
Assert ($saved.connections.('levmet-iam-test').driver -eq 'postgres-jdbc') 'Migration did not switch the managed connection to the standard PostgreSQL driver.'
Assert (@($saved.connections.PSObject.Properties).Count -eq 2) 'Migration duplicated a connection.'
Assert ($saved.connections.existing.name -eq 'Preserve me') 'Migration changed an unrelated connection.'
Assert ((Get-FileHash -LiteralPath $driversFile).Hash -eq $driverHash) 'Artifactory setup changed existing driver definitions.'
Assert (Test-DBeaverProfile $settings) 'Artifactory profile validation failed.'
$saved.connections.('levmet-iam-test').configuration.user = 'wrong.user@example.com'
Write-JsonFile $sourcesFile $saved
Assert-Throws { Test-DBeaverProfile $settings } 'Mismatched IAM user was accepted.'
Set-DBeaverProfile $settings (Join-Path $testRoot 'backups')
$settings.dbeaverWorkspace = Join-Path $testRoot 'fresh artifactory workspace'
$settings.driverDirectory = Join-Path $testRoot 'missing drivers'
Set-DBeaverProfile $settings (Join-Path $testRoot 'backups')
Assert (Test-DBeaverProfile $settings) 'Fresh Artifactory setup required offline libraries.'
Assert (-not (Test-Path -LiteralPath (Join-Path $settings.dbeaverWorkspace '.metadata\.config\drivers.xml'))) 'Fresh Artifactory setup wrote an offline driver definition.'
$report = [PSCustomObject]@{allChecksPassed=$false;configSha256=$config.configSha256;verifiedAtUtc=[DateTime]::UtcNow.ToString('o')}
Assert-Throws { Remove-CompletedConfig $config $report -DBeaverConfirmed } 'Failed verification allowed deletion.'
Assert (Test-Path -LiteralPath $configPath) 'Failed verification deleted the config.'
$report.allChecksPassed = $true
Assert-Throws { Remove-CompletedConfig $config $report } 'Config deleted without actual user confirmation.'
$report.verifiedAtUtc = [DateTime]::UtcNow.AddHours(-1).ToString('o')
Assert-Throws { Remove-CompletedConfig $config $report -DBeaverConfirmed } 'Stale verification allowed deletion.'
$report.verifiedAtUtc = [DateTime]::UtcNow.ToString('o')
[IO.File]::AppendAllText($configPath,"`n")
Assert-Throws { Remove-CompletedConfig $config $report -DBeaverConfirmed } 'Changed config allowed deletion.'
$config = Read-SetupConfig $configPath $repo
$report.configSha256 = $config.configSha256
Remove-CompletedConfig $config $report -DBeaverConfirmed
Assert (-not (Test-Path -LiteralPath $configPath)) 'Successful confirmed completion did not delete the exact config.'
Assert (Test-Path -LiteralPath $sourcesFile) 'Cleanup removed a profile.'
Write-Host "PASS: $script:checks safety and idempotence checks. Test artifacts: $testRoot"
