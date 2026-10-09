# Configure the Levmet reporting code after device setup

Use **`$levmet-code-environment`** from this repository, or the commands below.
This is an independent follow-up: it does not repeat DBeaver installation,
Google authentication, or the original device setup. It reads the installed
`settings.json`, so the original `config.local.json` is not needed.

An actual encrypted export from 9 October 2026 is now included in
[`transfers/levmet-code-env-20261009.levmet-env`](transfers/levmet-code-env-20261009.levmet-env)
at the user's request. For this prepared bundle, follow the
[new-machine import instructions](transfers/README.md). Its generated password
is saved separately on the source PC, outside Git. The sections below also
describe how to create another export using your own passphrase.

## On the source PC: capture configured credentials and overrides

Open PowerShell in the updated `levmet-device-setup` repository:

```powershell
.\CodeEnvironment.cmd -Phase Audit
.\CodeEnvironment.cmd -Phase Export -BundlePath "$env:USERPROFILE\Downloads\levmet-code-env.levmet-env"
```

Export asks for a passphrase of at least 12 characters and confirmation. Input
is masked. Do not put the passphrase in chat, command arguments, a script, or Git.
Copy the `.levmet-env` file to the new machine and keep its passphrase separately.
Export refuses to overwrite an existing bundle; choose a new filename for a new
export. It does not change the source PC's environment.

The export includes configured, supported codebase environment values and the
Graph client secret selected by `MS_GRAPH_SECRET_SERVICE` / `MS_GRAPH_SECRET_USER`
in Windows Credential Manager (defaults: `ms_graph_secret` / `RiskReports`). It
reads only that credential, including Python keyring's compound-target variant.
It lists credential variables that are absent instead of inventing values.
It never copies Google ADC, Codex login data, browser sessions, unrelated Windows
credentials, or secret-file contents such as `logICE.json`.

## On the new PC: apply the follow-up

Update this repository, ensure the reporting data/code folders are synced, and run:

```powershell
.\CodeEnvironment.cmd -Phase Audit
.\CodeEnvironment.cmd -Phase Apply -BundlePath "$env:USERPROFILE\Downloads\levmet-code-env.levmet-env"
.\CodeEnvironment.cmd -Phase Verify
```

Enter the transfer passphrase at the masked prompt. If there is no transfer yet,
`-Phase Apply` on its own configures the available paths and database identity.
Run Apply again with the bundle when it arrives. Repeated application is safe.

The default code location is
`%USERPROFILE%\Marex\Levmet Risk Prod - Documents\levmet-risk\Code`.
Its parent must contain `All trades` and `FTP files`. For another layout, pass
`-CodeRoot "C:\your\path\Code"`, or copy `code-environment.example.json` to
**`code-environment.local.json`** and edit the non-secret settings:

| Field | Purpose |
| --- | --- |
| `codeRoot` | Reporting code folder on this machine |
| `riskRoot` | Data root containing `All trades`, `FTP files`, and `Traders Dict`; blank uses the parent of `codeRoot` |
| `oneDriveRoot` | Optional old-style Levmet OneDrive root for remaining Monaco/ICE inputs; blank only auto-detects an existing `%USERPROFILE%\OneDrive - Levmet` |
| `email` | Google/IAM email; blank reads the completed device setup's settings, then existing `user_email` |
| `deviceSetupRoot` | Location of completed device setup; blank uses `LEVMET_SETUP_HOME` or `%LOCALAPPDATA%\Levmet\DeviceSetup` |
| `pathOverrides` | Object mapping inventoried path-variable names to their actual target paths |
| `valueOverrides` | Object mapping inventoried non-secret setting names to strings; credentials, runtime flags, and arbitrary variables are rejected |

Example non-secret overrides:

```json
{
  "pathOverrides": {
    "LEVMET_ICE_POWER_DIR": "D:\\MarketData\\ICE\\inputs",
    "LEVMET_ICE_CREDENTIALS_JSON": "C:\\Users\\YOUR_USER\\PrivateConfig\\logICE.json"
  },
  "valueOverrides": {
    "LEVMET_EMAIL_FROM": "YOUR_APPROVED_SENDER",
    "LEVMET_EMAIL_TEST_TO": "YOUR_TEST_MAILBOX"
  }
}
```

Use the actual approved mail addresses; setup does not infer SendGrid sender
verification from the IAM email. A path to a credential file is allowed in
`pathOverrides`; its contents are not copied or logged.

Apply regenerates `user_email`, `RISK_DB_USER`, `RISK_DB_URL`, and
`LEVMET_DB_HOST/PORT/NAME` from the destination settings. The SQLAlchemy URL
percent-encodes the IAM username. Data, template, output, and cache paths follow
the destination roots. Exported path overrides under known roots are rebased;
unmapped paths require an explicit destination override.

Conflicting existing values stop Apply before any changes. After reviewing the
names in Audit, use `-ReplaceExisting` if the proposed values should replace them.
Changes have a backup encrypted with Windows DPAPI for the current Windows user:

```powershell
.\CodeEnvironment.cmd -Phase Restore -BackupPath "C:\path\reported\environment-ID.dpapi"
```

The password-protected transfer works across machines. The DPAPI rollback file is
for the same Windows account/profile on the machine where it was created.
Restart terminal/IDE windows and relaunch jobs after Apply or Restore. No scheduled
tasks are created or enabled, and no reports, emails, downloads, or database writes
are performed by this follow-up.

## Missing credentials and verification

To set a credential that the source PC did not have, use a masked local prompt:

```powershell
.\CodeEnvironment.cmd -Phase SetSecret -Name LEVMET_BROKER_SFTP_PASSWORD
.\CodeEnvironment.cmd -Phase SetGraphSecret
```

`SetSecret` accepts only `SENDGRID_API_KEY`, `LEVMET_BROKER_SFTP_PASSWORD`,
`LEVMET_EMAIL_PASSWORD`, `LEVMET_LEVGAS_EMAIL_PASSWORD`, and
`LEVMET_POSMON_EMAIL_PASSWORD`. Use `-ReplaceExisting` to replace an existing
credential with a protected backup. The reporting programs read these five
variables as ordinary Windows environment strings; the transfer and backups
protect copies in transit/on disk, not the environment once configured.

Audit and Verify write **names/statuses only**, including absent credentials and
missing input paths, to `%LOCALAPPDATA%\Levmet\CodeEnvironment`. Audit rescans
the supplied code directory with the device setup's bundled Python and records
unrecognized variables, dynamic accesses, parse errors, and hardcoded path
locations. An explicit `-PythonPath` can select another working Python 3.10+ for
the scanner. The scanner never imports the inspected code.

Verify returns `0` when the inventoried managed settings, input paths, and
credentials are present, `2` for remaining gaps, and `1` for an operation error.
Apply can successfully write the available settings while Verify still reports
missing optional/legacy capabilities. Credential presence and path existence do
not prove provider permissions, data freshness, file hydration, installed Python
dependencies, or successful report execution.

## Inventory and scope

The 9 October 2026 audit covered **594 source/configuration files** and found
**86 distinct names**:

| Handling | Count | Behavior |
| --- | ---: | --- |
| Database/identity | 6 | Derived from destination device setup |
| Paths | 20 | Derived/rebased; unknown locations are reported |
| Credential variables | 5 | Exported only when present; masked entry also supported |
| Other application settings | 17 | Existing/configured overrides are preserved/transferred; unset values retain code defaults |
| Per-run options | 9 | Remain under the caller's control, including dates and send/write switches |
| OS/launcher variables | 21 | Left to Windows and the existing launchers |
| Application-local options | 7 | Not persisted globally: `DB_URL`, `ENVIRONMENT`, `LOGGING`, `PATHS`, `UI`, `PORT`, `DASH_BASE_PATH` |
| Test-only option | 1 | Not installed |

See the [complete inventory](.agents/skills/levmet-code-environment/references/inventory.md)
for every name and source location. The machine-readable allowlist is
[`assets/code-environment.json`](assets/code-environment.json).

The dashboard's generic `PATHS` JSON setting belongs in that application's local
configuration/launch environment. Old hardcoded `C:\Users\...`, OneDrive, and
network paths in other scripts also need separate source/configuration changes.
This follow-up configures the existing environment interfaces; it does not port
all legacy scripts or claim the whole reporting codebase is ready to run.

## Transfer implementation and maintainer checks

The versioned envelope uses PBKDF2-HMAC-SHA256 (600,000 iterations, random 32-byte
salt), AES-256-CBC with a random IV, and HMAC-SHA256 over the header, salt, IV, and
ciphertext using a separate derived key. Authentication is checked before
decryption. The implementation uses Windows/.NET components, so no additional
Python packages or network installation are needed for Apply/Export.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-CodeEnvironment.ps1
& "PATH_TO_WORKING_PYTHON" -B .\tests\test_code_env_inventory.py
```

Tests use dummy values, process-scoped environment changes, isolated folders, and
disposable Credential Manager targets that they remove. They cover wrong
passphrases, tampering, target-path rebasing, conflict handling, rollback, and
Python-keyring compatibility. They do not contact production services.

Implementation references: [Microsoft PBKDF2 API](https://learn.microsoft.com/en-us/dotnet/api/system.security.cryptography.rfc2898derivebytes.-ctor?view=netframework-4.8.1),
[Microsoft credential API](https://learn.microsoft.com/en-us/windows/win32/api/wincred/nf-wincred-credreadw),
[Python keyring's Windows backend](https://github.com/jaraco/keyring/blob/main/keyring/backends/Windows.py).
