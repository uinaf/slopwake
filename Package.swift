// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SlopwakeCore",
    platforms: [
        .macOS("26.0"),
    ],
    products: [
        .library(name: "SlopwakeCore", targets: ["SlopwakeCore"]),
    ],
    targets: [
        .target(
            name: "SlopwakeCore",
            path: "Sources/SlopwakeCore"
        ),
        .testTarget(
            name: "SlopwakeCoreTests",
            dependencies: ["SlopwakeCore"],
            path: "Tests/SlopwakeCoreTests"
        ),
    ]
)
