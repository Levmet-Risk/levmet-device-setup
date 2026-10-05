---
name: levmet-device-setup
description: Set up a Windows x64 Levmet team PC for passwordless Cloud SQL PostgreSQL access, offline DBeaver drivers, Google Cloud CLI, Codex PATH, and reusable tunnel commands using this repository's user config.
---

Use this skill from the complete `levmet-device-setup` repository. The repository
root is three directories above this SKILL.md's folder. Do not copy this skill
folder by itself: its scripts and offline assets live at the repository root.

Read [the config and troubleshooting reference](references/setup.md) when preparing
the config or diagnosing a failed phase. Run the supplied scripts rather than
recreating installers or hand-editing the user's DBeaver workspace.

1. Confirm this is Windows x64 and locate `config.local.json` in the repository.
   If absent, copy `config.example.json` and ask the user to edit the file on disk.
   The user supplies their own email and any changed connection values/paths.
   Do not request Google passwords, access tokens, service-account keys, or the
   full config in chat. The established authentication mode is automatic IAM,
   with a blank local PostgreSQL password and interactive Google browser sign-in.
2. Validate through the scripts. If DBeaver is running, ask the user to save their
   work and close it before Install; never force-close an active workspace.
   Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File <repo>\Setup.ps1
   -Phase Install`. Quote paths containing spaces. This changes user PATH and CA
   environment values, installs missing tools, and adds the managed DBeaver
   profile while preserving existing profiles. Do not weaken Windows Group Policy,
   TLS verification, proxy checks, or network controls if installation is blocked.
3. Run the Authenticate phase. Let the user complete Google sign-in with the email
   in their config. Authentication is interactive and cannot be completed by
   copying the maintainer's ADC or credentials. If the user already has valid ADC,
   Verify may be attempted first; a failed authentication requires Authenticate.
4. Run Verify. Require a successful real read-only database query matching the
   configured IAM user and database; a listening local port is insufficient.
   Verify leaves the config intact and stops only the temporary proxy it created.
   Diagnose failures from the installed `logs` folder without printing tokens or
   dumping config/ADC files. Explain any external IAM/firewall action required.
5. Have the user run `levmet-db-tunnel` in a terminal and keep it open, then run
   `levmet-dbeaver`. In already-open terminals, use the absolute generated `.cmd`
   paths under their install root, or refresh PATH from user/machine environment.
   Ask the user to confirm **Test Connection succeeds for the managed profile**.
   Wait for that actual confirmation; don't infer it from an open window or a
   successful network probe.
6. Only after that confirmation, run Complete with `-DBeaverConfirmed`. This repeats
   verification and deletes only the unchanged `config.local.json` after all checks
   pass. Never pass the confirmation switch on the user's behalf before receiving
   their DBeaver result. On any error, retain the file for the next attempt.

Report the installed location, useful commands, validation result, and whether
config deletion actually succeeded. Tell the user to restart existing terminal/IDE
windows to inherit PATH. Account credentials remain in Google's normal local ADC
store; non-secret connection settings remain in the installed runtime settings and
DBeaver profile so the tunnel continues to work after the input config is deleted.

Do not create IAM users, modify Cloud SQL settings, change firewall policy, publish
repositories, or grant team access as part of this device setup skill.
