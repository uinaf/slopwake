# Agent guidance

## Start

- Require macOS 26+ and Xcode 26+.
- Run `make release-check` for docs-only changes. Run `make verify` for product,
  build, installer, release, or CI changes before handoff.
- Edit `project.yml`; `Slopwake.xcodeproj` is generated.
- A push to `main` releases by commit type, per the rules in
  [`.releaserc.json`](.releaserc.json). Pick the type for the release it should
  cause.
- If a release stops after its draft exists, fix the failing step and resume
  with `gh workflow run ci.yml --ref main -f "release_version=$(sed -n '1p' VERSION)"`.
  Never publish a draft by hand or reuse a tag with different bytes.

## Boundaries

- Policy and child-process contracts live in `Sources/SlopwakeCore/`.
- AppKit, SwiftUI, IOKit, Service Management, and `UserDefaults` code lives in
  `SlopwakeApp/`.
- Keep signing and notarization credentials outside the repository; use them
  only at the release command boundary.
- Keep the README banner on uinaf.dev, not in the repository.

## Read next

- [Architecture](docs/ARCHITECTURE.md) before changing detection, wake policy,
  persistence, or process ownership.
- [Release runbook](https://app.notion.com/p/3e5e75710b5281d3a3e3dc8041e546fa)
  (Notion) before changing signing, notarization, or release artifacts.

## Repository skills

- [Swift concurrency](.agents/skills/swift-concurrency/SKILL.md): tasks, actor isolation, Sendable, callback-to-async.
- [SwiftUI](.agents/skills/swiftui-expert-skill/SKILL.md): views, state, layout, accessibility.
- [Swift testing](.agents/skills/swift-testing-expert/SKILL.md): test architecture and async test failures; keep the existing test framework.
- [Xcode build optimization](.agents/skills/xcode-build-orchestrator/SKILL.md): build timing; keep `project.yml` as the project source.
