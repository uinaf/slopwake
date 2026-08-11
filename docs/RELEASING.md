# Release workflow

The release command signs an existing universal Release build with Developer
ID, submits it to Apple notarization, staples the ticket, and verifies
Gatekeeper acceptance.

## Prepare

Run the complete gate before release credentials enter the process:

```sh
make verify
```

The expected app is
`DerivedData/Build/Products/Release/slopwake.app` and must contain exactly arm64
and x86_64.

## Sign and notarize

Provide these environment variables through an approved secret manager:

- `APPLE_DEVELOPER_ID_CERTIFICATE_P12_BASE64`
- `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `APPLE_NOTARY_API_ISSUER_ID`
- `APPLE_NOTARY_API_KEY_ID`
- `APPLE_NOTARY_API_KEY_P8_BASE64`
- `APPLE_TEAM_ID`

Run the release boundary inside that injected process:

```sh
make release
```

The workflow downloads a checksum-pinned `rcodesign`, decodes credentials into
a private temporary directory, and does not import the signing identity into a
keychain.

## Outputs

An accepted submission produces:

- `.artifacts/releases/slopwake-notarized.<submission-id>/slopwake.app`
- `.artifacts/releases/slopwake-notarized.<submission-id>/slopwake-notarized.zip`

The app is Developer ID signed with hardened runtime, notarized, stapled, and
accepted by `spctl`. The ZIP is rebuilt after stapling.

## Failure behavior

Credential material and temporary extraction directories are removed when the
command exits. An unsuccessful release removes its staging directory and leaves
the source Release build unchanged. Treat signing, notarization, stapling, or
Gatekeeper failure as a failed release.
