# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

ably-cocoa is the Ably pub/sub SDK for iOS, macOS, and tvOS. It is written in Objective-C with a public Objective-C API that is also consumed from Swift. It implements the [Ably client library specification](https://github.com/ably/specification).

**ably-cocoa is device-side only**: it serves apps running on an end user's device. Per [PDR-091](https://ably.atlassian.net/wiki/spaces/product/pages/5220106242), such a client declares that to Ably, which is what determines how its traffic counts toward an account's monthly active users. The decision records cover all nine Pub/Sub SDKs and describe a device/server pair, but the server half belongs to the server-capable SDKs; do not add a server package, a server factory, or the `ably-pubsub-server` agent identifier here, and do not document this SDK as a choice between two sides. Server-side Swift is tracked separately as `ably-swift`.

The SPM products are **`AblyPubSubDevice`** (what applications depend on: `PubSubDevice.createClient(options:)`, which declares the device runtime), **`AblyPubSubCore`** (the core SDK, an internal implementation product for Ably's own packages rather than for direct use by applications) and `AblyLiveObjects`. The core's **module is `Ably` and its class prefix is `ART`**, independently of the product name — do not rename ObjC symbols, headers or the module.

## Build and Test

```bash
# First-time setup: pull ably-common submodule (tests will crash without this)
git submodule update --init --recursive

# Build
swift build

# Run a single test class
swift test --filter AuthTests

# Run all tests (slow — includes integration tests that hit the Ably sandbox)
swift test
```

When verifying changes, escalate incrementally:

1. `swift build` — catch compilation errors in the SDK itself.
2. `swift build --build-tests` — catch compilation errors in test code too.
3. `swift test --filter <TestClass>` — run targeted tests for the area you changed.
4. `swift test` — full suite. Only run if explicitly asked; some tests hit the Ably sandbox and are slow.

## Specification

This SDK implements the Ably client library specification. Spec points are identified like `REC2a`. If you are given a task that requires knowledge of the spec, you must consult it before proceeding — never guess its contents. If you haven't been told where to find a local copy, ask. If the specification is unclear, mention this.

## Linting

EditorConfig compliance only (no SwiftLint/SwiftFormat):

```bash
# Requires: brew install editorconfig-checker
make lint
```

## Source Code Architecture

All SDK source is in `Source/`, written entirely in Objective-C:

- `Source/include/Ably/` — Public headers. Umbrella headers: `AblyPublic.h` (general use) and `AblyInternal.h` (for Ably-authored SDKs only).
- `Source/PrivateHeaders/Ably/` — Internal headers.
- `Source/*.m` — Implementations.
- `Source/SocketRocket/` — Vendored WebSocket implementation.
- `Source/Ably.modulemap` — Module map defining public/private module interfaces.

Key classes follow the `ART` prefix convention: `ARTRealtime`, `ARTRest`, `ARTAuth`, `ARTChannel`, `ARTConnection`, `ARTPresence`, `ARTPush`.

### Plugin System

Plugins are passed via `ARTClientOptions.plugins`. Plugin support is gated behind `#ifdef ABLY_SUPPORTS_PLUGINS` (enabled only in SPM builds). See `Docs/plugins.md`.

## LiveObjects

The LiveObjects plugin (the `AblyLiveObjects` product, in Swift) lives in `LiveObjects/`, which has its own CLAUDE.md with build/test/lint instructions; consult it when working on LiveObjects code. Its targets are declared in this repo's root `Package.swift`, and every top-level declaration in its sources must carry an `@available` annotation (enforced by `Scripts/annotate-liveobjects-availability.py`; see that script for details).

## Test Structure

- `Test/AblyTests/Tests/` — Swift test files.
- `Test/AblyTestsObjC/` — Objective-C tests (separate target because SPM doesn't allow mixed-language targets).
- `Test/AblyTesting/` — Shared Swift test helpers.
- `Test/AblyTestingObjC/` — Shared Objective-C test helpers.
- `Test/UTS/` — the Universal Test Suite target (tests derived from the cross-SDK UTS specs; the LiveObjects objects unit tier lives at `Test/UTS/unit/objects/`).
- `Test/AblyLiveObjectsTesting/` — LiveObjects test-support target (`testsOnly_` internal-access extensions plus shared test helpers/mocks; consumed via `@testable import` by both `AblyLiveObjectsTests` and `UTS`, never shipped).

## Adding New Files

Do **not** edit `Ably.xcodeproj/project.pbxproj` — ask the user to add files to the Xcode project manually. SPM discovers source files automatically, so `swift build` and `swift test` will work without Xcode project changes.

When adding new Objective-C files:

- **Public headers** go in `Source/include/Ably/` and must be imported in the appropriate umbrella header (`AblyPublic.h` or `AblyInternal.h`).
- **Private headers** go in `Source/PrivateHeaders/Ably/` and must be declared in both module map files (`Source/Ably.modulemap` and `Source/include/module.modulemap`).
- **Implementation files** go in `Source/`.

## Coding Standards

- Use `art_dispatch_sync` and `art_dispatch_async` instead of `dispatch_sync` and `dispatch_async`, for safer handling of `nil` queues.
- EditorConfig rules: UTF-8, LF line endings, trim trailing whitespace, final newline.

## Distribution

The SDK is distributed via CocoaPods, Carthage, and Swift Package Manager. Changes to dependencies must be kept in sync across `Cartfile`, `Ably.podspec`, and `Package.swift`.
