# Contributing

Requires macOS 26+ and Xcode 26+.

```sh
make project              # generate Slopwake.xcodeproj from project.yml
open Slopwake.xcodeproj
make verify               # full local gate
```

Focused targets live in the [`Makefile`](Makefile).

Test at the boundary that owns the behavior; trust macOS tools as given.
