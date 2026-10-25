![slopwake — keep your slopshop awake.](https://uinaf.dev/og/banner/slopwake.png)

# uinaf/slopwake

Keep your slopshop awake.

A macOS 26+ menu-bar app. It holds one `/usr/bin/caffeinate` child while a
coding agent is active or a manual hold runs.

## Install

```sh
brew install --cask uinaf/tap/slopwake
```

Without Homebrew:

```sh
curl -fsSL https://raw.githubusercontent.com/uinaf/slopwake/main/scripts/install.sh | bash
# options: ... | bash -s -- --help
```

The installer checks the digest, signature, and Gatekeeper, then installs to
`~/Applications` without administrator access. Or download the ZIP from
[GitHub Releases].

## Use

- Manual hold: 30 minutes, one hour, or eight hours.
- Pause automatic holds: 30 minutes, one hour, or until resumed.
- Detection for Codex, Claude, and Cursor, desktop and CLI, each toggled
  separately.
- Display sleep stays allowed unless you turn it off.
- Battery cutoff: 5% to 30%, default 15%, or off.
- Start at Login: opt-in.

Automatic holds expire after 30 quiet minutes.

## Privacy

- Only preferences persist. Timers, detected processes, and activity reset on
  quit.
- Detection reads process identity, parents, terminal presence, and CPU
  counters. It never reads prompts, transcripts, files, windows, or network
  traffic.
- No accounts, analytics, telemetry, or network calls at runtime.
- Detection is best-effort. `slopwake` does not bypass closed-lid sleep without
  an external display, or corporate policy.

## Links

- [Architecture](docs/ARCHITECTURE.md)
- [Contributing](CONTRIBUTING.md)
- [Security](https://github.com/uinaf/slopwake/security/policy)
- [MIT license](LICENSE)

[GitHub Releases]: https://github.com/uinaf/slopwake/releases
