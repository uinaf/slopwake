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

`project.yml` is the source of truth. The generated Xcode project is ignored
and must not be edited as project configuration.

## Verify

Run the complete local gate:

```sh
make verify
```

This runs the Swift package tests, the Xcode-hosted app-model tests, release
contract checks, and a warning-strict universal Release build.

Use a focused target while iterating:

| Command | Purpose |
| --- | --- |
| `make core-test` | Policy, detector, preference, and child-process contracts |
| `make app-test` | App coordination through the hosted test target |
| `make release-check` | Release configuration, version, and cask-generation contracts |
| `make build` | Universal arm64 and x86_64 Release app |
| `make release RELEASE_VERSION=x.y.z` | Signed and notarized local artifact; requires injected credentials |

Prefer deterministic contract tests. Do not add tests whose only purpose is to
re-prove macOS tool behavior or duplicate a contract already covered at a
stronger boundary.

## Project boundaries

- `Sources/SlopwakeCore/` owns platform-independent policy and process control.
- `SlopwakeApp/` owns macOS monitoring, persistence, login items, and menu UI.
- The deployment target is macOS 26. Compatibility branches for older releases
  are out of scope.
- Release credentials must remain outside the repository. Follow the
  [release workflow](docs/RELEASING.md).
