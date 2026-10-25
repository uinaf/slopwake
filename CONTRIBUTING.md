# Contributing

Requires macOS 26+ and Xcode 26+.

```sh
make project              # generate Slopwake.xcodeproj from project.yml
open Slopwake.xcodeproj
make verify               # full local gate
```

Focused targets:

| Command | Covers |
| --- | --- |
| `make core-test` | Policy, detector, preference, and child-process contracts |
| `make app-test` | App coordination through the hosted test target |
| `make release-check` | Release configuration, version, and cask generation |
| `make build` | Universal Release app |
| `make release RELEASE_VERSION=x.y.z` | Signed, notarized artifact; needs injected credentials |

Test at the boundary that owns the behavior; trust macOS tools as given.
