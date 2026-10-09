---
name: levmet-code-environment
description: Configure Windows user environment variables for the Levmet reporting code after device setup, audit missing paths and credentials, and transfer configured API/mail credentials between PCs using a password-protected bundle. Use without repeating DBeaver or Google authentication setup.
---

Run from the complete `levmet-device-setup` repository; its root is three
directories above this skill folder. Read [the variable inventory](references/inventory.md)
for scope and [the command/configuration guide](../../../CODE-ENVIRONMENT.md) for
the supported commands, overrides, and recovery procedure.

1. Locate the reporting `Code` folder and its data root. The default is
   `%USERPROFILE%\Marex\Levmet Risk Prod - Documents\levmet-risk\Code`.
   Run `CodeEnvironment.cmd -Phase Audit`, with `-CodeRoot` if different. Audit
   statically reads source; never import or run reporting modules to discover
   settings. Some execute database writes or send mail even in a named dry run.
2. Reuse the destination device setup's `settings.json` for IAM identity and
   tunnel settings. The original input `config.local.json` may already have been
   deleted; do not recreate it or repeat the device setup. If necessary, use
   `code-environment.local.json` (from the separate example), `-Email`, or
   `-DeviceSetupRoot`. Distinguish the Google/IAM identity from a verified mail
   sender; do not guess one from the other.
3. For an authorized credential migration, run `CodeEnvironment.cmd -Phase Export
   -BundlePath "<local transfer path>.levmet-env"` on the source PC in a terminal
   where the user can enter the masked passphrase and confirmation. The scripts
   export only supported configured variables and the selected Graph credential.
   Do not put passphrases or credential values in chat, commands, source, reports,
   or Git. Transfer the encrypted file and keep the passphrase separate.
   If the user requests an unattended export, generate a password with a
   cryptographic random generator and at least 32 random bytes; save it outside
   the repository in a file restricted to that Windows user. Pass it in memory
   as a SecureString to the core module, and verify decryption before reporting
   completion. An explicit request to publish the encrypted bundle authorizes
   adding that exact artifact to Git; its password must remain separate.
4. On the destination, run `CodeEnvironment.cmd -Phase Complete` to apply the
   prepared repository bundle, configure paths/database identity, and verify all
   managed settings in one run. For another bundle, pass `-BundlePath
   "<copied transfer path>.levmet-env"`. Use an interactive terminal for the
   masked passphrase prompt. Apply without a bundle is also useful: it configures the
   available paths/identity now and can import credentials later. Honor intended
   target paths and the audit's conflicts; use `-ReplaceExisting` when replacing
   those settings is part of the user's request. A DPAPI backup permits rollback.
5. Read the category counts and remaining gaps from Complete, or run Verify after
   a separate Apply. A SendGrid success message alone does not confirm full setup.
   SetSecret changes one credential and must not substitute for Complete.
   Missing credentials can be entered locally
   using the masked `SetSecret -Name <supported name>` or `SetGraphSecret` phase.
   Do not treat absent source credentials as a completed migration. The ICE
   credentials JSON is only a referenced path; the transfer does not copy it.

Audit/Apply cover the 48 managed variable names. The inventory also accounts for
run-specific flags/dates, OS/launcher values, generic application-local settings,
and a test flag; those are not made permanent user settings. Unset optional
settings retain application defaults. Unknown variable names and remaining
hardcoded paths require review; do not invent values or claim all legacy scripts
are portable because the environment was configured.

Do not send test mail, run reports, start scheduled jobs, modify the reporting
code, or change provider permissions as part of environment verification.
Presence checks do not verify service access or credential validity.

Report which settings were applied, the encrypted bundle/backup/report locations
when created, and remaining missing credentials or input paths. Tell the user to
restart terminals/IDEs and relaunch jobs to inherit the environment. If the new PC
is not accessible, deliver the prepared follow-up and exact source/destination
commands; do not claim it has been configured remotely.
