# Agent guidance

## Start

- Require macOS 26+ and Xcode 26+.
- Run `make release-check` for docs-only changes. Run `make verify` for product,
  build, installer, release, or CI changes before handoff.
- Treat `project.yml` as canonical; `Slopwake.xcodeproj` is generated.

## Boundaries

- Keep policy and child-process contracts in `Sources/SlopwakeCore/`.
- Keep AppKit, SwiftUI, IOKit, Service Management, and `UserDefaults` integration
  in `SlopwakeApp/`.
- Preserve one owned `caffeinate` child for the union of automatic and manual
  demand.
- Persist preferences only. Timers, process evidence, and activity history are
  memory-only.
- Target macOS 26 directly; do not add compatibility code for older releases.
- Keep signing and notarization credentials outside the repository and process
  them only at the release command boundary.

## Read next

- [Product behavior](README.md) for supported controls and privacy boundaries.
- [Contributing](CONTRIBUTING.md) for setup, focused tests, and verification.
- [Architecture](docs/ARCHITECTURE.md) before changing detection, wake policy,
  persistence, or process ownership.
- [Release workflow](docs/RELEASING.md) before changing signing, notarization,
  or release artifacts.
