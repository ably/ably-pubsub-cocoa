// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Darwin.C

let package = Package(
    name: "SPMIntegration",
    platforms: [
        .iOS(.v9),
        .macOS(.v10_11)
    ],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .target(
            name: "SPMIntegration",
            dependencies: [
                // `package:` is the dependency's identity, which for a path
                // dependency is the directory name, not the manifest's `name`.
                .product(name: "AblyPubSubCore", package: "ably-cocoa")
            ],
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors"])
            ]),
        .testTarget(
            name: "SPMTests",
            dependencies: ["SPMIntegration"],
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors"])
            ]),
    ]
)
