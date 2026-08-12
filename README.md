# slopwake

Keep your Mac awake while supported coding agents work, without an unbounded
wake lock.

`slopwake` is a native macOS 26+ menu-bar app. It combines automatic agent
activity with bounded manual holds and owns a single `/usr/bin/caffeinate`
child for the resulting demand.

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
windows, or network traffic.

## Build from source

Development requires macOS 26+ and Xcode 26+. See [Contributing](CONTRIBUTING.md)
for setup and verification commands.

## Documentation

- [Architecture](docs/ARCHITECTURE.md) explains detection, policy, persistence,
  and process ownership.
- [Branding](docs/BRANDING.md) records the canonical product-art source.
- [Release workflow](docs/RELEASING.md) covers signing, notarization, and release
  artifacts.

## License

[MIT](LICENSE)
