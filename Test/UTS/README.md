# UTS in ably-cocoa — A Human-Readable Guide

> A practical, end-to-end explanation of the **Universal Test Specification (UTS)** and how it is
> realised in the `ably-cocoa` repository. Written for a developer who has never touched UTS before
> and needs to understand *what it is*, *why it exists*, and *exactly how the Swift code under
> `Test/UTS/` makes the unit tests work* — and what is still to be built.
>
> This guide mirrors the structure of the equivalent document in `ably-java` (`uts/README.md`); the
> directory layout here is kept **in sync with the Kotlin `uts` module** so a developer can move
> between the two SDKs without re-learning the map.

---

## Table of Contents

1. [Introduction: What is UTS?](#1-introduction-what-is-uts)
2. [The Three Test Tiers](#2-the-three-test-tiers)
3. [The UTS Documents (the source of truth)](#3-the-uts-documents-the-source-of-truth)
4. [The Cocoa Setup: the `UTS` target](#4-the-cocoa-setup-the-uts-target)
5. [How a Test Reaches the SDK: the hook points](#5-how-a-test-reaches-the-sdk-the-hook-points)
6. [Unit-Test Infrastructure (mocked transports)](#6-unit-test-infrastructure-mocked-transports)
7. [Walkthrough: the Realtime Unit Test (`ConnectionRecoveryTests`)](#7-walkthrough-the-realtime-unit-test-connectionrecoverytests)
8. [Walkthrough: the REST Unit Test (`TimeTests`)](#8-walkthrough-the-rest-unit-test-timetests)
9. [Deviations: when the SDK disagrees with the spec](#9-deviations-when-the-sdk-disagrees-with-the-spec)
10. [How to Run the Tests](#10-how-to-run-the-tests)
11. [Integration & Proxy Infrastructure](#11-integration--proxy-infrastructure)
12. [Quick Reference / Cheat-Sheet](#12-quick-reference--cheat-sheet)
13. [Appendix: Per-File API Reference](#13-appendix-per-file-api-reference)

---

## 1. Introduction: What is UTS?

**UTS (Universal Test Specification)** is Ably's language-neutral catalogue of tests for its client
SDKs. Ably ships many SDKs (JavaScript, Dart, Kotlin/Java, Swift, Go, …), and every one of them must
obey the *same* behavioural contract — the **Ably features spec**
(`specification/specifications/features.md`, whose requirements are tagged `RSC16`, `RTN16g`,
`RTL4f`, etc.). Without a shared test definition, each SDK would re-invent its own tests, drift
apart, and leave gaps.

UTS fixes this by separating **what to test** from **how to test it in a given language**:

```text
        ┌──────────────────────────────┐
        │   Ably features spec          │   ← the ultimate authority (RSC*, RTN*, RTL* …)
        │   (features.md)               │
        └──────────────┬───────────────┘
                       │ distilled into portable test specs
                       ▼
        ┌──────────────────────────────┐
        │   UTS test specs (.md)        │   ← language-neutral pseudocode, one file per feature
        │                               │     e.g. realtime/unit/connection/connection_recovery_test.md
        └──────────────┬───────────────┘
                       │ translated ("derived") per SDK
                       ▼
        ┌──────────────────────────────┐
        │   Derived tests               │   ← concrete, runnable tests in the SDK's language
        │   (this repo: Swift in       │     e.g. ConnectionRecoveryTests.swift
        │    Test/UTS/)                 │
        └──────────────────────────────┘
```

Four concepts you will see constantly:

| Term | Meaning |
|------|---------|
| **Spec point** | A tagged requirement in the features spec, e.g. `RTN16g`, `RSC16`. Test names embed these. |
| **UTS spec** | A markdown file of portable pseudocode describing the setup, steps, and assertions for one feature. The *source of truth for what to test.* |
| **Derived test** | A faithful translation of a UTS spec into a real test in a specific SDK/language. This is what lives in `Test/UTS/`. |
| **Deviation** | A documented case where the SDK's actual behaviour diverges from the spec. Recorded in `deviations.md`. |

The golden rule (from
[`writing-derived-tests.md`](https://github.com/ably/specification/blob/main/uts/docs/writing-derived-tests.md)):
**translate the UTS spec faithfully** — same structure, same assertions, same naming — don't
optimise or skip steps. Every derived test carries a `// UTS: <id>` comment immediately above the
test method, linking it back to its spec (e.g. `// UTS: realtime/unit/RTN16g/recovery-key-structure-0`).

---

## 2. The Three Test Tiers

UTS divides tests into three tiers by *what infrastructure they need* and *what confidence they give*:

| Tier | Transport | Backend | Purpose | Example in this repo |
|------|-----------|---------|---------|----------------------|
| **Unit** | **Mocked** (`MockWebSocket`, `MockHTTPClient`) | none | Client-side logic: state machines, request formation, response parsing, timer behaviour. Fast & deterministic. | `unit/realtime/ConnectionRecoveryTests.swift` |
| **Direct sandbox integration** | Real network | Real Ably sandbox | Happy-path interop: connect, publish, subscribe. No fault injection. | `integration/standard/realtime/ChannelHistoryTests.swift` (§11.4) |
| **Proxy integration** | Real network **through a programmable proxy** | Real Ably sandbox | Fault behaviour: dropped connections, injected errors, timeouts, re-auth. | `integration/proxy/realtime/AuthReauthTests.swift` (§11.5) |

Each tier folder is organised **by module** (`realtime`, `rest`, …), so a feature's tests sit
together by SDK area — e.g. `unit/realtime/ConnectionRecoveryTests.swift`.

Key principles (from
[`integration-testing.md`](https://github.com/ably/specification/blob/main/uts/docs/integration-testing.md)):

- **Integration tests do not replace unit tests.** A spec point covered by a proxy test should
  *also* have a unit test. The unit test proves the client logic; the proxy test proves the client
  and the real server agree.
- **Proxy tests prefer "late fault injection".** Let the real handshake complete against the real
  server, *then* inject the fault as the final interaction.
- **Proxy tests always use JSON** (`useBinaryProtocol = false`) — the proxy can only inspect text
  WebSocket frames, not binary msgpack. (The cocoa unit infra *also* forces JSON, so its mock can
  decode the frames the SDK sends.) **Direct-sandbox tests**, by contrast, run once per protocol
  variant — JSON *and* msgpack — via `@Test(arguments: [false, true])` over `useBinaryProtocol`.

---

## 3. The UTS Documents (the source of truth)

These documents live in the **specification repo** at
[`uts/docs/`](https://github.com/ably/specification/blob/main/uts/docs/). They are the
policy/authoring guides; the Swift code in this directory is the *implementation* of what they
describe:

- [`writing-test-specs.md`](https://github.com/ably/specification/blob/main/uts/docs/writing-test-specs.md)
  — how to author a portable UTS spec: test types, **test IDs**
  (`<category>/<spec-point>/<descriptive-name>-<n>`), the mock pseudocode interfaces
  (`MockWebSocket`, `MockHttpClient`, `PendingConnection`, `PendingRequest`), WebSocket closing
  semantics (`send_to_client_and_close` for DISCONNECTED / connection-level ERROR vs
  `send_to_client` for channel-level ERROR), and anti-flake conventions (no fixed waits — use
  `AWAIT_STATE`, polling, and fake timers).
- [`writing-derived-tests.md`](https://github.com/ably/specification/blob/main/uts/docs/writing-derived-tests.md)
  — how to translate a spec into a real SDK test, and the **decision tree** when a translated test
  fails: spec wrong → fix the spec at source + a fail-fast test + record a UTS spec error;
  translation wrong → fix the test; SDK non-compliant → gate the spec-correct assertion behind
  `RUN_DEVIATIONS` and record a **deviation** (§9).
- [`integration-testing.md`](https://github.com/ably/specification/blob/main/uts/docs/integration-testing.md)
  — the policy for the two integration tiers (directory layout, sandbox provisioning, proxy session
  lifecycle, late fault injection). Implemented by the §11 infrastructure.
- [`completion-status.md`](https://github.com/ably/specification/blob/main/uts/docs/completion-status.md)
  — the coverage matrix mapping every features-spec group to its UTS specs; the tracker for what's
  done and what's missing.

> There is also a fifth, *referenced* spec:
> [`docs/proxy.md`](https://github.com/ably/specification/blob/main/uts/docs/proxy.md)
> — it defines the proxy's control API, rule format, action types, and the **protocol message
> action-number table** (CONNECTED=4, ATTACH=10, AUTH=17, …). `ProxySession` (§11.3) is the Swift
> client for exactly that API.

The specs currently derived here:

- `RTN16` (connection recovery) → unit spec
  [`connection_recovery_test.md`](https://github.com/ably/specification/blob/main/uts/realtime/unit/connection/connection_recovery_test.md)
  → **`unit/realtime/ConnectionRecoveryTests.swift`**.
- `RSC16` (server time) → unit spec
  [`time.md`](https://github.com/ably/specification/blob/main/uts/rest/unit/time.md)
  → **`unit/rest/TimeTests.swift`**.
- `RTL10d` (channel history) → integration spec
  [`channel_history_test.md`](https://github.com/ably/specification/blob/main/uts/realtime/integration/channel_history_test.md)
  → **`integration/standard/realtime/ChannelHistoryTests.swift`**.
- `RSA9`/`RSA9a`/`RSA9g` (token request) → integration spec
  [`token_request_test.md`](https://github.com/ably/specification/blob/main/uts/realtime/integration/auth/token_request_test.md)
  → **`integration/standard/realtime/TokenRequestTests.swift`**.
- `RTN22`/`RTC8a` (server-initiated re-auth) → proxy spec
  [`auth_reauth.md`](https://github.com/ably/specification/blob/main/uts/realtime/integration/proxy/auth_reauth.md)
  → **`integration/proxy/realtime/AuthReauthTests.swift`**.

---

## 4. The Cocoa Setup: the `UTS` target

`Test/UTS/` is a **standalone SPM test target** (`UTS` in `Package.swift`), separate from the main
`AblyTests` suite. Its distinguishing choices:

- **Swift Testing, not XCTest/Nimble.** Suites are `@Suite(.serialized) final class … : UTSTestCase`
  and tests are `@Test func …`. Swift Testing creates a **fresh suite instance per `@Test`**, so
  each test gets its own clients/mocks and `deinit` is the per-test teardown.
- **Swift 6 language mode** (strict concurrency checking), applied via the
  `-swift-version 6` compiler flag in `Package.swift` — the compiler itself catches data races in
  the infra and tests. This is why the infra has types like `Captured` (§6.6) instead of plain
  captured arrays.
- **`import Ably.Private`** — the SDK is Objective-C; its internal API is exposed to tests through
  the `explicit module Private` block in `Source/include/module.modulemap`. This is how the infra
  reaches the injection seams in §5.
- **SPM-only.** The target is not part of `Ably.xcodeproj`; SPM discovers the sources automatically,
  so adding a test file requires no project-file changes.

### Directory layout

The layout is deliberately **in sync with `ably-java`'s Kotlin `uts` module**
(`uts/src/test/kotlin/io/ably/lib/uts/`): **infrastructure** under `infra/` (no `@Test`s), tests
organised **by tier, then by module**.

```text
Test/UTS/
├── README.md                            # this guide
├── deviations.md                        # the catalogue of SDK-vs-spec divergences
│
├── infra/                               # ── TEST INFRASTRUCTURE (no @Test methods) ──
│   ├── Utils.swift                      #   shared helpers: async pollUntil / awaitState /
│   │                                    #   awaitChannelState + HTTP support (≈ Kotlin's infra/Utils.kt)
│   │
│   ├── unit/                            #   UNIT infra (mocked transports)
│   │   ├── UTSTestCase.swift            #     base case: installMock, makeRealtime/makeRest,
│   │   │                                #     awaitConnectionState/awaitChannelState/poll, advanceTime
│   │   │                                #     (≈ Kotlin's infra/unit/ClientFactories.kt)
│   │   ├── MockWebSocket.swift          #     MockWebSocketProvider + MockWebSocket + the two factories
│   │   ├── MockHTTPClient.swift         #     fake ARTHTTPExecutor + PendingHTTPConnection/Request
│   │   ├── MockTimeProvider.swift       #     virtual clock + virtual timers (deterministic time)
│   │   ├── ProtocolMessage.swift        #     Sendable server-message factories (.connected/.attached/…)
│   │   ├── Captured.swift               #     thread-safe captured_* collector (Swift 6 safe)
│   │   ├── CapturingLog.swift           #     ARTLog recording log lines for assertions
│   │   └── NoOpReachability.swift       #     disables OS network monitoring in unit tests
│   │
│   └── integration/                     #   INTEGRATION infra (real backend) — see §11
│       ├── IntegrationTestCase.swift    #     base case for direct-sandbox suites: withSandboxApp /
│       │                                #     withRealtimeClient scoped setup + always-run teardown
│       ├── SandboxApp.swift             #     provisions/deletes a sandbox app
│       └── proxy/                       #     (macOS-only — spawns a local process)
│           ├── ProxyTestCase.swift      #       base case for proxy suites: withProxySession +
│           │                            #       token-auth proxyClientOptions
│           ├── ProxyManager.swift       #       syncs (downloads/caches) + launches the uts-proxy binary
│           └── ProxySession.swift       #       proxy session: rules, actions, log + connectThroughProxy
│
├── unit/                                # ── UNIT TESTS (mock transport) ── · per module
│   ├── realtime/
│   │   └── ConnectionRecoveryTests.swift#   RTN16* (mocked WS, fake timers)
│   └── rest/
│       └── TimeTests.swift              #   RSC16 (mocked HTTP)
│
└── integration/                         # ── INTEGRATION TESTS (real backend) ── · per module
    ├── standard/                        #   direct sandbox: happy-path, no fault injection
    │   └── realtime/
    │       ├── ChannelHistoryTests.swift#   RTL10d (cross-client history, JSON + msgpack) — §11.4
    │       └── TokenRequestTests.swift  #   RSA9/RSA9a/RSA9g (server-accepted TokenRequest)
    └── proxy/                           #   sandbox through the fault-injecting uts-proxy
        └── realtime/
            └── AuthReauthTests.swift    #   RTN22/RTC8a (injected AUTH → re-auth) — §11.5
```

The mental model (same as ably-java): **`infra/unit/` powers the unit tests, `infra/integration/`
powers both integration kinds (`standard` + `proxy`), and `infra/Utils.swift` serves all of
them.** One deliberate difference from Kotlin: cocoa's `UTSTestCase` (in `infra/unit/`, like
Kotlin's `infra/unit/ClientFactories.kt`) also carries the unit tier's synchronous `AWAIT_STATE`
helpers, while the shared `infra/Utils.swift` provides the async `pollUntil` / `awaitState` /
`awaitChannelState` the integration tier uses for real-network waits (Kotlin keeps all of these
together in `infra/Utils.kt`).

---

## 5. How a Test Reaches the SDK: the hook points

A test can only mock transports because the SDK exposes **pluggable seams** on
`ARTClientOptions.testOptions` (an `ARTTestClientOptions`, reachable via `import Ably.Private` —
the cocoa analogue of ably-java's `DebugOptions`):

| Seam | Type | Mock installed there |
|------|------|----------------------|
| `testOptions.transportFactory` | `RealtimeTransportFactory` | `MockWebSocketTransportFactory` (→ `MockWebSocket`) |
| `testOptions.httpExecutor` | `ARTHTTPExecutor` | `MockHTTPClient` |
| `testOptions.timeProvider` | `ARTTimeProvider` | `MockTimeProvider` |
| `testOptions.reachabilityClass` | `ARTReachability` class | `NoOpReachability` |
| `options.logHandler` | `ARTLog` | `CapturingLog` (when a test asserts on log output) |

So the recipe is:

- Want to fake the **WebSocket**? Set `transportFactory` — note this still builds a **real**
  `ARTWebSocketTransport`, so URL and query-param construction (`recover`, `resume`, `format`, …)
  is exercised by production code; only the socket underneath is faked, through the
  `ARTWebSocketFactory` seam.
- Want to fake **HTTP**? Set `httpExecutor` — every REST request the SDK makes flows through it.
- Want to control **time** (timeouts, retries, TTL expiry) deterministically? Set `timeProvider` —
  every SDK timer is created through `scheduleAfter:queue:block:` on it.
- Want to stop the OS **network monitor** from interfering? Set `reachabilityClass`.

Tests never touch `testOptions` directly — `UTSTestCase.makeRealtime()`/`makeRest()` wire all of
this (§6.1).

**Reaching further internals.** `import Ably.Private` exposes exactly the private headers listed in
the `explicit module Private` block of `Source/include/module.modulemap` — anything declared only
in a `.m` file (class extensions, ivars, private methods) is invisible to Swift. The SDK being
Objective-C also means Swift access levels (`internal`/`package`) play no part. When a new test
needs an internal symbol that isn't exposed yet, the `uts-to-swift` skill (Step 4, "Accessing SDK
internals") carries the decision list: check the private headers, extend them (registering in both
module maps), or record the gap in `deviations.md`.

---

## 6. Unit-Test Infrastructure (mocked transports)

### 6.1 The base case — `infra/unit/UTSTestCase.swift`

Every UTS suite subclasses `UTSTestCase`. It provides the cocoa mappings of the UTS infra
primitives:

| UTS pseudocode | `UTSTestCase` API |
|---|---|
| `install_mock(mock_ws)` / `install_mock(mock_http)` | `installMock(_:)` — registers the mock; the **next** `makeRealtime()` / `makeRest()` picks it up. The mock is never passed to the client constructor (a mistake per `writing-test-specs.md`). |
| client construction | `makeRealtime { options in … }` / `makeRest { options in … }` — seeds a dummy key (`appId.keyId:keySecret`, like ably-java's `ClientOptionsBuilder`; the configure block can override it), forces JSON (`useBinaryProtocol = false`), gives each client its own internal/callback dispatch queues, and wires every installed mock into `testOptions`. `makeRealtime` *requires* a `MockWebSocketProvider`; it also wires an installed `MockHTTPClient` into the client's REST layer (auth callbacks, fallback hosts, …). |
| `AWAIT_STATE conn.state == s` | `awaitConnectionState(client, .connected)` — proceeds immediately if the condition already holds, otherwise polls until it does or the timeout (default 2 s) expires, then records a failure. |
| `AWAIT_STATE channel.state == s` | `awaitChannelState(channel, .attached)` |
| generic awaiting (e.g. "a frame has been sent") | `poll("description") { condition }` |
| `enable_fake_timers()` | `enableFakeTimers()` — clients built *after* this call use the `MockTimeProvider`, a **hard gate** per the spec's `mock_websocket.md` §Fake-time semantics (nothing timer-driven fires until `advanceTime`); by default they run on the real clock (mirroring the spec, where only timeout/retry tests opt into fake timers). |
| `ADVANCE_TIME(ms)` | `advanceTime(byMilliseconds:)` |
| `CLOSE_CLIENT` | `closeClient(_:)` |

Teardown is `deinit` (Swift Testing releases the suite instance after each `@Test`): it closes all
clients created by `makeRealtime` and calls `timeProvider?.cancelAllScheduled()` — the
**timer-leak safety net** the derived-tests guide asks for.

### 6.2 `MockWebSocket.swift` — the fake realtime transport

Three cooperating types:

- **`MockWebSocketProvider`** — the UTS `mock_ws`, the object the *test* holds. It outlives any
  single socket (the SDK creates a new `MockWebSocket` per connection attempt), carries the
  `onConnectionAttempt` handler, and exposes `activeConnection` (the UTS `active_connection` — the
  most recent attempt). Tests that need the full history capture sockets into a `Captured` inside
  `onConnectionAttempt`.
- **`MockWebSocket`** — a single simulated connection. It conforms to `ARTWebSocket` so the real
  `ARTWebSocketTransport` can drive it, and exposes the UTS **server-side API** to tests:

  | Method | What it does | Use for |
  |--------|--------------|---------|
  | `respondWithSuccess()` | accepts the connection (`readyState = .open`, fires `webSocketDidOpen`) | the transport-level accept; follow with `sendToClient(.connected(…))` |
  | `respondWithSuccess(_:)` | accept + deliver a message in one call | the common accept-then-CONNECTED pair, e.g. `respondWithSuccess(.connectedMessage)` |
  | `sendToClient(_:)` | delivers a protocol message, connection stays open | CONNECTED, ATTACHED, channel-level ERROR, ACK, normal messages |
  | `sendToClientAndClose(_:)` | delivers a message then closes (code 1000) | DISCONNECTED, connection-level (fatal) ERROR |
  | `respondWithRefused()` | closes with code 1003, no message | retryable connection refusal (`realtimeTransportRefused:`) |
  | `simulateDisconnect()` | closes with code 1001, no message | unexpected network drop → DISCONNECTED/resume |

  For **inspection** it exposes `request` / `url` / `queryParams` (the real production-built URL —
  this is how `recover=`/`resume=` assertions work) and `sentMessages` (every protocol message the
  SDK sent towards the "server", decoded, in order — the client→server `ws_frame` log).
- **`MockWebSocketFactory` / `MockWebSocketTransportFactory`** — the adapters. The transport factory
  is what `makeRealtime` installs; it builds a real `ARTWebSocketTransport` backed by a
  `MockWebSocketFactory`, which creates `MockWebSocket`s, registers them with the provider, and
  fires `onConnectionAttempt` on the client's work queue (timed so the transport has already wired
  `delegate` and `delegateDispatchQueue`).

All simulated server activity is delivered on the transport's `delegateDispatchQueue`, matching the
real `ARTSRWebSocket` contract.

> The cocoa UTS infra currently implements the **handler style** (`onConnectionAttempt` closure) from
> the spec. The await style (`await_connection_attempt()`), which ably-java also implements, hasn't
> been needed yet — add it when a spec requires different answers for first connection vs
> reconnection attempts that a handler can't express.

### 6.3 `MockHTTPClient.swift` — the fake REST transport

A fake `ARTHTTPExecutor` mirroring the spec's `mock_http.md`. The cocoa HTTP seam is
**request-level** (`execute(_:completion:)`), so each request is a standalone two-phase attempt:

1. **Connection phase** — `onConnectionAttempt` receives a `PendingHTTPConnection` (`host`, `port`,
   `tls`, `queryParams`, derived from the request URL) and returns the connection verdict:
   `respondWithSuccess()` (nil error — proceed), `respondWithRefused()`, `respondWithTimeout()`, or
   `respondWithDNSError()` (the corresponding `NSURLErrorDomain` errors).
2. **Request phase** — unless the connection failed, `onRequest` receives a `PendingHTTPRequest`
   exposing `url`, `method`, `headers`, `body`, `queryParams`, and the response API:
   `respondWith(status:body:headers:)` (body may be `Data`, `String`, or a JSON-serialisable value;
   defaults to a JSON content type), `respondWithDelay(_:status:body:)` (same, delivered after a
   delay — for slow-server specs), or `respondWithTimeout()`.

This lets REST unit tests assert on outgoing request shape (path, headers, query) and feed canned
responses back — all without a socket.

### 6.4 `MockTimeProvider.swift` — deterministic time

A deterministic `ARTTimeProvider`: both the wall clock and the continuous clock start at a fixed
origin (the wall-clock origin is overridable via `init(initialWallClockMilliseconds:)`, java's
`FakeClock(initialTimeMs)`) and **only move when the test calls `advanceTime(byMilliseconds:)`** —
nothing fires on its own. Every block the SDK schedules through `scheduleAfter:queue:block:` is
recorded.

`advanceTime` does more than bump a counter — it runs the SDK to quiescence:

1. **Drains** the SDK's queues first, so already-queued work finishes *registering its timer*
   before the clock moves past it.
2. Advances both clocks.
3. **Fires every now-due block** (in fire-time order) and drains the cascade it triggers, repeating
   while the cascade schedules further blocks that are themselves already due.

After it returns, the SDK has fully reacted to the elapsed time. Chained retries scheduled
*relative to the new time* remain in the future and need a subsequent `advanceTime` — matching real
elapsed time. `pendingScheduledCount` exposes how many blocks are currently scheduled — useful for
asserting retry state (the counterpart of ably-java's `FakeClock.pendingTaskCount`; cocoa timers
have no names, so it is a single overall count). `cancelAllScheduled()` is the teardown safety
net (§6.1).

### 6.5 `ProtocolMessage.swift` — server-message factories

A `Sendable` value type describing a server→client message, built lazily into a real
`ARTProtocolMessage` at delivery time (on the delegate queue). Factories:
`.connected(connectionId:connectionKey:maxIdleInterval:connectionStateTtl:)` (defaults: TTL 120 s,
max-idle 15 s), `.attached(channel:channelSerial:)`, `.error(code:statusCode:message:)`,
`.ack(msgSerial:count:)`, `.closed()`. Extend this enum as new specs need more actions.

`.connectedMessage` is a ready-to-use default CONNECTED message (ably-java's `CONNECTED_MESSAGE`:
connectionId `test-connection-id`, key `test-connection-key`) so most tests don't hand-build one —
and being a value type, each use is inherently a fresh instance.

### 6.6 `Captured.swift` — the spec's `captured_*` arrays, Swift 6-safe

Mock handlers run on SDK queues while the test reads results on the test thread; a plain captured
`var array` is a data race the Swift 6 compiler **rejects**. `Captured<Element>` is a small
lock-guarded, `Sendable` collector (`append`, `all`, `count`, `first`, subscript) that lets a test
keep a *local* collector — the spec's pattern — while staying race-free.

### 6.7 `CapturingLog.swift` — asserting on log output

An `ARTLog` that records every message the SDK logs (regardless of `logLevel`, and keeping the
console quiet). Install via `options.logHandler`; assert with
`contains(level: .error, message: "substring")`. Used by specs like RTN16f1 ("an error is logged").

### 6.8 `NoOpReachability.swift`

A reachability implementation that never reports network changes, installed via
`testOptions.reachabilityClass` so the SDK doesn't start OS-level network monitoring during a unit
test (which must not touch the real network).

### 6.9 Where each ably-java helper lives in cocoa

For a developer coming from the Kotlin `uts` module — the java helpers' capabilities are provided
here, though some map onto a different shape (and a few, such as client-close observability, are
exposed through dedicated accessors rather than the timeline):

| ably-java helper | cocoa equivalent |
|---|---|
| `infra/Utils.kt` (`awaitState`, `awaitChannelState`, `pollUntil`) | `infra/Utils.swift` (`awaitState`, `awaitChannelState`, `pollUntil` — async, for the integration tier) + the synchronous `UTSTestCase` awaits for the unit tier |
| `infra/Utils.kt` `withRealTimeout` | Not needed — Swift Testing has no virtual-time scheduler for `withTimeout` to be fooled by |
| `unit/ClientFactories.kt` (seeds the dummy key) | `UTSTestCase.makeRealtime` / `makeRest` (seed the same dummy key) |
| JUnit suite lifecycle (`@BeforeAll` / `@AfterAll` in integration suites) | Swift Testing has no setUp/tearDown and `deinit` can't `await` — integration suites subclass `IntegrationTestCase` / `ProxyTestCase`, whose scoped `with…` methods own setup + always-run teardown (§11) |
| `unit/MockWebSocket.kt` + `MockWebSocketEngineFactory.kt` | `MockWebSocket.swift` (provider + socket + the two factories) |
| `unit/MockHttpClient.kt` + `MockHttpEngine.kt` + `PendingConnection/Request` (+ `Default*`) | `MockHTTPClient.swift` (`MockHTTPClient`, `PendingHTTPConnection`, `PendingHTTPRequest`) — cocoa's HTTP seam is one protocol, so no engine/adapter split |
| `unit/MockEvent.kt` (typed event timeline) | `MockWebSocket.sentMessages` (client→server frames) + `Captured` collectors in `onConnectionAttempt` for most events; client-initiated close is observed via `MockWebSocket.awaitClientClose(timeout:)` / `clientClose` (recorded inside the mock's own `close`, since the transport nils its delegate before closing), not `sentMessages` |
| await-style mocking (`awaitConnectionAttempt()`, …) and the per-frame handlers (`onMessageFromClient`, `onText/BinaryDataFrame`) | Handler style + a counter in `onConnectionAttempt`, and `sentMessages` polling (see §6.2's note; add these when a spec needs what they can't express) |
| `CONNECTED_MESSAGE` | `ProtocolMessage.connectedMessage` |
| `parseQueryString` | `parseQueryParams(of:)` in `infra/Utils.swift` |
| `unit/FakeClock.kt` (`advance`, `pendingTaskCount`, `initialTimeMs`) | `MockTimeProvider` (`advanceTime(byMilliseconds:)`, `pendingScheduledCount`, `init(initialWallClockMilliseconds:)`) |
| `unit/Utils.kt` (`ConnectionDetails { }` reflective builder) | `ProtocolMessage.connected(…)` builds `ARTConnectionDetails` directly — `import Ably.Private` exposes the initialiser, no reflection needed |
| `integration/SandboxApp.kt`, `integration/proxy/ProxyManager.kt` / `ProxySession.kt` | Same names, same shape — `infra/integration/` (§11) |

### 6.10 How the pieces connect (request flow, no network)

A unit test installs the mock transport into `testOptions`; the SDK believes it is talking to a
real socket, while every byte is intercepted in-process and surfaced to the test:

```text
  ┌──────────────────────── TEST (Swift Testing suite : UTSTestCase) ────────────────────────┐
  │                                                                                          │
  │  installMock(wsProvider);  let client = makeRealtime { $0.autoConnect = false }          │
  │       │ client.connect()                        ▲ awaitConnectionState(client, .connected)│
  │       ▼                                         │                                         │
  │  ┌─────────────────────────────┐  testOptions.transportFactory                            │
  │  │ ARTRealtime + the REAL       │ ────────▶ MockWebSocketTransportFactory                 │
  │  │ ARTWebSocketTransport        │                   │ creates one per connection attempt  │
  │  └──────────┬──────────────────┘                    ▼                                     │
  │             │ send(frame) ─────────────▶ ┌────────────────────┐                           │
  │   didReceiveMessage ◀────────────────────│    MockWebSocket    │◀── wsProvider            │
  │             ▲                            │ • sentMessages      │    .activeConnection     │
  │             │                            │ • queryParams       │    (the test's handle)   │
  │             │                            └────────────────────┘                           │
  │   TEST drives the "server" side:               TEST inspects:                             │
  │     connection.respondWithSuccess(.connectedMessage)   ws.queryParams (recover/resume…)   │
  │     connection.sendToClient(.attached(…))              ws.sentMessages (ATTACH, ACK…)     │
  │     connection.sendToClientAndClose(…) / .simulateDisconnect()                            │
  │                                                                                          │
  │   MockTimeProvider (testOptions.timeProvider):                                            │
  │     enableFakeTimers() + advanceTime(byMilliseconds:) — fires due timers, settles cascades │
  └──────────────────────────────────────────────────────────────────────────────────────────┘

  No TCP, no DNS, no real time. Everything is in-process and deterministic.
```

(The HTTP path is identical in shape: `MockHTTPClient` → `testOptions.httpExecutor` →
`PendingHTTPConnection` then `PendingHTTPRequest`, with `respondWith(status:body:)`.
The integration-tier counterpart of this picture — real network through the proxy — is §11.6.)

---

## 7. Walkthrough: the Realtime Unit Test (`ConnectionRecoveryTests`)

**File:** `unit/realtime/ConnectionRecoveryTests.swift`
**Tier:** Unit (mocked WebSocket, no network).
**Spec area:** RTN16 — connection recovery via the `recover` option and `createRecoveryKey()`.
**Spec:** [`connection_recovery_test.md`](https://github.com/ably/specification/blob/main/uts/realtime/unit/connection/connection_recovery_test.md)

Six tests, each carrying a `// UTS: realtime/unit/RTN16…/…` tag:

### 7.1 `RTN16g, RTN16g1` — recovery-key structure (incl. Unicode)

Connects (the `onConnectionAttempt` handler responds with success + CONNECTED carrying a known
key), attaches two channels — one ASCII, one Unicode (`channel-éàü-世界`) — feeding each an
ATTACHED with a `channelSerial` via `sendToClient`. Asserts `createRecoveryKey()` contains the
connection key, `msgSerial == 0`, and both channel serials — including an encode→decode
round-trip proving the Unicode name survives.

### 7.2 `RTN16g2` — `createRecoveryKey()` returns nil in inactive states

Walks the connection through INITIALIZED → CONNECTED → CLOSING/CLOSED → FAILED → SUSPENDED
asserting nil in every inactive state. The SUSPENDED leg uses `enableFakeTimers()` +
`advanceTime` to expire the connection-state TTL deterministically — no real sleeping.

### 7.3 `RTN16k` — `recover` adds the `recover` query param

Builds the client with `options.recover = <key>` and asserts via `MockWebSocket.queryParams`
(real production URL building) that the first attempt carries `recover=` and a post-disconnect
reconnect switches to `resume=` — recover is a one-shot bootstrap.

### 7.4 `RTN16f` — `recover` initialises `msgSerial` from the recovery key

Verified through an ACK round-trip (`.ack(msgSerial:count:)`).

### 7.5 `RTN16f1` — malformed `recover` key degrades gracefully

A garbage key must be logged (asserted via `CapturingLog`) and ignored: the client connects
normally, with no `recover`/`resume` params.

### 7.6 `RTN16j` — `recover` instantiates channels with their serials (RTN16i too)

Not auto-attached; a manual `attach()` sends an ATTACH frame carrying the recovered serial
(verified via `sentMessages`).

**What this file teaches about the infra:** the handler-style mock, `sendToClient` vs a real close,
fake-timer-driven SUSPENDED, `queryParams`/`sentMessages` as the two inspection surfaces, and
`CapturingLog` assertions.

---

## 8. Walkthrough: the REST Unit Test (`TimeTests`)

**File:** `unit/rest/TimeTests.swift`
**Tier:** Unit (mocked HTTP, no network).
**Spec area:** RSC16 — `ARTRest.time()`.

Five tests (`// UTS: rest/unit/RSC16/…`): the returned `Date` matches the server's millisecond
timestamp; the request is a `GET /time` (asserted via `PendingHTTPRequest.url`/`method`); no
authentication is required; it works without TLS; and an error response (`respondWith(status: 500,
…)`) propagates as an error. Each test builds a `MockHTTPClient` with the two handlers and a
`makeRest` client — the minimal REST-unit-test shape to copy for new REST specs.

---

## 9. Deviations: when the SDK disagrees with the spec

`deviations.md` (next to this file) is the single catalogue of every place ably-cocoa behaves
differently from the features spec, discovered during translation. The mechanism (from
`writing-derived-tests.md`): the test keeps the **spec-correct** assertion but gates it behind the
`RUN_DEVIATIONS` environment variable, so normal runs stay green while each deviation stays
individually reproducible:

```swift
@Test(.enabled(if: ProcessInfo.processInfo.environment["RUN_DEVIATIONS"] != nil))
```

```bash
RUN_DEVIATIONS=1 swift test --filter UTS.<TestClass>/<testMethod>
```

No deviations are recorded yet. When one is found, follow the decision tree (§3,
`writing-derived-tests.md`) and record: the spec point, what the spec requires, what the SDK does,
the root cause (file/function, where known), the workaround in the test, and the affected tests.
Deviations are **valuable output**, not failures — each one is a precise, reproducible bug report,
and the gated test becomes the acceptance test for the fix.

---

## 10. How to Run the Tests

There is **no env-var gating** — every suite (unit, integration, proxy) runs directly from
`swift test` or the Xcode test runner UI, just like ably-java's Gradle tasks. Pick the tier by
**which suites you run**: unit suites are sub-second and fully mocked; integration/proxy suites
hit the real Ably sandbox (and the proxy suites additionally sync + spawn the local `uts-proxy`,
macOS-only — on iOS/tvOS destinations they compile to nothing, §11.2).

```bash
# The whole UTS target — unit AND integration tiers (integration needs network; proxy needs macOS):
swift test --filter UTS

# Unit suites only (fast, fully mocked, no network):
swift test --filter "UTS.ConnectionRecoveryTests|UTS.TimeTests"

# One suite / one test:
swift test --filter UTS.ConnectionRecoveryTests
swift test --filter UTS.ConnectionRecoveryTests/test_RTN16k_recover_option_adds_recover_query_param_to_WebSocket_URL

# Turn on the spec-correct (currently failing) deviation assertions:
RUN_DEVIATIONS=1 swift test --filter UTS.<TestClass>/<testMethod>

# Spec-derived integration & proxy suites (real sandbox; AuthReauthTests is macOS-only):
swift test --filter UTS.ChannelHistoryTests
swift test --filter UTS.AuthReauthTests

# Run the proxy tier against a locally built uts-proxy instead of a GitHub release
# (a config override, not a gate):
UTS_PROXY_LOCAL_PATH=/path/to/uts-proxy swift test --filter UTS.AuthReauthTests
```

**Where CI runs them:** there is currently **no UTS-specific CI job** — the UTS target runs as part
of the full test suite (the `ably-cocoa` scheme driven by the fastlane lanes in
`.github/workflows/integration-test.yaml`, which already has sandbox network access). A dedicated
fast PR-gate step running just the unit suites (e.g. in `check-spm.yaml`, mirroring ably-java's
`runUtsUnitTests` gate in its `check.yml`) is a cheap improvement worth making — the
unit/integration split now runs on suite selection rather than env vars, so the lanes only need
different `--filter` lists (ably-java splits the same way with `runUtsUnitTests` /
`runUtsIntegrationTests`).

Notes:
- `ProxyManager` **advises** running proxy suites from one test process at a time — they share the
  control port (10100), see §11.2.
- Proxy/sandbox tests need outbound network (sandbox + GitHub releases on first run; the binary is
  then cached under `~/.cache/uts-proxy/`).

---

## 11. Integration & Proxy Infrastructure

The `infra/integration/` layer mirrors ably-java's `infra/integration/` (see its `uts/README.md`
§7 for the reference design) and is exercised end-to-end by the spec-derived tests (§10):
`integration/standard/realtime/ChannelHistoryTests.swift` (SandboxApp + real TLS clients, no
proxy; run once per protocol variant — JSON + msgpack) and
`integration/proxy/realtime/AuthReauthTests.swift` (the full proxy chain, fault injection
included). Three components (§11.1–11.3), the base test cases that own setup/teardown (below),
then a walkthrough of each tier's reference test (§11.4–11.5) and the request-flow picture
(§11.6).

**The base test cases.** Swift Testing has no `setUp()`/`tearDown()` hooks and `deinit` cannot
`await`, so integration suites subclass a base case whose **scoped-resource methods** own the
lifecycle — provision, run your body, and *always* tear down (rethrowing any error after cleanup,
so failures stay attributed and nothing is orphaned):

| Base class | Subclass it for | Scoped methods |
|---|---|---|
| `IntegrationTestCase` | direct-sandbox suites | `withSandboxApp { app in … }` (create → body → `delete()`), `withRealtimeClient(options) { client in … }` (build → body → `close()` + await CLOSED) |
| `ProxyTestCase` (: `IntegrationTestCase`, macOS-only) | proxy suites | `withProxySession(rules:) { app, session in … }` (`ensureProxy` + app + session → body → `session.close()` + app delete), plus `proxyClientOptions(for:through:)` (token-auth options wired through the proxy) |

Components:

### 11.1 `SandboxApp.swift` — a throwaway app on the real sandbox

Provisions a real backend app **directly** (not through the proxy, so provisioning is independent
of any fault rules under test): fetches the canonical `test-app-setup.json` from ably-common,
`POST`s its `post_apps` body to `https://sandbox.realtime.ably-nonprod.net/apps` (both are
retried with backoff via `AblyTesting`'s `withProvisioningRetries` — retrying the POST is safe
because an orphaned app from a timed-out create is auto-deleted by the sandbox), and exposes `appId`,
`defaultKey` (full-capability `appId.keyId:keySecret`), and the full `keys` list. `delete()`
removes the app in teardown (best-effort — cleanup must never mask a test failure). Owns the single
upstream host constant `SandboxApp.sandboxHost` — the `nonprod:sandbox` endpoint used uniformly
across the integration specs; both `ProxySession` targets and direct-sandbox clients point at it.

`SandboxApp` is the shared backbone of *both* integration kinds: **proxy** tests pair it with a
`ProxySession`, while **direct sandbox** tests use it alone — connecting straight to
`SandboxApp.sandboxHost` over TLS, where plain key (basic) auth works;
`integration/standard/realtime/ChannelHistoryTests.swift` is the reference shape.

### 11.2 `proxy/ProxyManager.swift` — syncs and launches the proxy binary

The proxy is a small Go program — [`ably/uts-proxy`](https://github.com/ably/uts-proxy) — that
forwards traffic to the sandbox and injects faults on command. `ProxyManager` (an actor singleton)
owns the *process*:

- `try await ProxyManager.shared.ensureProxy()` (call in suite setup) is **idempotent**: if a proxy
  is already healthy on the control port (**10100**), it's a no-op. Otherwise it **downloads** the
  pinned release (`v0.3.0`) archive (`uts-proxy_<ver>_<os>_<arch>.tar.gz`) for the current arch
  from GitHub releases, **verifies its SHA-256 checksum**, extracts the binary (via the system
  `tar` — one deliberate simplification
  over ably-java's hand-rolled JDK-only tar reader), caches it under
  `~/.cache/uts-proxy/<version>/` — the **same cache ably-java uses**, so the two SDKs share one
  download — and launches it with `--port 10100`.
- The download is serialised across concurrently launched test processes by an exclusive `flock`,
  and within the process by the actor. Process *startup* relies only on the shared health check,
  so run proxy suites from **one test process at a time** (ably-java's single-fork advisory) —
  concurrent runners could race to bind the control port or reap each other's proxy.
- A spawned `Process` does **not** die with its parent, so an `atexit` reaper kills it when the
  test process exits; `stopProxy()` stops it explicitly.
- Override knob: set `UTS_PROXY_LOCAL_PATH` to a **locally built** proxy binary or `.tar.gz` to
  skip the download + checksum (for testing against an unreleased proxy). This mirrors ably-java's
  `-Duts.proxy.localPath` / `UTS_PROXY_LOCAL_PATH`; there is no separate "sync" build task in
  either SDK — the sync *is* `ensureProxy()`.
- **macOS-only**: spawning a local process needs `Foundation.Process`, which doesn't exist on
  iOS/tvOS — the `proxy/` infra and proxy suites are wrapped in `#if os(macOS)` and compile to
  nothing on the simulator platforms CI also builds.

### 11.3 `proxy/ProxySession.swift` — one test's window into the proxy

The proxy exposes a **control REST API** on port 10100; `ProxySession` is the typed Swift client
for it, per
[`docs/proxy.md`](https://github.com/ably/specification/blob/main/uts/docs/proxy.md).
One session per test:

- `ProxySession.create(rules:)` → `POST /sessions` with a `target` (the sandbox hosts) and an
  initial **rule list**; the proxy assigns a `sessionId` and a fresh **listening port**.
- `addRules(_:position:)` → add rules mid-test (`POST /sessions/{id}/rules`).
- `triggerAction(_:)` → fire an **imperative** action right now (`POST /sessions/{id}/actions`) —
  late fault injection, e.g. `["type": "inject_to_client", "message": ["action": 17]]`.
- `getLog()` → `GET /sessions/{id}/log`, returning the session's ordered, typed `[ProxyEvent]` —
  each carries `type` (`ws_connect`, `ws_frame`, `http_request`, …), `direction`, `queryParams`,
  and the parsed protocol `message` (introspect via `message?["action"] as? Int`). Proxy-log
  assertions are a proxy test's primary verification.
- `close()` → `DELETE /sessions/{id}` — always call it in teardown.

**Rules** = `match` + `action` (+ optional `times`), built with `wsConnectRule` /
`wsFrameToClientRule` / `wsFrameToServerRule` / `httpRequestRule`. Rules evaluate in order, first
match wins, unmatched traffic passes through, `times: N` auto-removes after N firings. Common
actions: `refuse_connection`, `suppress`, `replace`, `inject_to_client[_and_close]`, `disconnect`,
`http_respond`.

**Wiring a client through the proxy** — `options.connectThroughProxy(session)` sets
`realtimeHost`/`restHost` = localhost, `port` = the session's port, `tls = false`, and
`useBinaryProtocol = false` (the proxy only understands text frames). ⚠️ Because the proxy serves
plain ws, **basic (key) auth is rejected** (RSA1: basic auth is TLS-only) — authenticate through
the proxy with an `authCallback` that signs a `TokenRequest` locally using the sandbox key
(`ProxyTestCase.proxyClientOptions` packages this; `AuthReauthTests` inlines it to count the
callbacks — ably-java's `AuthReauthTest` does the same).

**The shared async helpers** both integration walkthroughs below lean on (from
`infra/Utils.swift` — java's `infra/Utils.kt`, see §6.9). All are wall-clock and poll-based
(never a fixed sleep); on timeout they record a Swift Testing `Issue` (and return `false`)
rather than throwing — though `pollUntil` re-throws an error thrown by its condition, aborting
the poll (a thrown error is a genuine failure; "not ready yet" is signalled by returning nil):

| Helper | Shape | Purpose |
|--------|-------|---------|
| `awaitState` | `await awaitState(client, .connected, timeout: 15)` | suspend until `connection.state == target` (or already there) |
| `awaitChannelState` | `await awaitChannelState(channel, .attached, timeout: 15)` | same, for a channel's state |
| `pollUntil` | `let page = await pollUntil("…") { cond ? value : nil }` or `await pollUntil("…") { condition }` | the spec's `poll_until`: the generic form returns the settled value (assert on it — a refetch can return fewer items); the Bool form is for latch/monotonic conditions with no page to keep |

### 11.4 Walkthrough: the direct-sandbox test (`ChannelHistoryTests`)

**File:** `integration/standard/realtime/ChannelHistoryTests.swift` (ably-java's
`ChannelHistoryTest.kt` is its sibling)
**Tier:** Direct-sandbox integration (real network, real Ably sandbox, **no** proxy, **no** fault
injection).
**Spec point:** RTL10d — messages published by one realtime client are retrievable from a
*separate* client's `history()`.
**Spec:** [`channel_history_test.md`](https://github.com/ably/specification/blob/main/uts/realtime/integration/channel_history_test.md)

This is the reference for the **middle tier**. Like a proxy test it talks to the real backend, but
it connects *straight* to `SandboxApp.sandboxHost` — there is no `ProxyManager`, no `ProxySession`,
and no `connectThroughProxy` wiring. It's the shape every happy-path interop spec
(connect/publish/subscribe/presence) follows.

#### 11.4.1 Suite setup/teardown

Swift Testing has no `@BeforeAll`/`@AfterAll` (§6.9), so the suite subclasses
`IntegrationTestCase` and the **scoped-resource methods** own the lifecycle — provisioning
**`SandboxApp` only**, no `ProxyManager.ensureProxy()`:

```swift
try await withSandboxApp { app in                             // SandboxApp.create() → body → app.delete()
    try await withRealtimeClient(publisherOptions) { publisher in
        try await withRealtimeClient(subscriberOptions) { subscriber in
            // … scenario …
        }                                                     // close() + await CLOSED — always
    }
}
```

#### 11.4.2 The client — wired straight to the sandbox

The options point the **real** transport at the sandbox host (no proxy in between). Setting
explicit hosts auto-disables fallback hosts (REC2c2), so there's nothing else to configure:

```swift
let publisherOptions = ARTClientOptions(key: app.defaultKey)
publisherOptions.realtimeHost = SandboxApp.sandboxHost   // sandbox.realtime.ably-nonprod.net
publisherOptions.restHost = SandboxApp.sandboxHost
publisherOptions.useBinaryProtocol = useBinaryProtocol
publisherOptions.autoConnect = false
```

(Plain `ARTClientOptions` with no `installMock` — TLS stays on, so basic key auth works here,
and the SDK drives its real `ARTWebSocketTransport` instead of a `MockWebSocket`.)

#### 11.4.3 Protocol variants — the parameterised-test pattern

The spec declares a `PROTOCOL` dimension (`json` / `msgpack`) and says *each test runs once per
variant*. Cocoa realises that with a Swift Testing **parameterised test** over
`useBinaryProtocol` (built in — no extra dependency, unlike ably-java's `junit-jupiter-params`):

```swift
// UTS: realtime/integration/RTL10d/history-cross-client-0
@Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
func test_RTL10d_history_contains_messages_published_by_another_client(useBinaryProtocol: Bool) async throws {
    …
}
```

A plain `@Test` test (no protocol dimension) stays a `@Test` — reach for `arguments:` only when
the spec actually declares variants.

#### 11.4.4 The scenario — real publish, real history

Two independent clients on the same app: the publisher's *confirmed* messages must appear in the
subscriber's history. The integration-specific techniques on show:

- **Awaiting a publish ack.** Realtime publish is fire-and-forget, so to honour the spec's
  `AWAIT publish` the test wraps the callback overload `publish(_:data:callback:)` in a
  `withCheckedContinuation` (`awaitPublish`, in the suite's extension), resuming on the callback
  and recording an `Issue` on error. This is the integration analogue of the unit test's
  `sentMessages` inspection.
- **`AWAIT attach()`** → `attach()` then `await awaitChannelState(channel, .attached, timeout: 10)`.
- **Polling real REST state.** `history()` is a callback-based REST call against the sandbox and
  the message store is eventually-consistent, so the test bridges it with a continuation
  (`historyItems`) and `await pollUntil("subscriber history contains all 3 messages", timeout: 10,
  interval: 0.5) { … == 3 }` — never a fixed sleep (the same anti-flake rule as the other tiers).
- **Order assertion.** History defaults to newest-first, so `items[0]` is `event3` … `items[2]`
  is `event1`.

**What this test teaches about the infra:** `SandboxApp`-only provisioning, the direct-sandbox
client wiring (`realtimeHost`/`restHost` from `SandboxApp.sandboxHost`, no proxy), the
protocol-variant parameterised test, awaiting a publish ack via the callback overload, and
`pollUntil` over a real `history()` call.

### 11.5 Walkthrough: the proxy test (`AuthReauthTests`)

**File:** `integration/proxy/realtime/AuthReauthTests.swift` (ably-java's `AuthReauthTest.kt` is
its sibling; macOS-only, §11.2)
**Tier:** Proxy integration (real sandbox, traffic routed through the local `uts-proxy`).
**Spec points:** RTN22 (server-initiated re-authentication) and RTC8a (the client sends an AUTH
frame with renewed auth details). Unit-tier spec counterparts:
`server_initiated_reauth_test.md`, `realtime_authorize.md`.
**Spec:** [`auth_reauth.md`](https://github.com/ably/specification/blob/main/uts/realtime/integration/proxy/auth_reauth.md)

#### 11.5.1 Suite setup/teardown

Swift Testing has no `@BeforeAll`/`@AfterAll` (§6.9), so the suite subclasses `ProxyTestCase` and
one scope owns everything the java `@BeforeAll`/`@AfterAll` pair does — ensure the proxy is
running (§11.2), provision the app **directly** against the sandbox (not through the proxy, so
provisioning is independent of any fault rules), and always close the session + delete the app:

```swift
try await withProxySession(rules: []) { app, session in
    // ensureProxy() ran, app provisioned, session created against the sandbox target
    // … scenario …
}   // session.close() + app.delete() — always, even on failure
```

#### 11.5.2 The test, step by step

1. **A session with no rules** (the `rules: []` above) — the fault will be injected
   *imperatively* later (late injection, §2 — the connect handshake runs against the real server
   unmodified). Declarative faults would use `addRules` / the rule builders instead (§11.3).
2. **Auth via `authCallback`** — the spec generates a JWT from the sandbox key; the idiomatic
   cocoa equivalent is a locally-signed `TokenRequest` from the same key (no external JWT
   library). A `Captured` counter records how many times the callback is invoked
   (`proxyClientOptions(for:through:)` packages this wiring; the test inlines it to count):

   ```swift
   let authCallbackInvocations = Captured<ARTTokenParams>()
   let signerOptions = ARTClientOptions(key: app.defaultKey)
   signerOptions.restHost = SandboxApp.sandboxHost
   let tokenSigner = ARTRest(options: signerOptions)

   let options = ARTClientOptions()
   options.authCallback = { params, callback in
       authCallbackInvocations.append(params)
       tokenSigner.auth.createTokenRequest(params, options: nil) { tokenRequest, error in
           callback(tokenRequest, error)
       }
   }
   ```
3. **Build the client through the proxy** and connect (JSON stays on so the proxy can inspect
   frames):

   ```swift
   options.connectThroughProxy(session)   // localhost + session port, tls = false, JSON
   options.autoConnect = false
   try await withRealtimeClient(options) { client in
       client.connect()
       guard await awaitState(client, .connected, timeout: 15) else { return }
       // …
   }
   ```
4. **Snapshot identity** — `connection.id` (`try #require` — later lines depend on it) and the
   callback count, and assert the callback already ran ≥ 1 (initial auth).
5. **Start recording state changes** (a `Captured` fed by `connection.on`), then **inject a
   server-initiated AUTH** (protocol action 17) imperatively — simulating Ably asking the client
   to re-authenticate:

   ```swift
   try await session.triggerAction(["type": "inject_to_client", "message": ["action": 17]])
   ```
6. **Wait for the re-auth round-trip** with `pollUntil` (real network, so poll — don't sleep):
   first on the callback count, then until the client→server AUTH frame appears in the proxy log
   (the cocoa callback returns a `TokenRequest` the SDK still exchanges for a token — a REST
   round-trip through the proxy — before it sends AUTH, a timing adaptation the test documents
   inline).
7. **Assertions** prove RTN22 + RTC8a:
   - `authCallback` was invoked **again** (count incremented) → re-auth was triggered.
   - Connection is still **CONNECTED** and `connection.id` is **unchanged** → re-auth does not
     reconnect.
   - **No** transitions away from CONNECTED were recorded.
   - The **proxy event log** contains a client→server **AUTH frame (action 17) carrying non-nil
     `auth` details** (RTC8a) — verified by filtering `session.getLog()`.
8. **Teardown is automatic** — the scopes unwind in order: client closed and awaited CLOSED,
   then `session.close()` (leaked sessions hold proxy listeners), then `app.delete()` — even when
   the scenario failed or threw.

**What this test teaches about the infra:** `ProxyTestCase`'s scoped setup/teardown
(`ensureProxy` + `SandboxApp` + session), `connectThroughProxy` with token auth, **late
imperative fault injection** via `triggerAction`, real-network waiting with `pollUntil`, and
**proxy-log assertions** as the primary verification (`getLog()` → filter by
`type`/`direction`/`message?["action"]`).

### 11.6 How the pieces connect (request flow)

```text
  ┌───────────────────── TEST (Swift Testing) ─────────────────────┐
  │ setup: try await ProxyManager.shared.ensureProxy()             │    syncs binary, launches proxy,
  │        let app  = try await SandboxApp.create() ────────────────────── POST /apps ──────────┐
  │ let session = try await ProxySession.create(rules: []) ──┐     │    control REST :10100     │ (direct, TLS)
  │ options.connectThroughProxy(session)                     │     │                            │
  └──────────────┬────────────────────────────────────────────┼─────┘                            │
                 │ client.connect()                           │                                  │
                 │ (host=localhost, port=session.proxyPort,   │                                  │
                 │  tls=false, JSON)                          │                                  ▼
                 ▼                                            │
        ┌──────────────────┐    ws/http (plain)    ┌──────────┴───────────┐    ws/http (TLS)   ┌───────────────────────────┐
        │   ARTRealtime     │ ◀──────────────────▶ │       uts-proxy       │ ◀───────────────▶ │   Ably sandbox             │
        │  (REAL transport) │      data plane      │  • forwards traffic   │                   │   sandbox.realtime.        │
        └──────────────────┘                       │  • applies rules      │                   │   ably-nonprod.net         │
                 ▲                                 │  • records event log  │                   └───────────────────────────┘
                 │  TEST controls the proxy:       └──────────┬───────────┘
                 │    session.triggerAction(["type": "inject_to_client", "message": ["action": 17]])
                 │    session.addRules([…])                   │ control plane (REST :10100)
                 │  TEST verifies via:                        │
                 │    session.getLog() — filter type / direction / message?["action"]
                 │    await awaitState(…) / await pollUntil("…") { … }
                 └── everything before the injected fault is REAL client ↔ server traffic
```

**Why two channels to the proxy?** The **data plane** (the SDK's ws/http traffic on
`session.proxyPort`) is separate from the **control plane** (the test's REST calls on the control
port 10100 to create sessions, add rules, trigger actions, read the log). The SDK never sees the
control plane; the test never speaks the data plane directly. A direct-sandbox test (§11.4) is
this same picture with the proxy column removed — the client talks TLS straight to the sandbox,
and the test's only side channel is `SandboxApp` provisioning.

### 11.7 What remains TODO

The first spec-derived tests for both tiers now exist (`ChannelHistoryTests`,
`TokenRequestTests`, `AuthReauthTests`). What's left:

- **More spec coverage** — translate the remaining `uts/<module>/integration/` and
  `…/integration/proxy/` specs into `integration/standard/<module>/` and
  `integration/proxy/<module>/` (via the `uts-to-swift` skill; §11.4–11.5 are the reference
  shapes).
- **CI wiring** — a dedicated job/lane for the integration tier (macOS, network access), separate
  from the fast unit gate (§10).

Design constraints to carry over: late fault injection, JSON-only through the proxy, poll — never
sleep — on real-network state (`pollUntil`), and every proxy test also keeping a unit-tier
counterpart.

---

## 12. Quick Reference / Cheat-Sheet

**The seams that make unit tests possible** (`ARTClientOptions.testOptions`, via
`import Ably.Private`): `transportFactory` (WS) · `httpExecutor` (HTTP) · `timeProvider` (time) ·
`reachabilityClass` (network monitor) — plus `options.logHandler` (log assertions).

**Build a unit-test client:**
```swift
let wsProvider = MockWebSocketProvider(onConnectionAttempt: { $0.respondWithSuccess(.connectedMessage) })
installMock(wsProvider)
let client = makeRealtime { $0.autoConnect = false }
client.connect()
awaitConnectionState(client, .connected)
```

**Build a proxy-test client:**
```swift
try await withProxySession(rules: []) { app, session in       // ensureProxy + SandboxApp + session
    let options = proxyClientOptions(for: app, through: session)  // token auth + proxy wiring
    options.autoConnect = false
    try await withRealtimeClient(options) { client in /* … */ }
}
```

**Writing a new test?** This guide documents the *existing* setup — the actionable authoring
material (file templates for every tier, pseudocode→Swift translation tables, deviation patterns)
lives in the `uts-to-swift` skill (`.claude/skills/uts-to-swift/SKILL.md`), which carries out UTS
spec translation and evaluation. The reference tests to crib from are listed in §13.

**Server→client (mock WS):** `sendToClient` (stays open — ATTACHED, channel ERROR, ACK) ·
`sendToClientAndClose` (DISCONNECTED / fatal ERROR) · `respondWithRefused` (1003 refusal) ·
`simulateDisconnect` (1001 drop).

**Inspect what the SDK did:** `mockWebSocket.queryParams` / `.sentMessages` (WS) ·
`PendingHTTPRequest.url/method/headers/body/queryParams` (HTTP) · `CapturingLog.contains(…)` (logs) ·
`session.getLog()` (proxy).

**Wait (never sleep):** unit tier — `awaitConnectionState` · `awaitChannelState` ·
`poll("…") { … }` · `enableFakeTimers()` + `advanceTime(byMilliseconds:)`; integration tier
(async, wall-clock) — `await awaitState(client, .connected)` · `await awaitChannelState(…)` ·
`await pollUntil("…") { … }`.

**Protocol action numbers** (used in proxy rules & log assertions): CONNECTED=4,
DISCONNECTED=6, ERROR=9, ATTACH=10, ATTACHED=11, DETACH=12, DETACHED=13, **AUTH=17**.

**Test ID format:** `<category>/<spec-point>/<descriptive-name>-<n>` →
`// UTS: realtime/proxy/RTN22/server-initiated-reauth-0`.

**The decision tree when a translated test fails:** spec wrong → fix the spec at source + a
fail-fast test + record under *UTS Spec Errors*; translation wrong → fix the test; SDK
non-compliant → gate the spec-correct assertion behind `RUN_DEVIATIONS` and record in
`deviations.md`.

**Test ID format:** `<category>/<spec-point>/<descriptive-name>-<n>` →
`// UTS: realtime/unit/RTN16g/recovery-key-structure-0` (comment immediately above each test).


---

## 13. Appendix: Per-File API Reference

### Infrastructure — `infra/` (shared)

| File | Key public surface | Role |
|------|--------------------|------|
| `infra/Utils.swift` | `pollUntil`, `awaitState`, `awaitChannelState` (async, wall-clock); `parseQueryParams`; `httpRequest`, `jsonRequest`, `makeURLSession`, `HTTPError` | Shared helpers: the integration tier's wall-clock waits (never sleep), the query-param parsing both mocks use, and the `URLSession` plumbing the integration infra is built on. |

### Infrastructure — `infra/unit/`

| File | Key public surface | Role |
|------|--------------------|------|
| `infra/unit/UTSTestCase.swift` | `installMock(_:)` ×2, `makeRealtime { }`, `makeRest { }`, `awaitConnectionState`, `awaitChannelState`, `poll`, `enableFakeTimers`, `advanceTime(byMilliseconds:)`, `closeClient`, `defaultAwaitTimeout` (2 s) | Base class for every UTS suite; seeds the dummy key; wires all seams; `deinit` closes clients + cancels leaked timers. |
| `infra/unit/MockWebSocket.swift` | `MockWebSocketProvider` (`onConnectionAttempt`, `activeConnection`); `MockWebSocket` (`respondWithSuccess`/`respondWithSuccess(_:)`, `sendToClient`, `sendToClientAndClose`, `respondWithRefused`, `simulateDisconnect`, `request`/`url`/`queryParams`, `sentMessages`); `MockWebSocketFactory`; `MockWebSocketTransportFactory` | Fake realtime transport (handler style). Real `ARTWebSocketTransport` on top → production URL building exercised. Close codes: 1000 closed / 1001 disconnected / 1003 refused. |
| `infra/unit/MockHTTPClient.swift` | `MockHTTPClient(onConnectionAttempt:onRequest:)`; `PendingHTTPConnection` (`host`/`port`/`tls`/`queryParams`, `respondWithSuccess/Refused/Timeout/DNSError`); `PendingHTTPRequest` (`url`, `method`, `headers`, `body`, `queryParams`, `respondWith(status:body:headers:)`, `respondWithDelay(_:status:body:)`, `respondWithTimeout`) | Fake REST transport (`ARTHTTPExecutor`); two-phase connect→request per call. |
| `infra/unit/MockTimeProvider.swift` | `init(initialWallClockMilliseconds:)`, `advanceTime(byMilliseconds:)`, `pendingScheduledCount`, `cancelAllScheduled()`; implements `wallClockNow`, `continuousClockNow`, `schedule(after:queue:block:)` | Virtual clocks + recorded timers; `advanceTime` drains SDK queues, fires due blocks, and settles cascades. |
| `infra/unit/ProtocolMessage.swift` | `.connected(…)`, `.attached(…)`, `.error(…)`, `.ack(…)`, `.closed()`; `.connectedMessage` (default CONNECTED); `makeProtocolMessage()` | `Sendable` server→client message descriptions, materialised at delivery time. |
| `infra/unit/Captured.swift` | `append`, `all`, `count`, `first`, subscript | Thread-safe local collector for the spec's `captured_*` pattern (Swift 6 race-free). |
| `infra/unit/CapturingLog.swift` | `entries`, `contains(level:message:)` | `ARTLog` recording everything regardless of `logLevel`; install via `options.logHandler`. |
| `infra/unit/NoOpReachability.swift` | (`ARTReachability` conformance) | Never reports network changes; keeps OS monitoring out of unit tests. |

### Infrastructure — `infra/integration/`

| File | Key public surface | Role |
|------|--------------------|------|
| `infra/integration/IntegrationTestCase.swift` | `withSandboxApp { }`, `withRealtimeClient(_:) { }`; `runThenCleanUp(_:body:cleanup:)` (the scoped-resource engine subclasses build new scopes on) | Base case for direct-sandbox suites: scoped setup + always-run async teardown (rethrows the body's error after cleanup). |
| `infra/integration/proxy/ProxyTestCase.swift` | `withProxySession(rules:) { }`, `proxyClientOptions(for:through:)` | Base case for proxy suites (extends `IntegrationTestCase`): ensureProxy + app + session lifecycle; token-auth options wired through the proxy. **macOS-only**. |
| `infra/integration/SandboxApp.swift` | `SandboxApp.create()`, `delete()`, `appId`, `defaultKey`, `keys`; `SandboxApp.sandboxHost` | Provisions/tears down a throwaway sandbox app from ably-common's `test-app-setup.json`; owns the upstream sandbox host constant. |
| `infra/integration/proxy/ProxyManager.swift` | `ProxyManager.shared.ensureProxy(timeout:)`, `stopProxy()`, `ProxyManager.controlPort` (10100); `UTS_PROXY_LOCAL_PATH` override | Syncs (downloads, checksum-verifies, caches at `~/.cache/uts-proxy/<version>/`) and launches the pinned `uts-proxy` release; `atexit` reaper. **macOS-only** (`#if os(macOS)`). |
| `infra/integration/proxy/ProxySession.swift` | `ProxySession.create(rules:port:timeoutMs:realtimeHost:restHost:)`, `addRules`, `triggerAction`, `getLog() -> [ProxyEvent]`, `close`, `sessionId`, `proxyPort`, `proxyHost`; `ProxyEvent`; `ProxyRule` + `wsConnectRule`/`wsFrameToClientRule`/`wsFrameToServerRule`/`httpRequestRule`; `ARTClientOptions.connectThroughProxy(_:)` | Typed client for the proxy control REST API + client wiring. **macOS-only**. |

### Tests and docs

| File | Contents | Notes |
|------|----------|-------|
| `unit/realtime/ConnectionRecoveryTests.swift` | 6 `@Test`s: RTN16g/g1, RTN16g2, RTN16k, RTN16f, RTN16f1, RTN16j/i | Mocked WS + fake timers; see §7. |
| `unit/rest/TimeTests.swift` | 5 `@Test`s: RSC16 ×5 | Mocked HTTP; see §8. |
| `integration/proxy/realtime/AuthReauthTests.swift` | 1 `@Test`: RTN22/RTC8a (needs network; macOS-only) | Spec-derived proxy test (`uts/realtime/integration/proxy/auth_reauth.md`): injects a server-initiated AUTH (17), asserts re-auth via authCallback + client→server AUTH frame, connection undisturbed. Walkthrough: §11.5. |
| `integration/standard/realtime/TokenRequestTests.swift` | 2 `@Test`s: RSA9a/RSA9g, RSA9 (needs network) | Spec-derived direct-sandbox tests (`uts/realtime/integration/auth/token_request_test.md`): a locally signed TokenRequest is accepted by the server via another client's authCallback, with and without clientId. |
| `integration/standard/realtime/ChannelHistoryTests.swift` | 1 `@Test` × {JSON, msgpack}: RTL10d (needs network) | Spec-derived direct-sandbox test (`uts/realtime/integration/channel_history_test.md`): messages published by one client appear (newest-first) in another client's channel history. Walkthrough: §11.4. |
| `deviations.md` | none recorded yet | Catalogue of SDK-vs-spec divergences + the `RUN_DEVIATIONS` pattern. |

> **Coverage note:** the infrastructure is built out beyond what the current suites exercise
> (full HTTP fault verdicts, `.error`/`.closed` message factories, `CapturingLog`, all four proxy
> rule builders), anticipating the broader UTS coverage catalogued in
> [`completion-status.md`](https://github.com/ably/specification/blob/main/uts/docs/completion-status.md).
> The spec-derived integration tests are the big missing piece — see §11.7.

---

### Source map (where each fact in this doc comes from)

| Topic | File |
|-------|------|
| Authoring portable specs, test IDs, mock pseudocode | [`uts/docs/writing-test-specs.md`](https://github.com/ably/specification/blob/main/uts/docs/writing-test-specs.md) |
| Translating specs, deviation patterns, decision tree | [`uts/docs/writing-derived-tests.md`](https://github.com/ably/specification/blob/main/uts/docs/writing-derived-tests.md) |
| Integration/proxy policy, late fault injection, tiers | [`uts/docs/integration-testing.md`](https://github.com/ably/specification/blob/main/uts/docs/integration-testing.md) |
| Coverage matrix | [`uts/docs/completion-status.md`](https://github.com/ably/specification/blob/main/uts/docs/completion-status.md) |
| Proxy control API, rule format, action numbers | [`uts/docs/proxy.md`](https://github.com/ably/specification/blob/main/uts/docs/proxy.md) |
| SDK seams | `Source/PrivateHeaders/Ably/ARTClientOptions+TestConfiguration.h` (`ARTTestClientOptions`), `Source/include/module.modulemap` (`Ably.Private`) |
| Target wiring | `Package.swift` (the `UTS` test target) |
| Unit mocks | `Test/UTS/infra/unit/*` |
| Shared helpers | `Test/UTS/infra/Utils.swift` |
| Integration helpers | `Test/UTS/infra/integration/*` (+ `proxy/*`) |
| The reference tests | `unit/realtime/ConnectionRecoveryTests.swift`, `unit/rest/TimeTests.swift`, `integration/standard/realtime/ChannelHistoryTests.swift`, `integration/proxy/realtime/AuthReauthTests.swift` |
| Deviations | `Test/UTS/deviations.md` |
| The ably-java counterpart this guide mirrors | `uts/README.md` in the `ably-java` repository |
