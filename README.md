# Levmet Windows device setup

Private team onboarding for Windows x64 PCs. The default workflow uses **DBeaver
from Company Portal** and **Marex Artifactory for database drivers**, following the
IT desk's October 2026 fix. The repository supplies the Google Cloud CLI with
Python, Cloud SQL Auth Proxy, Codex CLI fallback, Marex public CA bundle, and
passwordless IAM connection setup. Google sign-in, driver downloads, and database
access require network access and the user's existing permissions.

The earlier portable DBeaver distribution and 11 pinned PostgreSQL JDBC libraries
remain available through the explicit `dbeaverDriverSource: "offline"` fallback.
New configurations default to `"artifactory"`.

## Install DBeaver and configure the internal Maven mirror

1. Open **Company Portal** from the Windows Start menu and install **DBeaver**.
   If DBeaver is not visible, update or create your
   [Citizen Development registration ticket](https://help.marex.com/portal/203?createRequest=true&portalId=203&requestTypeId=927).
2. After installation finishes, open DBeaver and go to **Window > Preferences >
   Connection > Drivers > Maven**.
3. Add this repository URL: **https://artifactory.marex.com/artifactory/maven-virtual/**.
   Only the URL is needed; leave all other fields, including username and
   password, empty.
4. **Move the Artifactory entry to the top** of the repository list and apply the
   preferences.
5. **Fully close and restart DBeaver. This restart is mandatory.** You can then
   install database drivers from Marex's internal Maven mirror.

Apply these preferences in the workspace you will use for the managed connection
(`dbeaverWorkspace` in the config). If you choose a different workspace later,
configure the mirror there and restart DBeaver again.

## Start on a new PC

1. Complete the Company Portal and Maven mirror steps above. Clone this private
   repository, or use GitHub **Code > Download ZIP** and extract
   it to a short, permanent, non-synced path such as
   `C:\Users\YOUR_USERNAME\levmet-device-setup`. Download the whole repository;
   individual skill files or GitHub's source preview are insufficient.
2. Copy `config.example.json` to **`config.local.json`**. Set `email` to your own
   work Google/IAM email. Review the shared database defaults and paths. Change
   them if your administrator supplied different values. Leave
   `dbeaverDriverSource` as `"artifactory"`. If DBeaver is installed outside the
   usual locations, set `dbeaverPath` to its executable. The config reference is
   [here](.agents/skills/levmet-device-setup/references/setup.md).
3. Open a terminal in the extracted folder and run **`Bootstrap.cmd`**. It checks
   Codex, repairs PATH, installs the bundled CLI if needed, then opens Codex in
   this repository with the setup skill selected. On its first use, sign in to
   Codex with your own account. If you already have Codex open here, invoke
   **`$levmet-device-setup`** directly instead.
4. Let the skill run setup. Close DBeaver when asked so its workspace can be
   updated. Complete Google browser sign-in using the email in your config.
5. Follow the skill's instructions to open the tunnel and the managed DBeaver
   profile. Accept the driver download from the configured internal mirror when
   prompted. Click **Test Connection** and tell Codex the actual result. After
   successful verification and your confirmation, the skill deletes the input
   `config.local.json`.

No Google or database password goes in this config. This setup uses automatic IAM
authentication, so the local PostgreSQL password is empty. Do not put tokens or
service-account keys into it. User config files are ignored by Git and are never
included in the team's repository.

## Commands after setup

Restart existing terminals and VS Code to inherit the updated user PATH.

| Command | Purpose |
| --- | --- |
| `levmet-db-auth` | Refresh Google Application Default Credentials (ADC) through browser sign-in |
| `levmet-db-tunnel` | Run the automatic IAM proxy on the configured loopback port; keep the terminal open |
| `levmet-db-test` | Verify the managed DBeaver profile and execute a read-only query through the proxy |
| `levmet-dbeaver` | Open the managed profile in the configured DBeaver workspace |
| `gcloud.cmd` | Run Google Cloud CLI commands from CMD or PowerShell |
| `cloud-sql-proxy.exe` | Run the proxy directly when needed |
| `codex` | Run Codex from a terminal |

`re_auth.bat` and `run_tunnel.bat` compatibility launchers are also included.
Existing commands earlier on PATH keep their normal precedence; the unique
`levmet-*` commands select this installation unambiguously. The proxy listens only
on `127.0.0.1`. DBeaver's local SSL setting is disabled; remote encryption is
provided and verified by the Cloud SQL proxy.

## What setup changes

- Installs tools and supporting files beneath the configurable `installRoot`,
  normally `%LOCALAPPDATA%\Levmet\DeviceSetup`. A working Codex installation is
  reused. Default setup requires DBeaver to be installed from Company Portal;
  it stops with instructions if no executable is found. It locates an executable
  but cannot establish whether an existing installation came from Company Portal.
- Adds the necessary directories to **user** PATH without overwriting existing
  entries. Sets `LEVMET_SETUP_HOME`, `SSL_CERT_FILE`, and
  `CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE`. The CA file combines the SDK's public roots
  with the configured corporate certificates.
- Adds a managed connection using DBeaver's standard **PostgreSQL** driver.
  Configure the Maven mirror in DBeaver using the steps above; the scripts leave
  Maven preferences and existing driver definitions intact. In explicit offline
  mode, setup instead adds **Levmet PostgreSQL (offline)** with all 11 local JARs.
  Existing profiles are preserved. Changed workspace files and previous
  environment values are backed up under `installRoot\backups`.
- Stores only the operational values needed by the launchers in
  `installRoot\settings.json`. The email, database/instance identifiers and paths
  must remain available after onboarding. Google maintains ADC in the configured
  gcloud directory; Codex maintains its own authentication. The input config is
  not copied into the installed settings or backups wholesale.

The bundled CA does not disable certificate verification or override the Cloud
SQL connector's own instance CA. IT may still need to exempt the database tunnel
from TLS inspection and allow the instance's TCP **3307** connection plus Google
API HTTPS access. Setup does not change firewall policy, IAM permissions, Cloud
SQL settings, Windows Group Policy, or the system certificate store.

## Manual phases and resuming

Complete the Company Portal/Maven steps above, then close DBeaver so Install can
update its workspace. From the repository folder in PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 -Phase Install
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 -Phase Authenticate
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 -Phase Verify
```

Then run `levmet-db-tunnel` in a separate terminal, run `levmet-dbeaver`, and check
**Test Connection** for the managed profile, downloading drivers if prompted.
Verify's query checks IAM/database access independently of JDBC; it does not prove
that Artifactory downloads or DBeaver driver loading work. Only after DBeaver's
actual Test Connection succeeds:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 -Phase Complete -DBeaverConfirmed
```

`Complete` repeats the real database query before deleting the exact unchanged
config file. A failed or interrupted run retains it. After changing the config,
rerun Install before Authenticate/Verify. The per-process execution policy in
these commands does not change the machine/user policy or override Group Policy.

## Existing offline setups

Existing installed launchers retain their offline behavior until setup is rerun.
To switch, install Company Portal DBeaver and configure Artifactory as above. Copy
the example to `config.local.json` if the previous input was deleted, restore your
email and original connection values, and set `dbeaverPath`, `dbeaverWorkspace`,
and `installRoot` to the intended locations. Use `"dbeaverDriverSource":
"artifactory"`, close DBeaver, and rerun Install, Authenticate/Verify, and the
DBeaver connection test. Using the same instance, email, local port, and workspace
updates the existing managed profile to the standard PostgreSQL driver.

To deliberately retain the packaged workaround, use `"dbeaverDriverSource":
"offline"`. This mode copies the 11 pinned JARs and can install bundled DBeaver
when no existing executable is found. The default workflow never silently falls
back to this mode. An older input config that omits `dbeaverDriverSource` uses
Artifactory when Install is rerun; old installed settings remain offline.

## Bundled files and provenance

Pinned application versions and source records are in
[`assets/packages.json`](assets/packages.json); individual driver, proxy, and CA
hashes are in [`assets/files.json`](assets/files.json). Archives are split into
40 MiB parts to fit GitHub's file-size limit without requiring Git LFS. Setup
reassembles them locally and checks each part and full archive before extracting.

The initial offline application packages were repacked from the known working
Google SDK, DBeaver, and official Codex installation because public binary
downloads were blocked/reset on the build network. The Codex fallback is the
working `0.155.0-alpha.16.3` CLI and its companion tools; an already-working Codex
is preferred. No user profiles, Google credentials, Codex credentials, DBeaver
workspaces, or personal source files are inside these packages. Repacked archive
hashes differ from upstream download hashes. See [third-party notices](THIRD-PARTY-NOTICES.md).

## Maintainer checks

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Setup.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-OfflineInstall.ps1
```

Tests use isolated workspaces under ignored `.cache`, check preservation and
repeatability, config cleanup gates, fresh offline extraction and tool execution,
and leave the real user environment unchanged. The integration test also checks
Artifactory profile generation without copying offline JARs or extracting DBeaver.
It uses an isolated application fixture; it does not validate Company Portal
delivery or download from the internal mirror. Tests do not authenticate, grant
access, or claim a successful live database connection. The skill's Verify and
Complete phases perform the database check on each teammate's PC; the user must
also confirm the actual DBeaver Test Connection result.

The `maintainers` scripts rebuild pinned packages on a connected maintainer PC or
repack clean installed distributions. Changes to scripts, binaries, hashes, or CA
certificates should be reviewed together before distribution.

## References

- [Google: versioned SDK archives](https://docs.cloud.google.com/sdk/docs/downloads-versioned-archives)
- [Google: PostgreSQL IAM login and proxy networking](https://docs.cloud.google.com/sql/docs/postgres/iam-logins)
- [DBeaver: local driver configuration](https://dbeaver.com/docs/dbeaver/Admin-Manage-Drivers/)
- [DBeaver: driver management and Maven downloads](https://dbeaver.com/docs/dbeaver/Driver-Manager/)
- [DBeaver: authentication profile fields](https://github.com/dbeaver/dbeaver/wiki/Auth-Model-Reference)
- [DBeaver: command-line profile selection](https://dbeaver.com/docs/dbeaver/Command-Line/)
- [OpenAI: local skill discovery](https://learn.chatgpt.com/docs/build-skills)
