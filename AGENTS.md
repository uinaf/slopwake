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

## Repository skills

- Use [Swift concurrency](.agents/skills/swift-concurrency/SKILL.md) for tasks, actor isolation, Sendable, and callback-to-async changes.
- Use [SwiftUI](.agents/skills/swiftui-expert-skill/SKILL.md) for view, state, layout, and accessibility changes.
- Use [Swift testing](.agents/skills/swift-testing-expert/SKILL.md) for test architecture and async test failures; preserve the existing test framework unless migration is requested.
- Use [Xcode build optimization](.agents/skills/xcode-build-orchestrator/SKILL.md) for build timing and optimization work; its five companion skills are installed alongside it. Keep `project.yml` as the project source and use the repository build commands.
