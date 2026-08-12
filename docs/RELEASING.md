# Release workflow

Pushes to `main` run verification and release automatically. Conventional
Commits select the version, Apple accepts the signed artifact before it becomes
public, and the same immutable ZIP supplies the Homebrew cask.

## Versioning

| Commit | Release |
| --- | --- |
| `feat:` | minor |
| `fix:`, `perf:`, `refactor:` | patch |
| breaking change | major |
| `build:`, `chore:`, `ci:`, `docs:`, `test:` | none |

`semantic-release` writes the selected version to `VERSION` and the canonical
`project.yml`, then `uinaf-releaser` commits both through GitHub's API so the
org `required_signatures` ruleset accepts the writeback. The commit message
includes `[skip ci]`, and that commit is tagged `v<version>`. The app build
receives the same version as `CFBundleShortVersionString`.

## Pipeline

1. `make verify` runs on a macOS 26 runner with Xcode 26.6.
2. The protected `release` environment exposes Apple signing material and a
   short-lived `uinaf-releaser` token. The job re-checks that live `main` still
   equals the analyzed SHA immediately before version writeback.
3. `scripts/prepare-release.sh` writes `VERSION` and `project.yml` only.
   `uinaf-releaser` commits those files through GitHub's API, then
   `semantic-release` opens a draft GitHub Release.
4. The workflow then builds, Developer ID signs, notarizes, and uploads the ZIP
   to that draft. It verifies the uploaded SHA-256 digest before publishing.
   Organization policy then makes the release asset and tag [immutable].
5. The workflow writes the exact version and checksum to `uinaf/homebrew-tap`,
   runs Homebrew's online cask audit, and commits the cask through GitHub's API
   so the tap commit is App-signed.
6. A clean runner installs the cask, launches the app, observes an owned wake
   hold, quits it, checks that the hold exited, and uninstalls with preferences
   removed.

The first release proves installation and uninstall. A real Homebrew upgrade
can only be exercised after a second version exists.

## Release environment

The `release` GitHub Environment is restricted to `main` and provides:

| Name | Kind |
| --- | --- |
| `UINAF_RELEASE_APP_CLIENT_ID` | variable |
| `UINAF_RELEASE_APP_PRIVATE_KEY` | secret |
| `APPLE_TEAM_ID` | variable |
| `APPLE_NOTARY_API_KEY_ID` | variable |
| `APPLE_NOTARY_API_ISSUER_ID` | variable |
| `APPLE_DEVELOPER_ID_CERTIFICATE_P12_BASE64` | secret |
| `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD` | secret |
| `APPLE_NOTARY_API_KEY_P8_BASE64` | secret |

Keep credentials outside the repository and inject them only at the release
process boundary. The signing script decodes them in a private temporary
directory and never imports the certificate into a keychain.

## Local notarization proof

Run the complete gate before credentials enter the process:

```sh
make verify
```

Then inject the six Apple variables through an approved secret manager:

```sh
make release RELEASE_VERSION=1.0.0
```

An accepted submission produces:

- `.artifacts/releases/slopwake-<version>.<submission-id>/slopwake.app`
- `dist/slopwake-<version>-macos-universal.zip`

The ZIP is rebuilt after stapling. Its app contains exactly arm64 and x86_64,
has bundle identifier `dev.uinaf.slopwake`, and carries the requested release
version.

## Failure and recovery

Signing, notarization, stapling, Gatekeeper, draft digest validation, Homebrew
audit, and install smoke are hard failures. Temporary credentials and partial
local staging directories are removed when the command exits.

If semantic-release creates a draft but publication stops, inspect the draft
and its asset digest, fix the failing step, and rerun the same release job. Do
not publish a draft by hand or reuse a tag with different bytes. Immutable
verification, Homebrew, and install smoke run only after the GitHub Release is
published. If publication succeeds but the cask update fails, keep the
immutable release and rerun only the cask generation, audit, and smoke against
its existing asset.

[immutable]: https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases
