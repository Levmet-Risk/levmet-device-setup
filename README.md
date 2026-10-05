# Levmet Windows device setup

Private team onboarding for Windows x64 PCs. The repository contains a Codex skill,
PowerShell setup scripts, the Google Cloud CLI with Python, the Cloud SQL Auth
Proxy, a portable DBeaver distribution, Codex CLI fallback binaries, the Marex
public CA bundle, and all 11 PostgreSQL JDBC libraries from the working setup.
Installing these files needs no Maven/GUI downloads or administrator privileges.
Google sign-in and database access still require the corporate network and the
user's existing IAM permissions.

## Start on a new PC

1. Clone this private repository, or use GitHub **Code > Download ZIP** and extract
   it to a short, permanent, non-synced path such as
   `C:\Users\YOUR_USERNAME\levmet-device-setup`. Download the whole repository;
   individual skill files or GitHub's source preview are insufficient.
2. Copy `config.example.json` to **`config.local.json`**. Set `email` to your own
   work Google/IAM email. Review the shared database defaults and paths. Change
   them if your administrator supplied different values. The config reference is
   [here](.agents/skills/levmet-device-setup/references/setup.md).
3. Open a terminal in the extracted folder and run **`Bootstrap.cmd`**. It checks
   Codex, repairs PATH, installs the bundled CLI if needed, then opens Codex in
   this repository with the setup skill selected. On its first use, sign in to
   Codex with your own account. If you already have Codex open here, invoke
   **`$levmet-device-setup`** directly instead.
4. Let the skill run setup. Close DBeaver when asked so its workspace can be
   updated. Complete Google browser sign-in using the email in your config.
5. Follow the skill's instructions to open the tunnel and the managed DBeaver
   profile. Click **Test Connection** and tell Codex the actual result. After
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
  normally `%LOCALAPPDATA%\Levmet\DeviceSetup`. A working Codex installation and
  an existing DBeaver installation are reused when found.
- Adds the necessary directories to **user** PATH without overwriting existing
  entries. Sets `LEVMET_SETUP_HOME`, `SSL_CERT_FILE`, and
  `CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE`. The CA file combines the SDK's public roots
  with the configured corporate certificates.
- Adds a separate **Levmet PostgreSQL (offline)** driver definition referencing
  all 11 local JARs and a managed connection profile. Existing profiles and other
  drivers are preserved. Changed workspace files and previous environment values
  are backed up under `installRoot\backups`.
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

From the repository folder in PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 -Phase Install
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 -Phase Authenticate
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 -Phase Verify
```

Then run `levmet-db-tunnel` in a separate terminal, run `levmet-dbeaver`, and check
**Test Connection** for the managed profile. Only after it succeeds:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 -Phase Complete -DBeaverConfirmed
```

`Complete` repeats the real database query before deleting the exact unchanged
config file. A failed or interrupted run retains it. After changing the config,
rerun Install before Authenticate/Verify. The per-process execution policy in
these commands does not change the machine/user policy or override Group Policy.

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
and leave the real user environment unchanged. They do not authenticate, grant
access, or claim a successful live database connection. The skill's Verify and
Complete phases perform that check on each teammate's PC.

The `maintainers` scripts rebuild pinned packages on a connected maintainer PC or
repack clean installed distributions. Changes to scripts, binaries, hashes, or CA
certificates should be reviewed together before distribution.

## References

- [Google: versioned SDK archives](https://docs.cloud.google.com/sdk/docs/downloads-versioned-archives)
- [Google: PostgreSQL IAM login and proxy networking](https://docs.cloud.google.com/sql/docs/postgres/iam-logins)
- [DBeaver: local driver configuration](https://dbeaver.com/docs/dbeaver/Admin-Manage-Drivers/)
- [DBeaver: authentication profile fields](https://github.com/dbeaver/dbeaver/wiki/Auth-Model-Reference)
- [DBeaver: command-line profile selection](https://dbeaver.com/docs/dbeaver/Command-Line/)
- [OpenAI: local skill discovery](https://learn.chatgpt.com/docs/build-skills)
