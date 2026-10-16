## Install

Download `RFC-Reader-VERSION_PLACEHOLDER.dmg`, drag RFC Reader to Applications, and open it. It updates itself from then on; Settings ▸ General turns off the automatic checks.

## Where this build came from

A public GitHub Actions run built this release from a public commit, and recorded a signed provenance attestation over the disk image.

- **Commit:** `COMMIT_PLACEHOLDER`
- **Build log:** RUN_URL_PLACEHOLDER
- **Attestation:** ATTESTATION_URL_PLACEHOLDER
- **SHA-256:** `SHA256_PLACEHOLDER`

To check a download against them:

```sh
shasum -a 256 RFC-Reader-VERSION_PLACEHOLDER.dmg
gh attestation verify RFC-Reader-VERSION_PLACEHOLDER.dmg --repo REPOSITORY_PLACEHOLDER
```

This proves which source and which run produced the file, not that a rebuild gives the same bytes: Xcode's output is not reproducible.

Updates are signed with a key the maintainer holds, which the build system never sees, so the build system alone cannot ship an update.
