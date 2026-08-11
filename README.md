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

Run the core tests and build the unsigned universal app:

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

## Release gates

A release still requires a universal Developer ID signature, hardened-runtime
verification, Apple notarization and stapling, Gatekeeper acceptance, and a
launch plus wake-hold check from `~/Applications` on the managed work Mac. An
MDM failure is a stop condition, not a reason to bypass policy.

## License

MIT
