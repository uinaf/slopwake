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

CI classifies changed paths with `.github/verification-paths.yml`. Pull
requests are classified through the GitHub API and need only the filter file
checked out; push events diff against the previous commit, and the filter
deepens the shallow clone itself.

## Project boundaries

- `Sources/SlopwakeCore/` owns platform-independent policy and process control.
- `SlopwakeApp/` owns macOS monitoring, persistence, login items, and menu UI.
- The deployment target is macOS 26. Compatibility branches for older releases
  are out of scope.
- Release credentials must remain outside the repository. Follow the
  [release workflow](docs/RELEASING.md).

## Dependency automerge

- Eligible Renovate updates use GitHub auto-merge after required checks: verify and scan / Gitleaks, scan / TruffleHog, scan / Actionlint, scan / Zizmor.
- Checks are non-strict; repository admins and the existing release App retain direct writes through
  a bypass limited to the check ruleset. Renovate has no bypass.
- Shared release-age and major/digest rules remain unchanged. Add new voting
  checks to the ruleset; workflow presence alone does not require them.
