// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "ably-pubsub-cocoa",
    platforms: [
        .macOS(.v10_11),
        .iOS(.v9),
        .tvOS(.v10)
    ],
    products: [
        // The shared implementation of the SDK, for use by Ably's own
        // packages. A client built from it does not declare that it runs on an
        // end user's device, so Ably classifies its traffic by default rules;
        // applications depend on AblyPubSubDevice, which does declare it.
        .library(
            name: "AblyPubSubCore",
            targets: ["Ably"]
        ),
        // The entry point for apps: creates clients that declare they are
        // running on an end user's device.
        .library(
            name: "AblyPubSubDevice",
            targets: ["AblyPubSubDevice"]
        ),
        .library(
            name: "AblyLiveObjects",
            targets: ["AblyLiveObjects"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/rvi/msgpack-objective-C", from: "0.4.0"),
        .package(url: "https://github.com/ably/delta-codec-cocoa", from: "1.3.5"),
        .package(url: "https://github.com/quick/nimble", from: "11.2.2")
    ],
    targets: [
        // The LiveObjects plugin. Formerly the separate
        // ably-liveobjects-swift-plugin repository. Unlike the rest of the
        // package it requires macOS 11 / iOS 14 / tvOS 14, which it declares
        // through @available annotations on all of its top-level declarations
        // (see Scripts/annotate-liveobjects-availability.py).
        .target(
            name: "AblyLiveObjects",
            dependencies: [
                .target(name: "Ably"),
                .target(name: "_AblyPluginSupportPrivate"),
            ],
            path: "LiveObjects/Sources/AblyLiveObjects"
        ),
        .testTarget(
            name: "AblyLiveObjectsTests",
            dependencies: [
                .target(name: "AblyLiveObjects"),
                .target(name: "AblyLiveObjectsTesting"),
                .target(name: "Ably"),
                .target(name: "_AblyPluginSupportPrivate"),
                // Shared provisioning-retry helper + nonprod sandbox host constant.
                .byName(name: "AblyTesting"),
            ],
            path: "LiveObjects/Tests/AblyLiveObjectsTests",
            exclude: [
                "CLAUDE.md"
            ]
        ),
        // Test-support module hosting internal-access extensions of
        // AblyLiveObjects types (via @testable import), plus shared test
        // helpers/mocks, so production sources stay free of test plumbing.
        // Consumed by the LiveObjects test targets via
        // @testable import AblyLiveObjectsTesting; deliberately not a
        // product member, so it is unreachable from — and never built by —
        // consumers of the shipped AblyLiveObjects library. See
        // Test/AblyLiveObjectsTesting/README.md.
        .target(
            name: "AblyLiveObjectsTesting",
            dependencies: [
                .target(name: "AblyLiveObjects"),
                .target(name: "Ably"),
                .target(name: "_AblyPluginSupportPrivate"),
            ],
            path: "Test/AblyLiveObjectsTesting",
            exclude: [
                "README.md"
            ]
        ),
        // Private API of the core SDK, exposed to Ably-authored plugins. Formerly
        // the separate ably-cocoa-plugin-support repository; deliberately not
        // vended as a product.
        .target(
            name: "_AblyPluginSupportPrivate",
            path: "_AblyPluginSupportPrivate"
        ),
        // Creates clients that declare they are running on an end user's
        // device, by stamping the agent entry Ably classifies on.
        .target(
            name: "AblyPubSubDevice",
            dependencies: [
                .target(name: "Ably"),
            ],
            path: "PubSubDevice",
            publicHeadersPath: "include"
        ),
        // The core SDK. Vended as the AblyPubSubCore product; its module is
        // named `Ably`.
        .target(
            name: "Ably",
            dependencies: [
                .product(name: "msgpack", package: "msgpack-objective-C"),
                .product(name: "AblyDeltaCodec", package: "delta-codec-cocoa"),
                .target(name: "_AblyPluginSupportPrivate")
            ],
            path: "Source",
            exclude: [
                "Info-iOS.plist",
                "Info-tvOS.plist",
                "Info-macOS.plist"
            ],
            resources: [.copy("PrivacyInfo.xcprivacy")],
            publicHeadersPath: "include",
            cSettings: [
                .define("ABLY_SUPPORTS_PLUGINS"),
                .headerSearchPath("PrivateHeaders"),
                .headerSearchPath("PrivateHeaders/Ably"),
                .headerSearchPath("include/Ably"),
                .headerSearchPath("SocketRocket"),
                .headerSearchPath("SocketRocket/Internal"),
                .headerSearchPath("SocketRocket/Internal/Security"),
                .headerSearchPath("SocketRocket/Internal/Proxy"),
                .headerSearchPath("SocketRocket/Internal/Utilities"),
                .headerSearchPath("SocketRocket/Internal/RunLoop"),
                .headerSearchPath("SocketRocket/Internal/Delegate"),
                .headerSearchPath("SocketRocket/Internal/IOConsumer"),
            ]
        ),
        .testTarget(
            name: "AblyTests",
            dependencies: [
                .byName(name: "Ably"),
                .target(name: "AblyPubSubDevice"),
                .byName(name: "AblyTesting"),
                .byName(name: "AblyTestingObjC"),
                .product(name: "Nimble", package: "nimble"),
                .target(name: "_AblyPluginSupportPrivate")
            ],
            path: "Test/AblyTests",
            resources: [
                .copy("ably-common")
            ],
            swiftSettings: [
                // This test code predates the Swift 6 language mode.
                .swiftLanguageMode(.v5)
            ]
        ),
        // Universal Test Suite (UTS)
        // A standalone Swift Testing suite (import Testing / @Suite) derived from the language-neutral
        // specs in the `ably/specification` repo (uts/). Deliberately does not depend on Nimble or XCTest.
        .testTarget(
            name: "UTS",
            dependencies: [
                .byName(name: "Ably"),
                .target(name: "AblyPubSubDevice"),
                .target(name: "_AblyPluginSupportPrivate"),
                // The `objects` UTS module tests the LiveObjects plugin's public API.
                .target(name: "AblyLiveObjects"),
                // Shared LiveObjects test helpers/mocks + internal-access seams,
                // used by the objects UTS ports.
                .target(name: "AblyLiveObjectsTesting"),
                // Shared provisioning-retry helper (Helpers/ProvisioningRetry.swift).
                .byName(name: "AblyTesting"),
            ],
            path: "Test/UTS",
            exclude: [
                "README.md",
                "deviations.md"
            ],
            swiftSettings: [
                // Build the UTS suite in the Swift 6 language mode (strict concurrency checking) so the
                // compiler catches data races in the harness/tests. Only affects this test target (not
                // the shipped product).
                .swiftLanguageMode(.v6)
            ]
        ),
        // A soak test: many realtime clients driven against faked HTTP, WebSocket and
        // reachability implementations for twenty minutes. It is skipped unless
        // RUN_SOAK_TEST is set in the environment, so `swift test` and CI never spend that
        // time on it. See Test/AblySoakTests/SoakTest.swift.
        .testTarget(
            name: "AblySoakTests",
            dependencies: [
                .byName(name: "Ably"),
            ],
            path: "Test/AblySoakTests",
            swiftSettings: [
                // This test code predates the Swift 6 language mode.
                .swiftLanguageMode(.v5)
            ]
        ),
        // A handful of tests written in Objective-C (they can't be part of AblyTests because SPM doesn't allow mixed-language targets).
        .testTarget(
            name: "AblyTestsObjC",
            dependencies: [
                .byName(name: "Ably"),
                .target(name: "AblyPubSubDevice"),
                .byName(name: "AblyTesting"),
                .byName(name: "AblyTestingObjC"),
            ],
            path: "Test/AblyTestsObjC"
        ),
        // Provides test helpers used by both AblyTests and AblyTestsObjC.
        .target(
            name: "AblyTesting",
            dependencies: [
                .byName(name: "Ably"),
            ],
            path: "Test/AblyTesting",
            swiftSettings: [
                // This test code predates the Swift 6 language mode.
                .swiftLanguageMode(.v5)
            ]
        ),
        // Provides test helpers written in Objective-C (they can't be part of AblyTests because SPM doesn't allow mixed-language targets).
        .target(
            name: "AblyTestingObjC",
            path: "Test/AblyTestingObjC",
            cSettings: [
                .headerSearchPath("Dependencies/steipete"),
            ]
        )
    ]
)

