# AblyLiveObjectsTesting

A test-support module for the `AblyLiveObjects` plugin. It exists so that the
production sources in `LiveObjects/Sources/AblyLiveObjects` do **not** have to
host test-only plumbing.

## Purpose

`AblyLiveObjectsTests` needs to read and poke internal state of the LiveObjects
implementation types. Historically that was done with `testsOnly_`-prefixed
members declared directly in `Sources/`. This module is the new home for that
plumbing: it hosts `@testable import AblyLiveObjects` extensions that expose the
internal state the tests need, keeping the shipped sources clean.

It is a **regular** SPM target (not a test target) so that the test target can
consume it via `@testable import AblyLiveObjectsTesting`. SPM discovers sources
recursively, so the two-directory split below needs no `Package.swift` change.
It is **not** a member
of any product, so it is unreachable from — and never built by — consumers of
the shipped `AblyLiveObjects` library (verified: debug and release consumer
builds are unaffected). SwiftPM enables testability for it automatically in
debug builds; the release CI job is deliberately scoped to
`--target AblyLiveObjects` so it never builds this debug-only tooling (for an
in-package build, `--product` does not provide that scoping — `--target` does).

## Directory layout

The module's files are split into two subdirectories by role. `AblyLiveObjectsTesting.swift`
(the umbrella/doc file) and this `README.md` stay at the module root.

- **`Internals/`** — internal-access seam files, one per type, named
  `<Type>+TestsOnly.swift`. Each is an `@testable import AblyLiveObjects` extension that
  exposes internal members/state of an `AblyLiveObjects` (or core) type as `testsOnly_`
  accessors. `PublicDefaultRealtimeObject+TestsOnly.swift` lives here too: although it
  extends a *public* type, it reaches the type's **internal** `proxied` / `coreSDK`
  members via `@testable`, so it is an internal-access seam, not public-API convenience.
- **`Helpers/`** — mocks, factories, loggers, and assertion utilities that build on the
  public/testable surface: `Assertions.swift`, `MockCoreSDK.swift`,
  `MockLiveMapObjectsPoolDelegate.swift`, `MockRealtimeObjects.swift`,
  `MockSimpleClock.swift`, `Subscriber.swift`, `TestFactories.swift`, `TestLogger.swift`,
  and `StandardTestPool.swift` (the shared-module mirror of the UTS spec helper
  `uts/objects/helpers/standard_test_pool.md`: the serial/siteCode vocabulary plus the shared
  `SyncObjectsPool` and spec-pool operation-message builders used by both
  `AblyLiveObjectsTests` and the UTS objects tier).

**Classification rule:** a file goes in `Internals/` if it is a `<Type>+TestsOnly.swift`
extension whose purpose is to expose internal members via `@testable` access; everything
else (mocks, factories, loggers, assertions) goes in `Helpers/`.

## Linting

This module lives under `Test/` and is **EditorConfig-linted only** (LF line
endings, trailing-newline, no trailing whitespace — `make lint`), like the rest
of the `Test/` tree (`AblyTests`, `AblyTesting`, `UTS`). It is deliberately
**outside** the LiveObjects `BuildTool lint` (SwiftFormat/SwiftLint) scope: that
tooling runs from `LiveObjects/` and its config discovery + relative `excluded`
paths are cwd-anchored there, so covering a sibling `Test/` directory would be a
fragile cross-directory config hack rather than a clean one-line extension. The
files here still satisfy the SwiftFormat/SwiftLint style they were authored under
(they were moved verbatim from `LiveObjects/Tests/`), but that style is no longer
enforced by CI for this directory.

## Hard review rule — dumb accessors only

A helper in this module may **only**:

- read or write **existing** internal state of an `AblyLiveObjects` type
  (including the mechanical `mutex.withSync { … }` hop to reach mutex-guarded
  state), or
- delegate 1:1 to an **existing** internal method.

A helper may **not** contain:

- new computation,
- decision logic, or
- state of its own.

Mechanical, shape-preserving constructs do **not** count as logic and are fine:

- enum-case `switch` / `if case` pattern matches that read existing state or
  delegate per-case 1:1 (e.g. projecting a sync-state enum to a Bool, or
  dispatching an `ObjectsPool.Entry` to its per-case accessor),
- element-wise `for` forwarding of a collection to an existing internal method,
- `withCheckedContinuation` bridging of an existing callback API.

Logic in a test helper is itself untested code. This rule is enforced in review:
if a helper needs to do anything more than a pass-through, the logic belongs in
`Sources/` (properly tested) or the requirement needs a lead-dev decision — do
not smuggle it into this module.

### Lead-approved exceptions to the dumb-accessor rule

Helpers in this module that exceed the dumb-accessor rule, each individually
approved with the reason recorded here. Do not add to this list without a
lead-dev decision.

| Helper | What exceeds the rule | Why it is accepted |
| ------ | --------------------- | ------------------ |
| `InternalDefaultRealtimeObjects.testsOnly_publish` | Sequences validation and publish with its own error propagation (`do`/`catch` + early return inside a continuation). | It composes two production pieces unchanged — the RTO15d validator (`ensureMessageSizeWithinLimit`, made `internal` for this seam) and `CoreSDK.nosync_publish` — and exists so tests can send an OBJECT ProtocolMessage *without* the RTO20 apply-on-ACK stage of `nosync_publishAndApply`. Its callers (the wire-size RTO15d tests and the plugin round-trip test) must not trigger local apply; routing through the production publish path would change their semantics, and extracting a shared validate-then-publish production method is library surface growth deferred to a dedicated change. |

## Residual allowlist

A small number of `testsOnly_` seams physically cannot move into this module
(e.g. stored `AsyncStream` instrumentation that production code writes, or
protocol requirements that a foreign module cannot add). Those stay in
`Sources/` with a marker comment. The authoritative list of what is allowed to
remain in `Sources/`, with the reason each is immovable, is the six members
below. Line numbers drift; the guardrail (`Scripts/check-liveobjects-test-seams.sh`)
matches on **file + member name**, not line, and fails CI if `Sources/` grows any
`testsOnly_` declaration outside this list (or if a listed member disappears).

| Member                                             | File:line (approx.)                                 | Why it cannot move                                                                                                                                                                     |
| -------------------------------------------------- | --------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `testsOnly_overridePublish` (protocol requirement) | `Internal/CoreSDK.swift:19`                         | A requirement cannot be added to a protocol from another module, so the `CoreSDK` protocol must declare it itself.                                                                     |
| `testsOnly_overridePublish` (impl)                 | `Internal/CoreSDK.swift:122`                        | Stores the override closure in `DefaultCoreSDK`'s own state, which production `nosync_publish` reads — an extension cannot host stored state.                                          |
| `testsOnly_waitingForSyncEvents`                   | `Internal/InternalDefaultRealtimeObjects.swift:82`  | Exposes a stored `AsyncStream` whose continuation production code writes; an extension cannot host the backing stored state.                                                           |
| `testsOnly_receivedObjectProtocolMessages`         | `Internal/InternalDefaultRealtimeObjects.swift:517` | Exposes a stored `AsyncStream` whose continuation production `OBJECT` handling writes; backing stored state cannot live in an extension.                                               |
| `testsOnly_receivedObjectSyncProtocolMessages`     | `Internal/InternalDefaultRealtimeObjects.swift:536` | Exposes a stored `AsyncStream` whose continuation production `OBJECT_SYNC` handling writes; backing stored state cannot live in an extension.                                          |
| `testsOnly_finishAllTestHelperStreams`             | `Internal/InternalDefaultRealtimeObjects.swift:767` | Finishes the instrumentation stream continuations that are stored on the class (including the completed-GC stream, which has no accessor); it must live where that stored state lives. |

### Sanctioned non-seams

These are **not** `testsOnly_` seams and are deliberately left in `Sources/`.
They read as test-adjacent but are legitimate production surface, so they are
neither moved nor guarded:

| Symbol                                                                            | File:line                                          | Why it is fine to keep                                                                                                                                                              |
| --------------------------------------------------------------------------------- | -------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ARTClientOptions.garbageCollectionOptions`                                       | `Internal/ARTClientOptions+Objects.swift:17`       | A real configuration knob for the RTO10 garbage collector; tests set it, but it is production config surface, not a state-poking seam.                                              |
| `GarbageCollectionOptions.GracePeriod.fixed`                                      | `Internal/InternalDefaultRealtimeObjects.swift:63` | A production config case (a grace period that ignores the server's `objectsGCGracePeriod`); happens to be used mainly by tests but is a legitimate option.                          |
| `nosync_mergeInitialValue` (counter)                                              | `Internal/InternalDefaultLiveCounter.swift:201`    | Carries spec-mandated create-operation merge logic (RTLO). Test-only-called today but expected to gain production callers; the dumb-accessor rule forbids moving logic into a test helper, so it stays. |
| `nosync_mergeInitialValue` (map)                                                  | `Internal/InternalDefaultLiveMap.swift:258`        | Same as above — spec-mandated merge logic that must stay in tested production code.                                                                                                 |
| `nosync_applySyncObjectsPool`'s `pathObjectSubscriptionRegister: … = nil` default | `Internal/ObjectsPool.swift:362`                   | A test-convenience default on a production method; the parameter itself is production, only its default is test-oriented. Optional later cleanup, out of scope here.                |
| `Plugin.defaultPluginAPI`                                                         | `Public/Plugin.swift:42`                           | A production dependency-injection seam (lets tests substitute the plugin API); a DI abstraction, not test plumbing.                                                                 |
| `InternalRealtimeObjectsProtocol`                                                 | `Internal/InternalDefaultRealtimeObjects.swift:6`  | A production abstraction over `InternalDefaultRealtimeObjects` "for testability" (mockability); a DI point, not a `testsOnly_` seam.                                                |

## How to add a helper

1. One file per LiveObjects type, named `<Type>+TestsOnly.swift` (e.g.
   `InternalDefaultLiveCounter+TestsOnly.swift`), placed in `Internals/`.
2. `@testable import AblyLiveObjects` at the top of the file.
3. Declare an `extension <Type>` and add the accessor as a `testsOnly_`-prefixed
   member (keep the prefix verbatim — it matches the existing 700+ test call
   sites).
4. Obey the dumb-accessor rule above. If the backing member you need is
   `private`, raise it to `internal` in `Sources/` with a
   `// internal for AblyLiveObjectsTesting` intent comment. If more
   than a visibility raise is required (stored state, production write hooks),
   **stop and escalate** — that is a residual-class seam, not a helper.
