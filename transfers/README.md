# Prepared environment transfer

`levmet-code-env-20261009.levmet-env` is the actual password-encrypted export
from the source PC, published here at the user's request. It was decrypted
locally using the separately saved password and checked against the source
payload before publication.

On the new PC, from this repository:

```powershell
git pull --ff-only
.\CodeEnvironment.cmd -Phase Apply -BundlePath ".\transfers\levmet-code-env-20261009.levmet-env"
.\CodeEnvironment.cmd -Phase Verify
```

Enter the password at the masked prompt. Its local text file is on the source
PC under `%LOCALAPPDATA%\Levmet\CodeEnvironment\TransferKeys`, in the export's
subfolder, named `levmet-code-env-20261009-password.txt`. Access to that folder
is restricted to the source Windows user. Transfer the password separately;
it is not in this repository. Restart terminals and IDEs after Apply.

This export contains the configured `SENDGRID_API_KEY`. No Graph credential,
broker SFTP password, or legacy mail passwords were present on the source PC.
Paths and database identity are configured from the destination's roots and
completed device setup. Missing credentials and input paths remain visible in
Verify. The export does not imply that every legacy reporting script is ready.

SHA-256 of the encrypted bundle:

```text
e05cb9ea085731536ac3fb86f1d584393a36db2e50bfacba58169f371025d8ec
```

See [the full guide](../CODE-ENVIRONMENT.md) for layout overrides, missing
credentials, and rollback. Other encrypted exports remain ignored by Git;
publishing this specific artifact does not change that default.
