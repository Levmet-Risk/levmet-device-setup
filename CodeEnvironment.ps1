[CmdletBinding()]
param(
    [ValidateSet('Audit','Export','Apply','Complete','Verify','Restore','SetSecret','SetGraphSecret')][string]$Phase = 'Audit',
    [string]$ConfigPath,
    [string]$CodeRoot,
    [string]$Email,
    [string]$DeviceSetupRoot,
    [string]$BundlePath,
    [string]$BackupPath,
    [string]$Name,
    [string]$PythonPath,
    [string]$ReportDirectory = (Join-Path $env:LOCALAPPDATA 'Levmet\CodeEnvironment'),
    [switch]$ReplaceExisting,
    # SecureString is for interactive callers; never supply a plaintext CLI password.
    [Security.SecureString]$Password
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'scripts\CodeEnvironment.Core.psm1') -Force -DisableNameChecking

function Read-TransferPassphrase([switch]$Confirm) {
    $first = Read-Host 'Transfer passphrase (at least 12 characters; keep it separately from the file)' -AsSecureString
    if ($first.Length -lt 12 -or $first.Length -gt 1024) { throw [Levmet.Setup.EnvironmentSetupException]::new('Passphrase must contain 12 to 1024 characters.') }
    if ($Confirm) {
        $second = Read-Host 'Repeat transfer passphrase' -AsSecureString
        $left = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($first)
        $right = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($second)
        try {
            $difference = $first.Length -bxor $second.Length
            if ($first.Length -eq $second.Length) {
                for ($i=0; $i -lt $first.Length; $i++) {
                    $difference = $difference -bor ([Runtime.InteropServices.Marshal]::ReadInt16($left,$i*2) -bxor [Runtime.InteropServices.Marshal]::ReadInt16($right,$i*2))
                }
            }
            if ($difference -ne 0) { throw [Levmet.Setup.EnvironmentSetupException]::new('Passphrases do not match.') }
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($left)
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($right)
            $second.Dispose()
        }
    }
    return $first
}

try {
    $backupDirectory = Join-Path $ReportDirectory 'backups'
    if ($Phase -eq 'Restore') {
        if (-not $BackupPath) { throw [Levmet.Setup.EnvironmentSetupException]::new('Restore requires -BackupPath to the .dpapi file produced on this machine.') }
        Restore-CodeEnvironmentBackup $BackupPath
        Write-Host 'Previous user environment and Graph credential restored. Restart terminal/IDE windows.'
        exit 0
    }
    if ($Phase -eq 'SetSecret') {
        if (-not $Name) { throw [Levmet.Setup.EnvironmentSetupException]::new('SetSecret requires -Name, such as SENDGRID_API_KEY.') }
        $secret = Read-Host ('Enter ' + $Name + ' (input is hidden)') -AsSecureString
        try { $result = Set-CodeEnvironmentSecret $Name $secret $backupDirectory -ReplaceExisting:$ReplaceExisting }
        finally { $secret.Dispose() }
        Write-Host ('Secret configured. Protected backup: ' + $result.BackupPath)
        exit 0
    }
    if ($Phase -eq 'SetGraphSecret') {
        $selectors = Get-CodeGraphSelectors @{MS_GRAPH_SECRET_SERVICE=(Get-CodeEnvironmentValue 'MS_GRAPH_SECRET_SERVICE');MS_GRAPH_SECRET_USER=(Get-CodeEnvironmentValue 'MS_GRAPH_SECRET_USER')}
        $secret = Read-Host 'Enter the Graph client secret (input is hidden)' -AsSecureString
        $bytes = $null
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
        try {
            if ($secret.Length -eq 0) { throw [Levmet.Setup.EnvironmentSetupException]::new('Secret cannot be empty.') }
            $bytes = New-Object byte[] ($secret.Length * 2)
            [Runtime.InteropServices.Marshal]::Copy($pointer,$bytes,0,$bytes.Length)
            $graph = [PSCustomObject]@{service=$selectors.service;user=$selectors.user;blobBase64=[Convert]::ToBase64String($bytes)}
            $result = Set-CodeEnvironmentPlan @() -Graph $graph -BackupDirectory $backupDirectory -ReplaceExisting:$ReplaceExisting
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
            if ($bytes) { [Array]::Clear($bytes,0,$bytes.Length) }
            $secret.Dispose()
        }
        Write-Host ('Graph credential configured in Windows Credential Manager. Protected backup: ' + $result.BackupPath)
        exit 0
    }
    if (-not $ConfigPath -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'code-environment.local.json'))) { $ConfigPath = Join-Path $PSScriptRoot 'code-environment.local.json' }
    $context = Read-CodeEnvironmentContext -ConfigPath $ConfigPath -CodeRoot $CodeRoot -Email $Email -DeviceSetupRoot $DeviceSetupRoot
    if ($Phase -eq 'Export') {
        if (-not $BundlePath) { throw [Levmet.Setup.EnvironmentSetupException]::new('Export requires -BundlePath, for example C:\Users\YOUR_USER\Downloads\levmet-code-env.levmet-env.') }
        if (-not $Password) { $Password = Read-TransferPassphrase -Confirm }
        $payload = New-CodeEnvironmentTransfer $context
        Write-CodeTransferFile $payload $BundlePath $Password
        Write-Host ('Encrypted transfer written to: ' + [IO.Path]::GetFullPath($BundlePath))
        Write-Host ('Captured environment entries: ' + $payload.entries.Count + '; Graph credential present: ' + [bool]$payload.graph)
        if ($payload.missingSecrets.Count) { Write-Host ('Not present on this PC; not exported: ' + ($payload.missingSecrets -join ', ')) }
        Write-Host 'Only configured codebase variables and the selected Graph credential were captured. No Google/Codex login caches were copied.'
        exit 0
    }
    if ($Phase -eq 'Complete' -and -not $BundlePath) {
        $BundlePath = Join-Path $PSScriptRoot 'transfers\levmet-code-env-20261009.levmet-env'
        if (-not (Test-Path -LiteralPath $BundlePath -PathType Leaf)) { throw [Levmet.Setup.EnvironmentSetupException]::new('The prepared transfer is missing. Update this repository or pass -BundlePath to your encrypted export.') }
    }
    $transfer = $null
    if ($BundlePath) {
        if (-not $Password) { $Password = Read-TransferPassphrase }
        $transfer = Read-CodeTransferFile $BundlePath $Password
    }
    $plan = @(New-CodeEnvironmentPlan $context $transfer)
    if ($Phase -in @('Apply','Complete')) {
        $graph = if ($transfer) { $transfer.graph } else { $null }
        $result = Set-CodeEnvironmentPlan $plan -Graph $graph -BackupDirectory $backupDirectory -ReplaceExisting:$ReplaceExisting
        Write-Host ('Environment entries changed: ' + $result.Changed + '; Graph credential changed: ' + $result.CredentialChanged)
        if ($result.BackupPath) { Write-Host ('Protected backup: ' + $result.BackupPath) }
        $plan = @(New-CodeEnvironmentPlan $context $transfer)
        Write-Host 'Restart terminal/IDE windows and relaunch scheduled jobs to inherit the user environment.'
    }
    $scan = $null
    if ($Phase -eq 'Audit') {
        if (-not $PythonPath) { $PythonPath = $context.pythonPath }
        if (-not $PythonPath) {
            $gcloud = Get-Command gcloud.cmd -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($gcloud) { $PythonPath = Join-Path (Split-Path -Parent (Split-Path -Parent $gcloud.Source)) 'platform\bundledpython\python.exe' }
        }
        if (-not $PythonPath -or -not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) { throw [Levmet.Setup.EnvironmentSetupException]::new('Audit needs Python. Complete device setup, or supply -PythonPath to a working Python 3.10+ executable.') }
        [IO.Directory]::CreateDirectory($ReportDirectory) | Out-Null
        $inventoryPath = Join-Path $ReportDirectory 'source-inventory.json'
        & $PythonPath -E -X utf8 -B (Join-Path $PSScriptRoot 'scripts\code_env_inventory.py') --code-root $context.roots.codeRoot --output $inventoryPath
        if ($LASTEXITCODE -ne 0) { throw [Levmet.Setup.EnvironmentSetupException]::new('Static source inventory failed. No codebase scripts were executed.') }
        $scan = Get-Content -LiteralPath $inventoryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    $selectors = Get-CodeGraphSelectors @{MS_GRAPH_SECRET_SERVICE=(Get-CodeEnvironmentValue 'MS_GRAPH_SECRET_SERVICE');MS_GRAPH_SECRET_USER=(Get-CodeEnvironmentValue 'MS_GRAPH_SECRET_USER')}
    $hasGraph = $null -ne (Get-CodeGraphCredential $selectors)
    $reportRows = @(Get-CodeEnvironmentReport $plan)
    $gaps = @($reportRows | Where-Object { $_.State -like 'Needs *' -or $_.State -eq 'Missing credential' -or $_.PathStatus -eq 'Missing input path' })
    $completion = Get-CodeEnvironmentCompletion $reportRows $hasGraph
    $unknown = @(if ($scan) { $scan.variables | Where-Object { $_.name -notin $reportRows.Name } | Select-Object -ExpandProperty name })
    $report = [PSCustomObject]@{schemaVersion=1;phase=$Phase;checkedAtUtc=[DateTime]::UtcNow.ToString('o');variables=$reportRows;graphCredentialPresent=$hasGraph;gapCount=$gaps.Count;completion=$completion;unknownVariables=@($unknown);scan=$scan;servicesTested=$false}
    [IO.Directory]::CreateDirectory($ReportDirectory) | Out-Null
    $reportPath = Join-Path $ReportDirectory 'environment-report.json'
    [IO.File]::WriteAllText($reportPath,($report | ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
    $reportRows | Where-Object Kind -in @('derived','path','secret','setting') | Format-Table Name,Action,State,PathStatus -AutoSize | Out-Host
    Write-Host ('Graph credential present: ' + $hasGraph + '; missing settings/credentials/inputs: ' + $gaps.Count)
    if ($Phase -in @('Apply','Complete','Verify')) {
        $categories = $completion.categories
        Write-Host ('Database/identity: ' + $categories.derived.configured + '/' + $categories.derived.total + ' configured')
        Write-Host ('Path variables: ' + $categories.path.configured + '/' + $categories.path.total + ' configured; missing input paths: ' + $completion.missingInputPaths)
        Write-Host ('API/mail credential variables: ' + $categories.secret.configured + '/' + $categories.secret.total + ' configured')
        Write-Host ('Application settings: ' + $categories.setting.configured + ' explicit; ' + $categories.setting.usingDefaults + ' using code defaults')
        if ($completion.complete) { Write-Host 'Managed environment verification passed. Service access and report execution have not been tested.' }
        else { Write-Host ('Managed environment INCOMPLETE: ' + $completion.missingCount + ' missing settings/credentials/inputs; ' + $completion.pendingCount + ' changes still needed; Graph credential present: ' + $hasGraph) }
    }
    if ($context.derived.dbPort -ne '5433') { Write-Host 'Some legacy scripts hardcode port 5433. Their source/launchers need separate review for this tunnel port.' }
    if ($unknown.Count) { Write-Host ('New variable names need review before migration: ' + ($unknown -join ', ')) }
    if ($scan -and $scan.unresolved.Count) { Write-Host ('Static scan has ' + $scan.unresolved.Count + ' unresolved references/parse issues; see the report.') }
    Write-Host ('Redacted report: ' + $reportPath)
    Write-Host 'Runtime/per-run/app-local options are listed in the report and left to their launchers. No reports, emails, broker downloads or database writes were run.'
    if ($Phase -in @('Verify','Complete') -and -not $completion.complete) { exit 2 }
    exit 0
} catch {
    # Native/crypto/JSON exceptions can include inputs. Emit only controlled messages.
    $message = 'Code environment operation failed. Check the paths, config, and transfer passphrase; no credential values are logged.'
    if ($_.Exception -is [Levmet.Setup.EnvironmentSetupException]) { $message = $_.Exception.Message }
    Write-Host ('ERROR: ' + $message)
    Write-Verbose ('Location: ' + $_.ScriptStackTrace)
    exit 1
}
