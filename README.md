![slopwake — keep your slopshop awake.](https://uinaf.dev/og/banner/slopwake.png)

# slopwake

Keep your slopshop awake.

`slopwake` is a native macOS 26+ menu-bar app. It combines automatic agent
activity with bounded manual holds, without leaving an unbounded wake lock. One
owned `/usr/bin/caffeinate` child serves the resulting demand.

## Install

With Homebrew:

```sh
brew install --cask uinaf/tap/slopwake
```

Without Homebrew, install the latest signed release for your user:

```sh
curl -fsSL https://raw.githubusercontent.com/uinaf/slopwake/main/scripts/install.sh | bash
```

The installer verifies the release SHA-256 digest, bundle identity, version,
code signature, and Gatekeeper acceptance before copying `slopwake.app` to
`~/Applications`. It never requests administrator access. Pass options after
`bash -s --`, for example:

```sh
curl -fsSL https://raw.githubusercontent.com/uinaf/slopwake/main/scripts/install.sh | bash -s -- --help
```

The installer supports `--version`, `--install-dir`, and opt-in replacement
with `--force`.

Or download the universal ZIP from [GitHub Releases], then move
`slopwake.app` to `~/Applications` without administrator access, or to
`/Applications` if you have permission. The app is Developer ID signed and
notarized.

## Use

The menu exposes the current wake state and its active sources.

- Start a manual hold for 30 minutes, one hour, or eight hours.
- Pause automatic holds for 30 minutes, one hour, or until resumed.
- Enable Codex, Claude, and Cursor desktop or CLI detection independently.
- Allow display sleep, or keep the display awake while a hold is active.
- Set a battery cutoff from 5% to 30%, disable the cutoff, or keep the 15%
  default.
- Opt into Start at Login.

Automatic holds expire after 30 quiet minutes. A continuous automatic hold is
limited to eight hours and rearms after its activity becomes idle.

## Safety and privacy

Manual and automatic demand share one wake policy and one child process. The
child exits with the app, battery policy can release it, and display sleep stays
enabled by default.

Only preferences persist. Manual timers, pause timers, detected processes, and
activity state reset when the app exits.

Detection uses process identity, parent relationships, terminal presence, and
cumulative CPU counters. It does not inspect prompts, transcripts, files,
windows, or network traffic. The app has no accounts, analytics, telemetry, or
runtime network calls.

Detection is best-effort; it does not claim exact agent turn state. Wake holds
support an open lid. Normal powered clamshell use with an external display
continues to work, but `slopwake` does not bypass macOS bare closed-lid sleep or
corporate policy.

## Documentation

- [Architecture](docs/ARCHITECTURE.md) explains detection, policy, persistence,
  and process ownership.
- [Branding](docs/BRANDING.md) records the canonical product-art source.
- [Release workflow](docs/RELEASING.md) covers signing, notarization, and release
  artifacts.
- [Security](SECURITY.md) explains private vulnerability reporting.

## Contributing

Development requires macOS 26+ and Xcode 26+. See
[Contributing](CONTRIBUTING.md) for setup and verification commands.

## License

[MIT](LICENSE)

[GitHub Releases]: https://github.com/uinaf/slopwake/releases
