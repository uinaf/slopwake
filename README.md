# slopwake

Keep your slopshop awake.

`slopwake` is a native macOS 26+ menu-bar app. This first tracer bullet owns a
single `/usr/bin/caffeinate -ims` child so a user can start and stop a wake hold
without administrator access. The child also watches the app process and exits
if the app crashes.

## Development

Requirements:

- macOS 26+
- Xcode 26+

Run the core tests, build the universal app, inspect both architectures, apply
and verify an ad-hoc hardened-runtime signature, then launch and terminate the
Release executable:

```sh
make verify
```

The project generator downloads a pinned XcodeGen release into the ignored
`.artifacts` directory and verifies its SHA-256 digest. Open the generated
project with:

```sh
make project
open Slopwake.xcodeproj
```

## Manual wake-hold check

1. Record the baseline with `pmset -g assertions`.
2. Launch `DerivedData/Build/Products/Release/slopwake.app`.
3. Choose **Keep Awake** from the menu-bar item.
4. Confirm `pmset -g assertions` reports the `caffeinate` assertions.
5. Choose **Allow Sleep** and confirm the assertions disappear.
6. Start another hold, quit `slopwake`, and confirm no child or assertion remains.

The system bolt is temporary development artwork and is not a publishable
product mark.

## Automatic detection

`slopwake` independently watches Codex Desktop/CLI, Claude Desktop/CLI, and
Cursor Desktop/CLI. Headless CLI processes hold for their lifetime. Interactive
CLI and desktop surfaces arm only after their public CPU counters advance;
Claude Desktop may also use the lifetime of its descendant local-agent process.
Recent activity expires after 30 quiet minutes. A continuous automatic hold is
capped at eight hours and rearms only after the evidence becomes idle first.

This is deliberately best-effort inference, not exact active-turn detection.
The sampler keeps only process IDs plus start times, parent relationships,
executable names, bundle identifiers, terminal presence, and cumulative CPU
counters in memory. It does not read arguments, prompts, transcripts,
databases, logs, sockets, window text, workspace names, or file contents.

## Notarized smoke build

An authorized workstation can consume the adjacent private `uinaf/vault`
payload through a process boundary and produce a Developer ID-signed, notarized,
stapled smoke artifact:

```sh
make build
sops exec-env --same-process \
  ../vault/secrets/shared/uinaf-macos-release-signing.sops.json \
  'make notarized-smoke'
```

The build runs before the release credentials enter the environment. The
notarization command verifies a checksum-pinned `rcodesign` archive on every
run, writes only a fully validated app and ZIP below ignored `.artifacts`, and
removes all decoded certificate, certificate-password, and notary-key material
before returning. It does not import the signing identity into a macOS
keychain.

## Release gates

A release still requires a universal Developer ID signature, hardened-runtime
verification, Apple notarization and stapling, Gatekeeper acceptance, and a
launch plus wake-hold check from `~/Applications` on the managed work Mac. An
MDM failure is a stop condition, not a reason to bypass policy.

## License

MIT
