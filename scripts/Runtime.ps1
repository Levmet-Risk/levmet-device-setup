[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('Auth','Tunnel','Test','DBeaver')][string]$Action)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Setup.Core.psm1') -Force -DisableNameChecking
try {
    $settings = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Set-RuntimeEnvironment $settings
    switch ($Action) {
        'Auth' {
            Write-Host ('Complete Google sign-in using ' + $settings.email)
            & $settings.gcloudPath auth application-default login $settings.email
            if ($LASTEXITCODE -ne 0) { throw 'ADC sign-in failed. Complete the browser sign-in and retry levmet-db-auth.' }
        }
        'Tunnel' {
            if (Test-LocalPort $settings.localPort) { throw 'The local port is already in use. Keep the existing tunnel, or select a different port in a new setup config.' }
            Write-Host ('IAM tunnel on 127.0.0.1:' + $settings.localPort + '. Keep this terminal open; Ctrl+C stops it.')
            & $settings.proxyPath @(Get-ProxyArguments $settings)
            if ($LASTEXITCODE -ne 0) { throw 'The proxy stopped with an error. Run levmet-db-auth if sign-in has expired.' }
        }
        'Test' {
            Test-DBeaverProfile $settings | Out-Null
            Invoke-DatabaseVerification $settings
        }
        'DBeaver' {
            # This launches a user-facing interactive application intentionally.
            $arguments = '-data "' + $settings.dbeaverWorkspace + '" -con "id=' + $settings.connectionId + '|create=false|connect=true|openConsole=true"'
            if ((Get-DBeaverDriverSource $settings) -eq 'offline') {
                $driverConfig = Join-Path $settings.dbeaverWorkspace '.metadata\.config\drivers.xml'
                $arguments = '--launcher.appendVmargs ' + $arguments + ' -vmargs "-Ddbeaver.drivers.configuration-file=' + $driverConfig + '"'
            }
            Start-Process -FilePath $settings.dbeaverPath -ArgumentList $arguments | Out-Null
        }
    }
} catch {
    Write-Error $_.Exception.Message -ErrorAction Continue
    exit 1
}
