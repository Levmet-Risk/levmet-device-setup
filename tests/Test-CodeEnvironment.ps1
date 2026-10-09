$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repo 'scripts\CodeEnvironment.Core.psm1') -Force -DisableNameChecking
$fixture = Join-Path $repo ('.cache\code environment ' + [guid]::NewGuid().ToString('N'))
$sourceRoot = Join-Path $fixture 'source user\risk'
$targetRoot = Join-Path $fixture 'target user\risk'
foreach ($root in @($sourceRoot,$targetRoot)) {
    foreach ($child in @('Code','All trades','FTP files','Traders Dict')) { [IO.Directory]::CreateDirectory((Join-Path $root $child)) | Out-Null }
}
$script:checks = 0
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message }; $script:checks++ }
function Assert-Throws([scriptblock]$Action, [string]$Message) { $caught=$false; try { & $Action | Out-Null } catch { $caught=$true }; Assert $caught $Message }
function Write-TestJson([string]$Path,$Value) { [IO.File]::WriteAllText($Path,($Value | ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false)) }

$device = Join-Path $fixture 'device'
[IO.Directory]::CreateDirectory($device) | Out-Null
Write-TestJson (Join-Path $device 'settings.json') @{email='new.user@example.com';localPort=15433;database='risk data'}
$source = Read-CodeEnvironmentContext -CodeRoot (Join-Path $sourceRoot 'Code') -Email 'old.user@example.com' -DeviceSetupRoot $device
$target = Read-CodeEnvironmentContext -CodeRoot (Join-Path $targetRoot 'Code') -DeviceSetupRoot $device
$target.roots.userProfile = Join-Path $fixture 'target user'
$source.roots.userProfile = Join-Path $fixture 'source user'
$catalog = Get-CodeEnvironmentCatalog
Assert ($catalog.variables.Count -eq @($catalog.variables.name | Select-Object -Unique).Count) 'Duplicate manifest names.'
Assert ($target.derived.email -eq 'new.user@example.com') 'Target device identity was not reused.'
Assert ($target.derived.dbUrl -eq 'postgresql+psycopg2://new.user%40example.com@127.0.0.1:15433/risk%20data') 'Database URL was not encoded or did not reuse the target tunnel.'
$dummySecret = 'dummy-' + [guid]::NewGuid().ToString('N')
$values = @{LEVMET_EMAIL_PASSWORD=$dummySecret;LEVMET_PRICES_DIR=(Join-Path $sourceRoot 'FTP files\prices');MS_GRAPH_TENANT_ID='test-tenant';GREEKS_REPORT_DATE='19990101';PYTHONPATH='old-runtime';user_email='old.user@example.com';RISK_DB_URL='not-transferred'}
$payload = New-CodeEnvironmentTransfer $source -CurrentValues $values -SkipCredentialStore
Assert ($payload.entries.Count -eq 3) 'Export captured an identity, per-run flag or runtime variable.'
Assert ($payload.entries.name -notcontains 'GREEKS_REPORT_DATE') 'A stale report date was exported.'
Assert ($payload.missingSecrets -contains 'SENDGRID_API_KEY') 'Unavailable source credentials were not reported.'
$portable = @($payload.entries | Where-Object name -eq 'LEVMET_PRICES_DIR')[0]
Assert ($portable.root -eq 'riskRoot') 'Path did not use the most specific portable root.'
$plan = @(New-CodeEnvironmentPlan $target $payload -CurrentValues @{})
Assert (@($plan | Where-Object Name -eq 'LEVMET_PRICES_DIR')[0].Desired -eq (Join-Path $targetRoot 'FTP files\prices')) 'Path migration retained the old username/root.'
Assert (@($plan | Where-Object Name -eq 'user_email')[0].Desired -eq 'new.user@example.com') 'Source identity replaced the new machine identity.'
Assert (@($plan | Where-Object Name -eq 'LEVMET_EMAIL_PASSWORD')[0].Desired -ceq $dummySecret) 'Secret was altered during planning.'
Assert (@($plan | Where-Object Name -eq 'GREEKS_REPORT_DATE')[0].Action -eq 'None') 'Per-run report date would be persisted.'
Assert (@($plan | Where-Object Name -eq 'PATHS')[0].Action -eq 'None') 'Generic app-local Pydantic settings would be persisted globally.'
$redacted = Get-CodeEnvironmentReport $plan | ConvertTo-Json -Depth 10
Assert (-not $redacted.Contains($dummySecret)) 'Report leaked a secret.'
Assert (-not $redacted.Contains('Desired') -and -not $redacted.Contains('Current')) 'Report retained value-bearing properties.'
$completion = Get-CodeEnvironmentCompletion (Get-CodeEnvironmentReport $plan) $false
Assert (-not $completion.complete -and $completion.pendingCount -gt 0) 'A plan that has not been applied was reported complete.'
Assert ($completion.categories.derived.total -eq 6 -and $completion.categories.path.total -eq 20) 'Completion omitted database or path settings.'
$readyRows = $redacted | ConvertFrom-Json
foreach ($row in $readyRows) {
    if ($row.Kind -in @('derived','path','secret')) { $row.State='Configured'; $row.Action='Unchanged'; $row.PathStatus='' }
    elseif ($row.Kind -eq 'setting' -and $row.State -eq 'Configured') { $row.Action='Unchanged' }
}
$ready = Get-CodeEnvironmentCompletion $readyRows $true
Assert ($ready.complete -and $ready.categories.setting.usingDefaults -gt 0) 'Optional application defaults prevented complete verification.'
Assert ($ready.categories.secret.configured -eq 5 -and $ready.categories.derived.configured -eq 6) 'Completion counts omitted configured credentials or identity.'
Assert (-not (Get-CodeEnvironmentCompletion $readyRows $false).complete) 'A missing Graph credential was reported complete.'
$samplePath = @($readyRows | Where-Object Kind -eq 'path')[0]
$samplePath.PathStatus = 'Missing input path'
Assert (-not (Get-CodeEnvironmentCompletion $readyRows $true).complete) 'A missing input path was reported complete.'
$samplePath.PathStatus = ''; $samplePath.Action='Set'
Assert (-not (Get-CodeEnvironmentCompletion $readyRows $true).complete) 'An unapplied path setting was reported complete.'
$samplePath.Action='Unchanged'
$sampleSecret = @($readyRows | Where-Object Name -eq 'LEVMET_EMAIL_PASSWORD')[0]
$sampleSecret.State='Missing credential'; $sampleSecret.Action='None'
Assert (-not (Get-CodeEnvironmentCompletion $readyRows $true).complete) 'SendGrid success concealed a missing mail credential.'
Assert-Throws { Resolve-CodePortablePath ([PSCustomObject]@{root='riskRoot';relative='..\escape'}) $target.roots } 'Parent traversal was accepted.'
Assert-Throws { Resolve-CodePortablePath ([PSCustomObject]@{root='riskRoot';relative='C:\escape'}) $target.roots } 'Absolute relative path was accepted.'
Assert-Throws { Resolve-CodePortablePath ([PSCustomObject]@{root='riskRoot';relative='file:stream'}) $target.roots } 'Alternate data stream was accepted.'
Assert ((ConvertTo-CodePortablePath 'Z:\unmapped\prices' $source.roots).root -eq 'unmapped') 'An unmapped source path was carried blindly to the target.'

$bad = $payload | ConvertTo-Json -Depth 15 | ConvertFrom-Json
$bad.entries[0].name = 'PATH'
Assert-Throws { Test-CodeTransferPayload $bad } 'Transfer could replace an arbitrary environment variable.'
$bad = $payload | ConvertTo-Json -Depth 15 | ConvertFrom-Json
$bad.entries += $bad.entries[0]
Assert-Throws { Test-CodeTransferPayload $bad } 'Duplicate transfer entries were accepted.'
$badConfigPath = Join-Path $fixture 'bad.local.json'
Write-TestJson $badConfigPath @{valueOverrides=@{LEVMET_EMAIL_PASSWORD=$dummySecret}}
Assert-Throws { Read-CodeEnvironmentContext -ConfigPath $badConfigPath -CodeRoot (Join-Path $targetRoot 'Code') } 'Plaintext secrets were accepted in the config.'

Write-Host 'Testing password-protected transfer, wrong passwords and authenticated tamper detection...'
$password = ConvertTo-SecureString 'test-only passphrase 2026' -AsPlainText -Force
$wrong = ConvertTo-SecureString 'different test passphrase' -AsPlainText -Force
$bundle = Join-Path $fixture 'fixture.levmet-env'
Write-CodeTransferFile $payload $bundle $password
Assert (-not [IO.File]::ReadAllText($bundle).Contains($dummySecret)) 'Bundle stored the secret in plaintext.'
$decoded = Read-CodeTransferFile $bundle $password
Assert (@($decoded.entries | Where-Object name -eq 'LEVMET_EMAIL_PASSWORD')[0].value -ceq $dummySecret) 'Protected transfer did not round-trip.'
Assert-Throws { Write-CodeTransferFile $payload $bundle $password } 'Export overwrote an existing transfer file.'
Assert-Throws { Read-CodeTransferFile $bundle $wrong } 'Wrong passphrase was accepted.'
$raw = [Convert]::FromBase64String([IO.File]::ReadAllText($bundle))
$raw[60] = $raw[60] -bxor 1
$tampered = Join-Path $fixture 'tampered.levmet-env'
[IO.File]::WriteAllText($tampered,[Convert]::ToBase64String($raw))
Assert-Throws { Read-CodeTransferFile $tampered $password } 'Modified ciphertext passed authentication.'
$raw[0] = 0
[IO.File]::WriteAllText($tampered,[Convert]::ToBase64String($raw))
Assert-Throws { Read-CodeTransferFile $tampered $password } 'Modified version header was accepted.'

Write-Host 'Testing conflicts, idempotence and DPAPI rollback with process-only variables...'
$name = 'LEVMET_EMAIL_TEST_TO'
$originalProcess = [Environment]::GetEnvironmentVariable($name,'Process')
$originalUser = [Environment]::GetEnvironmentVariable($name,'User')
try {
    [Environment]::SetEnvironmentVariable($name,'existing@example.com','Process')
    $conflict = @([PSCustomObject]@{Name=$name;Action='Conflict';Desired='new@example.com'})
    Assert-Throws { Set-CodeEnvironmentPlan $conflict -BackupDirectory (Join-Path $fixture 'backups') -ProcessOnly } 'Conflict was overwritten without selection.'
    Assert ([Environment]::GetEnvironmentVariable($name,'Process') -eq 'existing@example.com') 'Failed plan partially changed the environment.'
    $result = Set-CodeEnvironmentPlan $conflict -BackupDirectory (Join-Path $fixture 'backups') -ProcessOnly -ReplaceExisting
    Assert ($result.Changed -eq 1 -and (Test-Path -LiteralPath $result.BackupPath)) 'Apply did not create a protected backup.'
    Assert ([Environment]::GetEnvironmentVariable($name,'Process') -eq 'new@example.com') 'Apply failed to set the value.'
    Assert ([Environment]::GetEnvironmentVariable($name,'User') -ceq $originalUser) 'Test changed the persistent user environment.'
    $same = @([PSCustomObject]@{Name=$name;Action='Unchanged';Desired='new@example.com'})
    Assert ((Set-CodeEnvironmentPlan $same -BackupDirectory (Join-Path $fixture 'backups') -ProcessOnly).Changed -eq 0) 'Unchanged apply was not idempotent.'
    $bytes = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($result.BackupPath),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    $snapshot = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
    [Array]::Clear($bytes,0,$bytes.Length)
    Restore-CodeEnvironmentSnapshot $snapshot -ProcessOnly
    Assert ([Environment]::GetEnvironmentVariable($name,'Process') -eq 'existing@example.com') 'Snapshot did not restore the previous setting.'
} finally { [Environment]::SetEnvironmentVariable($name,$originalProcess,'Process') }

Write-Host 'Testing the Windows credential bridge with disposable test targets only...'
$service = 'levmet-code-environment-test-' + [guid]::NewGuid().ToString('N')
$firstBlob = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('first fake secret'))
$secondBlob = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('second fake secret'))
try {
    [Levmet.Setup.CredentialStore]::Write($service,'first-test-user',$firstBlob)
    $graph = [PSCustomObject]@{service=$service;user='second-test-user';blobBase64=$secondBlob}
    $result = Set-CodeEnvironmentPlan @() -Graph $graph -BackupDirectory (Join-Path $fixture 'credential backups')
    Assert ($result.CredentialChanged) 'Graph credential was not imported.'
    Assert ([Levmet.Setup.CredentialStore]::Read($service).BlobBase64 -ceq $firstBlob) 'Import replaced another user under the same credential service.'
    $resolved = Get-CodeGraphCredential ([PSCustomObject]@{service=$service;user='second-test-user'})
    Assert ($resolved.BlobBase64 -ceq $secondBlob) 'Python-keyring compound target could not be resolved.'
    Restore-CodeEnvironmentBackup $result.BackupPath
    Assert ($null -eq [Levmet.Setup.CredentialStore]::Read('second-test-user@' + $service)) 'Credential restore failed to remove the newly imported entry.'
    Assert ([Levmet.Setup.CredentialStore]::Read($service).BlobBase64 -ceq $firstBlob) 'Credential restore changed an unrelated entry.'
} finally {
    [Levmet.Setup.CredentialStore]::Delete($service)
    [Levmet.Setup.CredentialStore]::Delete('second-test-user@' + $service)
    $password.Dispose(); $wrong.Dispose()
}
Write-Host "PASS: $script:checks code environment checks. No production services were called. Fixture: $fixture"
