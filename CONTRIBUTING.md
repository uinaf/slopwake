# Contributing

## Setup

Requirements:

- macOS 26+
- Xcode 26+

Generate the Xcode project and open it:

```sh
make project
open Slopwake.xcodeproj
```

`project.yml` is the source of truth; `Slopwake.xcodeproj` is generated and
ignored by git.

## Verify

Run the complete local gate:

```sh
make verify
```

This runs the Swift package tests, the Xcode-hosted app-model tests, release
contract checks, and a warning-strict universal Release build. The hosted test
app starts without live services; app-model tests supply isolated preferences
and fake services.

Use a focused target while iterating:

| Command | Purpose |
| --- | --- |
| `make core-test` | Policy, detector, preference, and child-process contracts |
| `make app-test` | App coordination through the hosted test target |
| `make release-check` | Release configuration, version, and cask-generation contracts |
| `make build` | Universal arm64 and x86_64 Release app |
| `make release RELEASE_VERSION=x.y.z` | Signed and notarized local artifact; requires injected credentials |

Write deterministic contract tests at the strongest boundary that owns the
behavior; macOS tools are trusted as given.

CI picks verification lanes from the changed paths in
`.github/verification-paths.yml`.

## Project boundaries

- `Sources/SlopwakeCore/` owns platform-independent policy and process control.
- `SlopwakeApp/` owns macOS monitoring, persistence, login items, and menu UI.
- The deployment target is macOS 26 only.
- Release credentials live outside the repository.

## Dependency automerge

- Eligible Renovate updates use GitHub auto-merge after the required `verify`
  check.
- Checks are non-strict. Repository admins and the release App bypass the
  check ruleset for direct writes; Renovate does not.
- A new workflow check becomes required only once it is added to the ruleset.
