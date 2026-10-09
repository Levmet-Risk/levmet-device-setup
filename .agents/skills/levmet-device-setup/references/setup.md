# Config and failure handling

## Company Portal and Artifactory (default)

Follow the IT desk's October 2026 instructions:

1. Open **Company Portal** from Start and install DBeaver. If it is not listed,
   update or create the user's
   [Citizen Development registration ticket](https://help.marex.com/portal/203?createRequest=true&portalId=203&requestTypeId=927).
2. Once installed, open DBeaver in the workspace configured as `dbeaverWorkspace`.
   Go to **Window > Preferences > Connection > Drivers > Maven**.
3. Add **https://artifactory.marex.com/artifactory/maven-virtual/**. Only the URL is
   required; leave all other fields empty. No username or password is needed.
4. Move Artifactory to the **top** of the repository list and apply the change.
5. **Fully close and restart DBeaver. The restart is mandatory** before installing
   database drivers from the internal Maven mirror.

The scripts generate a connection using the standard PostgreSQL driver and do
not configure Maven preferences. The real DBeaver Test Connection checks driver
download/loading and database access; the Python query alone cannot verify JDBC.

## Config

`config.example.json` documents the supported fields through its keys and defaults.
The user's working file must be named `config.local.json`; it is Git-ignored.
All machine paths support `%USERPROFILE%`, `%APPDATA%`, and `%LOCALAPPDATA%`.
Relative paths are resolved against the repository root.

| Field | Meaning |
| --- | --- |
| email | User's Google identity and provisioned PostgreSQL IAM username |
| instanceConnectionName | `project:region:instance` supplied by the team |
| instanceIp | Instance IP for IT/firewall diagnostics; the proxy discovers its endpoint from Google |
| usePrivateIp | Use the private endpoint only when the PC has the necessary network route |
| database, localPort, connectionName | Database name, loopback listening port, saved DBeaver display name |
| installRoot | Persistent tool/runtime folder; default `%LOCALAPPDATA%\Levmet\DeviceSetup` |
| caCertificatePath | IT-supplied public PEM CA bundle; the included Marex bundle is the default |
| gcloudPath | Optional existing `gcloud.cmd` in an SDK with bundled Python; blank installs the included SDK |
| gcloudConfigDirectory | ADC/config directory, normally `%APPDATA%\gcloud` |
| codexPath | Optional working `codex.exe`/`codex.cmd`; blank searches PATH and VS Code, then installs the bundled CLI |
| dbeaverPath | Company Portal DBeaver executable; blank checks common locations. In default mode, a missing application stops setup with Company Portal instructions. Only explicit offline mode can install the bundled application. |
| dbeaverDriverSource | `artifactory` (default, including older input configs that omit this field) uses the standard PostgreSQL driver and the manually configured mirror; `offline` uses the 11 bundled JARs. Existing installed settings without this field retain offline behavior. |
| dbeaverWorkspace | Workspace receiving the new managed profile; default DBeaver Community `workspace6` |

No database password is required for automatic IAM. No Google password, token,
GitHub credential, service-account key, or secret belongs in the config. Unknown
fields are rejected rather than accidentally persisted. Google authenticates in
its browser flow; Codex uses its own sign-in when first launched.

The scripts combine Google's public CA bundle with the supplied corporate PEM and
set user `SSL_CERT_FILE` and `CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE`. This configures
clients that honor those variables; it does **not** override the Cloud SQL
connector's instance CA verification. A firewall/TLS inspection exception may
still be required for the instance's TCP 3307 connection. Local DBeaver uses
127.0.0.1, SSL disabled, and no SOCKS proxy; the Cloud SQL proxy encrypts the remote
connection.

For the offline fallback, generated DBeaver XML uses a flat `<driver provider="postgresql" ...>` entry.
The launcher also explicitly supplies that configuration file to DBeaver's JVM.
Write the XML as UTF-8 **without a byte order mark**: the bundled 26.2 build
silently ignored the BOM-prefixed XML during integration testing. Native authentication also needs
`configuration.user`; `auth-properties.userName` alone did not populate the login.

| Symptom | Next action |
| --- | --- |
| Scripts blocked by company Group Policy | Ask IT to approve/sign the supplied scripts. Process-only execution policy cannot override Group Policy. |
| ADC refresh/login error | Run `levmet-db-auth` and finish sign-in using the configured email. Never display `print-access-token`. |
| Local port occupied | Keep an existing matching IAM tunnel or choose another localPort and rerun Install. Do not kill an unknown process. |
| TCP 3307 timeout/reset | Ask IT to verify group access and egress to instanceIp:3307, plus required Google API HTTPS access. |
| Unknown certificate authority during DB handshake | Give IT the proxy log; verify inspection exemption. Do not add `--insecure`, disable TLS verification, or use plaintext remotely. |
| Database user/role denied | An administrator must provision the user's Cloud SQL IAM/database access. Setup does not grant permissions. |
| DBeaver asks to download a driver (Artifactory mode) | Expected on first use. Confirm Artifactory is first in Maven preferences in this workspace and DBeaver was fully restarted. Download the driver and run Test Connection. No Artifactory credentials are required. |
| Driver download fails (Artifactory mode) | Recheck the exact mirror URL, first position, and full restart. If it still fails, give IT the download error; do not automatically switch to the packaged workaround. |
| DBeaver asks to download a driver (offline mode) | Use the managed profile with `Levmet PostgreSQL (offline)`. Verify all 11 local libraries and restart DBeaver. |
| Commands missing in an old terminal | Restart the terminal/IDE or call the `.cmd` files by full path under installRoot\bin. |

Phases are restartable. Install backs up changed workspace files and previous user
environment values under `installRoot\backups`. It never backs up the input config
or ADC files. Logs may contain the instance identifier and email; inspect locally
and redact these before sharing outside the team. Failed installation staging
folders are retained for diagnosis; don't recursively delete an unverified path.

Complete verifies the current config hash, tools, offline libraries when selected, profile, and live
database query again. Only the user-confirmed DBeaver result allows deletion.
Deletion removes the input file, not disk snapshots, cloud sync history, or
backups made outside these scripts. Keep the repository outside synced folders.
