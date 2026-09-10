---
name: uts-to-swift
description: "Translate the UTS pseudocode test specs in a whole module directory into runnable Swift tests in the ably-cocoa UTS test target. Takes a UTS module directory (e.g. <cloned-ably-specification-repo-path>/uts/objects), validates its structure, resolves the target test directories, lets you pick a tier (unit/integration/proxy) and which specs, then derives a Swift test per spec. Usage: /uts-to-swift <path-to-uts-module-directory>"
license: proprietary
allowed-tools: Bash, Read, Edit, Write, WebFetch
metadata:
  team: engineering
  version: "2.0.0"
  tags: testing, uts, swift, cocoa, ably-cocoa, test-translation
  marketplace: false
---

Translate the UTS pseudocode test specs under the **module directory** `$ARGUMENTS` into runnable Swift
tests in the ably-cocoa `UTS` test target (`Test/UTS`). Every tier lands under `Test/UTS` via the
resolver's per-module mapping. The resolver output (Step A) is always the single source of truth for where
a file goes and what it is named — never hand-compute the path or class name.

`$ARGUMENTS` is a UTS *module* directory — a directory sitting directly under the spec repo's `uts/`,
e.g. `<cloned-ably-specification-repo-path>/uts/objects`. Its name (`objects`, `realtime`,
`rest`, …) is the **source module**. A module directory holds many spec files, organised into tiers
(`unit/`, `integration/`, and `integration/proxy/`).

The work happens in two phases:

- **Phase 1 — Selection (Steps A–E below):** a bundled resolver script validates the directory and works
  out the target `Test/UTS` directories, the spec files, and their class names; you then pick a tier, pick
  which specs, and choose whether to also evaluate.
- **Phase 2 — Per-spec translation (Steps 1–7):** for each selected spec file, derive a Swift test.

## Required reading — fetch first

Always fetch [writing-derived-tests.md](https://raw.githubusercontent.com/ably/specification/refs/heads/main/uts/docs/writing-derived-tests.md) first (once per run) — don't rely on memory or the inlined summaries; the manual is updated over time.

---

# Phase 1 — Selection

Path validation, the directory mapping, spec discovery, and class-name derivation are all mechanical, so a
bundled script does them — that keeps selection byte-for-byte deterministic instead of relying on the model
to re-eyeball regexes, join paths, and hand-convert `snake_case` → `PascalCase` each run.

> **If `$ARGUMENTS` is empty or blank**, stop and show: `Usage: /uts-to-swift <path-to-uts-module-directory>`
> — with the example `/uts-to-swift <cloned-ably-specification-repo-path>/uts/objects`
> (the path to a module directory inside a local clone of
> [`ably/specification`](https://github.com/ably/specification)).

## Step A — Resolve the module

Run the resolver on the directory passed in (substitute the real path; the script path is relative to the
ably-cocoa repo root):

```bash
python3 .claude/skills/uts-to-swift/scripts/resolve_uts.py "<module-dir>"
```

It prints one JSON object. **If `ok` is `false`, relay `message` to the user and stop** — error codes:
`NOT_A_UTS_MODULE_PATH` (not a `.../uts/<module>` directory), `DIR_NOT_FOUND`, `NO_TIER_DIRS` (no `unit/`
or `integration/`). On success it gives `sourceModule`, `mapped`, `testRoot`, `translationNotes`, and a
`tiers` object with one entry per tier (`unit` / `integration` / `proxy`), each carrying `present`,
`sourceDir`, `targetDir`, and `specs` (a list of `{file, className}`). Everything downstream reads from
this output — treat it as the single source of truth and don't recompute paths or names by hand. A tier's
`targetDir` comes from the module mapping (`testRoot` + the tier entry, e.g. `Test/UTS/unit/objects`), and
a module may also declare a per-tier className suffix (so `className` isn't always `<Stem>Tests` — see
Step 2), which is exactly why you read both from here rather than assuming a `Test/UTS/...` path or a name.

`translationNotes` is the path to a per-module ably-js → ably-cocoa type/interface map when the module
declares one (its `notes` field in `uts-package-mapping.json`, e.g. `objects` →
`references/objects-mapping.md`), else `null`. When it's non-null, it is **required reading before
Phase 2** — see Step 1. (If a module's notes file only carries an "intentionally empty" placeholder
stub, tell the user the module's mapping hasn't been authored yet and treat the module as
not-yet-translatable rather than guessing a mapping.)

## Step B — Confirm or create the target mapping

The target dirs come from `uts-package-mapping.json` (alongside this skill); a spec module's name and
the SDK's internal naming for that area don't necessarily match, which is why the mapping is explicit.

- **If `mapped` is `true`**: show the resolved `targetDir` for each present tier and ask the user to confirm
  (show whatever the resolver returned verbatim).
  If they say the mapping is wrong, ask for the correct ably-cocoa module base name and re-run with `--create`
  (below) to overwrite the entry, then re-resolve.
- **If `mapped` is `false`**: there's no mapping for `sourceModule` yet. Ask for the target ably-cocoa module
  base name (default to `sourceModule`; suggest a rename only when the SDK uses different terminology), then
  create it deterministically and re-resolve:

  ```bash
  python3 .claude/skills/uts-to-swift/scripts/resolve_uts.py "<module-dir>" --create <target>
  ```

  This adds `unit/<target>`, `integration/standard/<target>`, and `integration/proxy/<target>` under
  `packages` and re-prints the resolved output. (`<target>` must be a simple module base name — letters,
  digits, underscore; the script returns `BAD_TARGET_NAME` otherwise, so just ask again.)

## Step C — Choose the tier

Offer the tiers whose `present` is `true`. The chosen tier fixes the `targetDir` and `specs` (from Step A)
**and** the translation flow Phase 2 uses — don't re-detect any of it per spec:

| Tier | Translation flow |
|---|---|
| **unit** | mocked transport — Steps 3–4 below |
| **integration** (direct sandbox) | real sandbox, no faults — **Direct-sandbox integration tests** section |
| **proxy** | real sandbox + fault injection — **Integration tests** section (proxy subsections) |

## Step D — Choose which specs to translate

The chosen tier's `specs` list (from Step A) is the candidate set — each entry already has its source `file`
and derived `className`. Present it and ask whether to translate **all** of them or a **selected subset**.
Then continue to Step E.

## Step E — Translate only, or also evaluate?

`writing-derived-tests.md` splits the work into **Translation** (always) and **Evaluation** (only
meaningful once the SDK implementation for this module exists). Ask the user which they want, and carry the
answer into Phase 2:

- **Translate only** — generate each test and make it **compile** (Steps 1–5 and the Step 7 review). Don't
  run the tests. Use this when the SDK feature isn't implemented yet, so there's nothing to run against.
- **Translate and evaluate** — all of the above **plus** running the tests and **fixing until they pass**
  (Step 6): work the decision tree, and where the SDK genuinely diverges, gate/adapt the assertion and
  record a deviation. Use this when the implementation exists.

If you can't tell whether the implementation exists, ask the user rather than guessing.

---

# Phase 2 — Per-spec translation

Run this for **each** spec file selected in Step D. **Step 6 only applies in "translate and evaluate" mode
(Step E)** — in "translate only" mode, stop after compiling (Step 5) and reviewing (Step 7), and skip
Step 6 entirely.

When translating several specs, do Steps 1–4 (generate the file) for every spec first, then run Step 5
(compile) once for the whole module, then per file run Step 6 (only if evaluating) and the Step 7 review —
compiling once is faster than per-file and surfaces cross-file issues together. For a single spec, just go
through the steps in order.

## Step 1 — Read the spec (and any module translation notes)

**If Step A reported a non-null `translationNotes`, read that file first (once per run).** UTS specs are
written in a language-agnostic pseudocode that mirrors the *ably-js* API; for modules whose ably-cocoa
types diverge, the notes map each spec symbol to its ably-cocoa equivalent. Skipping them yields tests
that read like ably-js and won't compile. A module's notes may also **override parts of the generic flow
below** — Step 3's infrastructure reading list, Step 4's `import Ably.Private` internal-access ladder,
Step 4's method-naming rule, and Step 6's deviations-file location; where the notes override, they win.
(If the notes file is still the "intentionally empty" placeholder, stop and tell the user — see Step A.)

Then read the current spec file (the one being translated from the Step D selection). Identify:
- All test cases — each has a structured ID like `realtime/unit/RSA4c2/callback-error-connecting-disconnected-0` and a description
- The protocol used (WebSocket for Realtime, HTTP for REST)
- Any timer usage (`enable_fake_timers`, `ADVANCE_TIME`)
- Any **protocol-variant dimension** — a `PROTOCOL` (`json` / `msgpack`) matrix the spec header says to run "once per variant". In swift this becomes a `useBinaryProtocol` parameterised test — `@Test(arguments: [false, true])` (see the **Direct-sandbox integration tests** section), not a plain `@Test`.

---

## Step 2 — Output path

Don't derive anything here — the resolver (Step A) already produced it. For the chosen tier use its
`targetDir`, and for the spec being translated use its `className` from that tier's `specs` list. Write the
test to `<targetDir>/<className>.swift`.

> **className.** The resolver derives `className` as `<Stem>Tests` (e.g. `internal_live_map.md` →
> `InternalLiveMapTests`). Use the resolver's `className` verbatim — it stays authoritative.
> **Add to an existing suite** when one matches: if a spec's tests fan out across more than
> one suite (e.g. `internal_live_map.md`'s parent-reference cases live in the separate
> `InternalLiveMapParentReferencesTests`), add the new methods to the existing suite rather than
> creating a duplicate (per the "add to an existing suite" rule below).

The spec's own `<sub>` grouping (e.g. `connection/`, `channels/`) is **not** reflected in the output — every
test sits directly in `targetDir` (the resolver flattens it). The chosen tier also fixes the translation
flow: **unit** → the rules in Steps 3–4 below; **integration** (direct sandbox) → the **Direct-sandbox
integration tests** section; **proxy** → the proxy subsections of the **Integration tests** section.

Each test file is a **Swift Testing** suite whose base class matches the tier:
`@Suite(.serialized) final class <className>: UTSTestCase` (unit), `… : IntegrationTestCase`
(direct sandbox), or `… : ProxyTestCase` (proxy). If a suitable suite already exists, add the new test
methods to it rather than creating a duplicate.

---

## Step 3 — Read infrastructure files

> **Orientation — read `Test/UTS/README.md` first.** It's the human-readable guide to this target: the
> tier model (unit / direct-sandbox / proxy, §2), the run commands (§10), the integration & proxy
> infrastructure (§11), and a per-file API reference for the core realtime/rest infra helpers (§13). A
> module whose translation notes override the reading list (Step 1) may fall outside that README — when
> the notes say so, follow them instead. Skim it for the *why* and the *what's available*; the per-file
> list below is the *what to open for exact signatures* before writing code.

Infrastructure is split by tier under `Test/UTS/infra/`:

- `infra/Utils.swift` — shared async helpers used by the integration tiers (`awaitState`,
  `awaitChannelState`, `pollUntil`, `parseQueryParams`).
- `infra/unit/` — unit-test base class and mocks (`UTSTestCase.swift` with the `makeRealtime`/`makeRest`
  factories and the synchronous `awaitConnectionState`/`awaitChannelState`/`poll` waits,
  `MockWebSocket.swift`, `MockHTTPClient.swift`, `MockTimeProvider.swift`, `ProtocolMessage.swift`,
  `Captured.swift`, `CapturingLog.swift`, `NoOpReachability.swift`).
- `infra/integration/` + `infra/integration/proxy/` — direct-sandbox + proxy helpers (`SandboxApp.swift`,
  `IntegrationTestCase.swift`, `ProxyManager.swift`, `ProxySession.swift`, `ProxyTestCase.swift`) — see
  the **Integration tests** section.

For a **unit** test, read ALL files under `infra/unit/` plus `infra/Utils.swift` before generating any code
(you need exact method signatures). For an **integration** or **proxy** spec, follow the reading list in
the **Integration tests** section instead. A module whose translation notes override this reading list
(Step 1) follows the notes' list instead of `infra/unit/`.

## Step 4 — Generate the Swift test file

Apply the translation rules below, then write the file.

### Accessing SDK internals (`import Ably.Private`)

> **A module's translation notes may override this ladder** (Step 1) — a module whose SDK layer isn't
> the core Objective-C SDK can specify its own internal-access mechanism instead of `import Ably.Private`;
> follow the notes where they do. The rest of this section is for the core Objective-C SDK.

The SDK is Objective-C, so Swift access levels (`internal`/`package`/`private`) don't apply to it —
visibility is controlled by **headers + the module map**:

- `import Ably` → the public API (headers in `Source/include/Ably/`).
- `import Ably.Private` → the internal API: the private headers listed in the `explicit module Private`
  block of `Source/include/module.modulemap` (files under `Source/PrivateHeaders/Ably/`, e.g.
  `ARTClientOptions+TestConfiguration.h` for `testOptions`, `ART*+Private.h` for class internals). This is
  how the UTS infra reaches the injection seams, and how a test reaches internal fields the spec asserts
  on. See `Test/UTS/README.md` §4–§5.

When a spec needs an internal class/method/field, work down this list:

1. **Check it's already exposed**: `grep -r "<symbol>" Source/PrivateHeaders/Ably/` — if it's declared in a
   listed private header, just `import Ably.Private` and use it.
2. **Declared only in a `.m` file** (class extension, ivar, private method)? It is invisible to Swift,
   period. To expose it, declare it in a header under `Source/PrivateHeaders/Ably/` and register that
   header in `Source/include/module.modulemap` — the repo's CLAUDE.md convention. Only do this for
   small, test-motivated exposure; mirror how existing `+Private.h` headers are written.
3. **Truly private state with no reasonable seam** (or exposing it would distort the SDK)? Don't hack
   around it — keep the spec's line as a comment, note why no assertion is emitted (see "Comments and
   assertion fidelity"), and record it in `deviations.md` under **Mock Infrastructure Limitations**.

### Client construction

Set `ClientOptions` fields (`key`, `autoConnect`, `recover`, `disconnectedRetryTimeout`, etc.) in the
`makeRealtime`/`makeRest` configuration block. Both factories already seed the dummy key
`appId.keyId:keySecret` (matching ably-java's `ClientOptionsBuilder`), so only set `options.key` when the
spec pseudocode sets one — then use the spec's value.

| Pseudocode | Swift |
|---|---|
| `install_mock(mock_http)` / `install_mock(mock_ws)` | `installMock(mockHTTPClient)` / `installMock(wsProvider)` — **before** `makeRealtime`/`makeRest` (the mock is injected at construction) |
| `Rest(options: ClientOptions(key: "..."))` | `let rest = makeRest { $0.key = "..." }` |
| `Realtime(options: ClientOptions(key: "...", autoConnect: false))` | `let client = makeRealtime { $0.key = "..."; $0.autoConnect = false }` |
| `Realtime(options: ClientOptions(autoConnect: false))` | `let client = makeRealtime { $0.autoConnect = false }` — no key set; the seeded dummy key applies |
| `enable_fake_timers()` | `enableFakeTimers()` — **before** `makeRealtime`/`makeRest` (the clock is injected at construction) |

### Mock setup — WebSocket

Use the **handler pattern**: configure the simulated server in `onConnectionAttempt`. As in the spec,
opening the socket and delivering the `CONNECTED` message are two separate calls —
`respond_with_success()` then `send_to_client(...)`.

Spec pseudocode:

```pseudo
mock_ws = MockWebSocket(
  onConnectionAttempt: (conn) => {
    conn.respond_with_success()
    conn.send_to_client(ProtocolMessage(
      action: CONNECTED,
      connectionId: "connection-1",
      connectionKey: "key-abc-123",
      connectionDetails: ConnectionDetails(connectionKey: "key-abc-123")
    ))
  }
)
install_mock(mock_ws)
client = Realtime(options: ClientOptions(key: "appId.keyId:keySecret", autoConnect: false))
client.connect()
AWAIT_STATE client.connection.state == ConnectionState.connected
ws_connection = mock_ws.events.find(e => e.type == CONNECTION_SUCCESS).connection
```

Swift (the UTS infra exposes `activeConnection` as the cocoa equivalent of the spec's
`events.find(CONNECTION_SUCCESS).connection`):

```swift
let wsProvider = MockWebSocketProvider(onConnectionAttempt: { connection in
    connection.respondWithSuccess()
    connection.sendToClient(.connected(connectionId: "connection-1", connectionKey: "key-abc-123"))
})
installMock(wsProvider)
let client = makeRealtime { options in
    options.key = "appId.keyId:keySecret"
    options.autoConnect = false
}
client.connect()
awaitConnectionState(client, .connected)
let ws = try #require(wsProvider.activeConnection)
```

When attempts need different behaviour (e.g. first succeeds, reconnects refused), branch on a counter
inside the handler:

Spec pseudocode:

```pseudo
connection_attempt_count = 0
mock_ws = MockWebSocket(
  onConnectionAttempt: (conn) => {
    connection_attempt_count++
    IF connection_attempt_count == 1:
      conn.respond_with_success()
      conn.send_to_client(ProtocolMessage(
        action: CONNECTED,
        connectionId: "conn-s",
        connectionKey: "key-s",
        connectionDetails: ConnectionDetails(connectionKey: "key-s", connectionStateTtl: 2000)
      ))
    ELSE:
      conn.respond_with_refused()
  }
)
```

Swift:

```swift
var attemptCount = 0
let wsProvider = MockWebSocketProvider(onConnectionAttempt: { connection in
    attemptCount += 1
    if attemptCount == 1 {
        connection.respondWithSuccess()
        connection.sendToClient(.connected(connectionId: "conn-s", connectionKey: "key-s", connectionStateTtl: 2))
    } else {
        connection.respondWithRefused()
    }
})
```

### Mock setup — HTTP

Spec pseudocode:

```pseudo
captured_requests = []
mock_http = MockHttpClient(
  onConnectionAttempt: (conn) => conn.respond_with_success(),
  onRequest: (req) => {
    captured_requests.push(req)
    req.respond_with(200, [1704067200000])
  }
)
install_mock(mock_http)
client = Rest(options: ClientOptions(key: "app.key:secret"))
```

Swift:

```swift
let capturedRequests = Captured<PendingHTTPRequest>()
let mockHTTPClient = MockHTTPClient(
    onConnectionAttempt: { connection in connection.respondWithSuccess() },
    onRequest: { request in
        capturedRequests.append(request)
        request.respondWith(status: 200, body: [1704067200000])
    }
)
installMock(mockHTTPClient)
let rest = makeRest { $0.key = "app.key:secret" }
```

### Variable declarations

Take spec variable names (adapted to camelCase), for new ones, if needed don't use "noname" names (like
"fields"), make the name concrete.

### Capturing connection attempts / requests

The target is built in the Swift 6 language mode. Since mock handler closures are `@Sendable` and run on
the SDK's queues, a plain `var array` captured into them is a compile error (a data race). Use the UTS
infra's thread-safe (lock-guarded) `Captured<T>` instead:

Spec pseudocode:

```pseudo
captured_connection_attempts = []
mock_ws = MockWebSocket(
  onConnectionAttempt: (conn) => {
    captured_connection_attempts.append(conn)
    conn.respond_with_success()
    conn.send_to_client(ProtocolMessage(
      action: CONNECTED,
      connectionId: "c",
      connectionKey: "k",
      connectionDetails: ConnectionDetails(connectionKey: "k")
    ))
  }
)
# ... after AWAIT_STATE client.connection.state == ConnectionState.connected:
ASSERT captured_connection_attempts[0].url.query_params["recover"] == "..."
```

Swift:

```swift
let capturedConnectionAttempts = Captured<MockWebSocket>()
let wsProvider = MockWebSocketProvider(onConnectionAttempt: { connection in
    capturedConnectionAttempts.append(connection)
    connection.respondWithSuccess()
    connection.sendToClient(.connected(connectionId: "c", connectionKey: "k"))
})
// ... after awaitConnectionState(client, .connected):
#expect(capturedConnectionAttempts[0].queryParams["recover"] == "...")
```

`Captured<T>` exposes `append`, `all`, `count`, `first`, and `subscript(Int)`. Use
`capturedConnectionAttempts.count` to change outcome for different connection attempts.

### Inspecting outgoing frames

The spec inspects client-sent frames through the mock's event timeline
(`mock_ws.events.filter(e => e.type == "ws_frame" AND e.direction == "client_to_server")`); the cocoa UTS
infra exposes the decoded equivalent as `ws.sentMessages`. Capture after the channel/connection state
confirms the send happened:

Spec pseudocode:

```pseudo
ws_connection = mock_ws.events.find(e => e.type == CONNECTION_SUCCESS).connection
channel.attach()
ws_connection.send_to_client(ProtocolMessage(action: ATTACHED, channel: "channel-one", channelSerial: "serial-1"))
AWAIT_STATE channel.state == ChannelState.attached
sent_frames = mock_ws.events.filter(e => e.type == "ws_frame" AND e.direction == "client_to_server")
attach_frame = sent_frames.find(f => f.message.action == ATTACH AND f.message.channel == "channel-one")
ASSERT attach_frame.message.channelSerial == "serial-1"
```

Swift:

```swift
let ws = try #require(wsProvider.activeConnection)
channelOne.attach()
ws.sendToClient(.attached(channel: "channel-one", channelSerial: "serial-1"))
awaitChannelState(channelOne, .attached)
// cocoa's decoded equivalent of the spec's events.filter(ws_frame, client_to_server)
let attachFrames = ws.sentMessages.filter { $0.action == .attach && $0.channel == "channel-one" }
#expect(attachFrames.count == 1)
#expect(attachFrames.first?.channelSerial == "serial-1")
```

### Mock method reference

`connection` is the object the relevant handler hands you — for WebSocket it's the `MockWebSocket` passed
to `onConnectionAttempt` (the spec's `mock_ws`/`conn`); for HTTP it's the `PendingHTTPConnection` passed to
the `MockHTTPClient` `onConnectionAttempt`. `request` is the `PendingHTTPRequest` passed to `onRequest`.

| Pseudocode | Swift |
|---|---|
| `conn.respond_with_success()` | `connection.respondWithSuccess()` |
| `conn.respond_with_success(message)` | `connection.respondWithSuccess(message)` — accept + deliver in one call (e.g. `.connectedMessage`) |
| `conn.respond_with_refused()` | `connection.respondWithRefused()` |
| `mock_ws.send_to_client(msg)` | `connection.sendToClient(msg)` |
| `mock_ws.send_to_client_and_close(msg)` | `connection.sendToClientAndClose(msg)` |
| `mock_ws.simulate_disconnect()` | `connection.simulateDisconnect()` |
| `req.respond_with(200, {...})` | `request.respondWith(status: 200, body: [...])` |
| `req.respond_with_delay(delay, status, body)` | `request.respondWithDelay(delay, status: …, body: …)` |
| `req.respond_with_timeout()` | `request.respondWithTimeout()` |
| `conn.respond_with_refused/timeout/dns_error()` (HTTP) | `connection.respondWithRefused()` / `respondWithTimeout()` / `respondWithDNSError()` |

**Known WS-mock gap (core realtime/rest tier only):** the WS-level `conn.respond_with_timeout()` /
`conn.respond_with_dns_error()` some specs use have **no** `MockWebSocket` counterpart yet (only
success/refused/disconnect exist; the timeout/refused/DNS-error trio exists HTTP-side on
`PendingHTTPConnection`). When a spec calls them, either extend `MockWebSocket` (small — mirror
`respondWithRefused()`, plumbing the matching transport error) or record the case in `deviations.md`
under **Mock Infrastructure Limitations** — never silently substitute `respondWithRefused()`. This is a
genuine *missing* capability: a case that **cannot run**. It does **not** cover a tier that deliberately
drives without a WS mock by design (e.g. the objects unit tier seeds the graph directly — see
`objects-mapping.md` §13); that is a sanctioned infra choice whose ports all run, is **not** a Mock
Infrastructure Limitation, and is **not** recorded in `deviations.md`.

### Protocol messages and types

Server-to-client messages are described with the `Sendable` `ProtocolMessage` factories —
`sendToClient`/`sendToClientAndClose` take a `ProtocolMessage` and build the real `ARTProtocolMessage` at
delivery, so no non-Sendable value crosses the queue hop. Use these factories; add a new one (and the
matching `makeProtocolMessage()` case) if you need another action:

| Pseudocode | Swift |
|---|---|
| `ProtocolMessage(action: CONNECTED, connectionId, connectionKey, connectionDetails(...))` | `.connected(connectionId:, connectionKey:, maxIdleInterval:, connectionStateTtl:)` |
| `ProtocolMessage(action: ATTACHED, channel, channelSerial)` | `.attached(channel:, channelSerial:)` |
| `ProtocolMessage(action: ERROR, error: ErrorInfo(code, statusCode, message))` | `.error(code:, statusCode:, message:)` |
| `ProtocolMessage(action: ACK, msgSerial, count)` | `.ack(msgSerial:, count:)` |
| `ProtocolMessage(action: CLOSED)` | `.closed()` |
| `CONNECTED_MESSAGE` (ready-made default) | `.connectedMessage` |
| `connectionStateTtl: 2000` (wire ms) | seconds here: `connectionStateTtl: 2` |
| `ConnectionState.connected` / `ChannelState.attached` | `.connected` / `.attached` (`ARTRealtimeConnectionState` / `ARTRealtimeChannelState`) |

### Awaiting state

`AWAIT_STATE x.state == ConnectionState.X` → `awaitConnectionState(client, .x)` (default 2s timeout, or
`timeout:`). Channels: `awaitChannelState(channel, .attached)`. For other conditions (e.g. "a frame was
sent") use `poll("description") { <bool> }`. Don't use poll unless you can't find alternative or spec says
to do so.

### Timer control

Spec pseudocode:

```pseudo
client = Realtime(...)
# ...
enable_fake_timers()
# ...
ADVANCE_TIME(1500)                     # fires due timers
```

Swift:

```swift
enableFakeTimers()                     // BEFORE makeRealtime/makeRest
let client = makeRealtime { ... }
// ...
advanceTime(byMilliseconds: 1500)      // fires due timers and settles the cascade
```

For multi-retry scenarios use the spec's loop (don't compute exact jumps):

Spec pseudocode:

```pseudo
LOOP up to 10 times:
  ADVANCE_TIME(1500)
  IF client.connection.state == ConnectionState.suspended:
    BREAK
AWAIT_STATE client.connection.state == ConnectionState.suspended
```

Swift:

```swift
for _ in 0..<10 {
    advanceTime(byMilliseconds: 1500)
    if client.connection.state == .suspended { break }
}
awaitConnectionState(client, .suspended)
```

### Asserting on logs

To assert "an error is logged", inject a `CapturingLog` and check it:

```swift
let log = CapturingLog()
let client = makeRealtime { $0.key = "..."; $0.logHandler = log }
// ...
#expect(log.contains(level: .error, message: "recovery key"))
```

### Comments and assertion fidelity

Carry over **every** comment from the spec pseudocode verbatim, as a `//` comment at the matching step —
these explain *why* each step exists and must not be dropped or paraphrased.

Translate every spec `ASSERT`/`AWAIT` into a Swift assertion at the same place. If an assertion genuinely
has no Swift equivalent (e.g. it checks a language-specific construct, or the SDK exposes no observable
hook for it), **do not silently omit it** — keep the spec's comment/line and add a `//` note explaining why
no assertion is emitted. Never delete the spec line.

```swift
// The recovery key should round-trip the connection id        ← spec comment, copied verbatim
#expect(recovered.connectionId == "connection-1")

// ASSERT connection.errorReason IS null
// (no assertion: ARTConnection exposes no errorReason getter in this state — see deviations.md)
```

A dropped or weakened assertion that is *not* annotated this way is a bug — Step 7 re-checks for it.

### Assertions (Swift Testing)

Use Swift Testing macros (`import Testing`, **not** `XCTest`):

| Pseudocode | Swift |
|---|---|
| `ASSERT x == y` | `#expect(x == y)` |
| `ASSERT x IS NOT null` | `let x = try #require(optional)` (or `#expect(x != nil)`) |
| `ASSERT x IS null` | `#expect(x == nil)` |
| `ASSERT x IS Auth` (type check) | `#expect(x is ARTAuth)` — or `let auth = try #require(x as? ARTAuth)` when later lines use the value |
| `ASSERT x matches pattern "..."` | `#expect(x.range(of: "...", options: .regularExpression) != nil)` |
| `ASSERT list CONTAINS_IN_ORDER [a, b, c]` | `#expect(list.filter { [a, b, c].contains($0) } == [a, b, c])` — or walk an index as the spec does |
| `ASSERT "k" IN map` / `NOT IN` | `#expect(map["k"] != nil)` / `#expect(map["k"] == nil)` |
| `ASSERT list.length == N` | `#expect(list.count == N)` |
| `ASSERT x == y (with message)` | `#expect(x == y, "message")` |
| `AWAIT op FAILS WITH error` | capture the error (see async below) and `#expect(error.code == ...)` / `#expect(error.statusCode == ...)` |

`#expect(...)` records a failure and continues; `try #require(...)` unwraps/asserts and stops the test on
failure (use it when later lines depend on the value, like `XCTUnwrap`).

REST calls will callback (e.g. `rest.time { ... }`) — make the test `async throws` and create a helper
method that bridges the completion handler with a continuation:

```swift
private func awaitTime(_ rest: ARTRest, sourceLocation: SourceLocation = #_sourceLocation) async -> Date {
    await withCheckedContinuation { (continuation: CheckedContinuation<Date, Never>) in
        rest.time { date, error in
            if let error { Issue.record("time() failed: \(error)", sourceLocation: sourceLocation) }
            guard let date else { Issue.record("time() failed: date should not be nil", sourceLocation: sourceLocation) }
            continuation.resume(returning: date)   // resume exactly once
        }
    }
}
```

Put these `async` helpers in the test class extension at the bottom of the test file. Inside these helpers,
report non-assertion failures (timeouts, unexpected errors) with `Issue.record("...", sourceLocation:)`.

### Test naming and annotation

- `// UTS: <spec-id>` comment immediately above each test, then the `@Test` attribute. Copy the spec's
  **full** structured id verbatim (e.g. `realtime/unit/RTN16g/recovery-key-structure-0`; for the objects
  module it would start `objects/unit/…`). Don't hand-build the prefix — use what the spec file declares.
  (A hand-built prefix silently breaks the Step 7 audit's ID matching.)
- Method name: `test_<SPEC>_<description_with_underscores>` — keep the spec point intact, join words with
  underscores. Take the description from the spec test title. Keep camelCase for symbol names. Mark the
  function `throws` (and `async` if it awaits).

```swift
// UTS: realtime/unit/RTN16g/recovery-key-structure-0
@Test
func test_RTN16g_createRecoveryKey_returns_a_recovery_key() throws {
    ...
}
```

### File template (unit tier)

This scaffold is for the **unit** tier — it wires the mocked transport (`MockWebSocketProvider`,
`installMock`, `makeRealtime`). For the **integration** (direct sandbox) and **proxy** tiers, start from
the file templates in the **Integration tests** section instead, not from this one.

```swift
import Testing
import Foundation
import Ably
import Ably.Private

/// <Feature> (<spec points>)
/// Derived from <spec URL>
@Suite(.serialized)
final class <className>: UTSTestCase {

    // UTS: <spec-id>
    @Test
    func test_<SPEC>_<description>() throws {
        let wsProvider = MockWebSocketProvider(onConnectionAttempt: { connection in
            connection.respondWithSuccess()
            connection.sendToClient(.connected(connectionId: "connection-1", connectionKey: "key-1"))
        })
        installMock(wsProvider)
        let client = makeRealtime { options in
            options.key = "appId.keyId:keySecret"
        }

        client.connect()
        awaitConnectionState(client, .connected)

        #expect(client.connection.state == .connected)
        closeClient(client)
    }
}
```

Helper methods return types should be ready for use in the test code without additional casting (if you
need "value as? String" in the test, move this conversion to the helper instead). Don't return optionals
from these methods - assert not `nil` within the method itself, unless test expects optional. Don't create
additional helper types for parsing dictionaries - just use a dictionary with the most suited type for the
test, accessing its fields by subscript. For dictionaries containing values of different types use
`[String: Any]`. Don't wrap dictionary constant initialization into helper method. Put helper methods for
the suite into an extension at the bottom of the file. Keep the spec's original tests order in the
generated test file. Keep test segmentation by adding comments like "// Setup", "// Test Steps",
"// Assertions".

---

## Step 5 — Compile

```bash
swift build --build-tests
```

Fix any compilation errors and recompile until clean. Common issues:
- Missing `import Ably.Private` when the test touches internals.
- Mock method names differing from what you read in Step 3's files — use the exact signatures.
- Swift 6 `@Sendable` capture errors — a plain `var` captured in a mock handler is a compile error; use
  `Captured<T>` (see "Capturing connection attempts / requests").

---

## Step 6 — Run tests *(evaluate mode only)*

Skip this whole step in "translate only" mode. In "translate and evaluate" mode, run the test and resolve
every failure via the decision tree below. Each test must end in exactly one of these states — never an
**unexplained** red:
- the spec-correct assertion **passes**; or
- a documented **SDK deviation** — env-gated or adapted, stays green (SDK ≠ spec; fix belongs in the SDK); or
- a documented **UTS spec error** — **fails fast** (the spec is wrong; fix belongs in the spec). This is the
  one acceptable red.

Run the suite with the resolver's `className` as the filter:

```bash
# unit tier (fast, fully mocked, no network)
swift test --filter "UTS.<className>"
# a single test (Swift Testing matches the function name)
swift test --filter "UTS.<className>/<test_method_name>"
```

(`swift test --filter UTS` still runs the whole UTS target — including the integration tiers. There is
no env-var gating: integration and proxy suites run directly from `swift test` or the Xcode test runner;
they just need network access, and the proxy tier needs macOS — see `Test/UTS/README.md` §10.)

Handle test failures using this decision tree (the **Required reading** doc you fetched up front has the full detail):

```
Test fails
  |
  +-- Does UTS spec match features spec?  (fetch the features spec — see Required reading)
  |     NO  → UTS SPEC ERROR — fix the spec at source, not the test. Record in deviations.md
  |           (UTS Spec Errors) + emit a fail-fast test (below) so it's fixed early.
  |     YES
  |       +-- Does test accurately translate the UTS spec?
  |             NO  → fix the test (no deviation entry needed)
  |             YES → SDK deviation — env-gated skip or adapted assertion (below); record in the deviations file
```

### Test patterns for a diagnosed failure

Two patterns are for an **SDK deviation** (both write the spec-correct assertions); the third,
**spec-error fail-fast**, is for a **UTS spec error** and is not a deviation.

**Env-gated skip** *(preferred for a deviation you expect to be fixed)* — the test carries the
**spec-correct** assertions, but is disabled by default via the Swift Testing `.enabled(if:)` trait, so it
only runs when `RUN_DEVIATIONS` is set. Use this when the SDK diverges from the spec **today** but is
expected to converge — the skipped test becomes the executable record of what "correct" will look like:

```swift
// UTS: realtime/unit/RSA4c2/callback-error-connecting-disconnected-0
// DEVIATION: see deviations.md
@Test(.enabled(if: ProcessInfo.processInfo.environment["RUN_DEVIATIONS"] != nil))
func test_RSA4c2_callback_error_connecting_disconnected() throws {
    // ... spec-correct setup and assertions ...
}
```

Reproduce with `RUN_DEVIATIONS=1 swift test --filter "UTS.<className>/<method>"`.

**Adapted assertion** — assert the SDK's actual behaviour to prevent regressions. **Prefer this over an
env-gated skip when the divergence is permanent or intentional** (a documented, deliberate departure from
the spec that the SDK is *not* going to change): a running test guards against regressions, whereas a
permanently-skipped spec assertion verifies nothing. Record it as a permanent documented divergence:

```swift
// DEVIATION: spec requires error code 40106, SDK returns 40160 — see deviations.md
#expect(error.code == 40160)
```

**Spec-error fail-fast** *(UTS spec error — NOT an SDK deviation)* — when the decision tree's first branch
is **NO** (the UTS spec contradicts the features spec, or is internally inconsistent), the spec is the
fixable source of truth, so the test must **fail loudly** pointing at the deviation entry, rather than be
quietly adapted to green. This is the opposite of the SDK-deviation patterns above (which stay green /
assert actual behaviour) — failing fast is the forcing function that gets the spec fixed early.

```swift
// UTS: realtime/unit/RTN15c4/resume-token-error-0
@Test
func test_RTN15c4_resume_with_token_error_reattaches() throws {
    // SPEC ERROR RTN15c4: the replayed CONNECTED message contradicts the harness's resume rules.
    // Fix the UTS spec first — see deviations.md (UTS Spec Errors).
    Issue.record("UTS spec error RTN15c4 — fix the spec first; see deviations.md")
}
```

**Never use the accommodate-both pattern** (accept either spec or SDK behaviour). Every test must assert
either spec behaviour or the SDK's actual behaviour — never both at once.

Note: an *infra-driving* difference (e.g. using fake timers where the spec uses real ones, a
queue-ordering workaround, or standing in for the spec's mock transport by seeding state directly and
capturing at an internal publish seam) is **not** an SDK deviation — explain it in a code comment, not
`deviations.md`. `deviations.md` is only for SDK non-compliance and for mock-capability gaps that leave a
case **unable to run** (a skipped stub, per `writing-derived-tests.md`); a sanctioned stand-in whose ports
all run is neither.

### Deviations file

Record in the respective section of the deviations file that belongs to the tier's module, using the
manual's **Recording deviations** entry format and sections (the `writing-derived-tests.md` you fetched
up front — not a home-grown format). New entries are inserted into their category's section, never
appended at the file end. For most tiers that is the shared `Test/UTS/deviations.md`; a module whose notes
declare a module-scoped deviations file (Step 1) uses that one instead. The ably-cocoa-specific section
mapping: a **UTS Spec Error**
(test fails fast — fix in the spec) goes under the manual's *UTS Spec Errors* section (add the heading on
first use if absent); an **SDK deviation** (env-gated/adapted — fix in the SDK) goes under *Failing Tests*
/ *Adapted Tests*; a mock-capability gap goes under *Mock Infrastructure Limitations*.

---

## Step 7 — Review generated output against the spec

The translation isn't done when it compiles — it's done when **every line of the source spec is faithfully
represented** in the Swift: each test case, each setup step, each operation, and each assertion. Missing a
single `ASSERT` produces a test that compiles, passes, and silently checks less than the spec demands. This
review runs in **both** modes (it's static — it doesn't need the tests to have run).

### Deterministic faithfulness audit — run the script first

Eyeballing two files for "did I translate every line?" is exactly the kind of mechanical comparison the
model does inconsistently, so a bundled script extracts the ledger for you — same inputs, same report every
time. Run it for each translated spec — don't hand-build paths; use the resolver's output (Step A): the
**source spec file** is that spec's `specs[].file` (already an absolute path) and the **generated Swift
file** is the chosen tier's `targetDir` + `className` (Step 2):

```bash
python3 .claude/skills/uts-to-swift/scripts/audit_translation.py \
    "<tier.specs[].file>" \
    "<tier.targetDir>/<className>.swift"
```

It prints one JSON report and exits non-zero (2) when there are missing or orphan Test IDs. It does **no**
semantic judgement — it only extracts, deterministically, what you must then reconcile by hand:

- **`idCoverage`** — the spec's `**Test ID**` set vs the Swift file's `// UTS:` tag set.
  - `missingInSwift` **must be empty.** Each entry is a spec test case with no `@Test` method — implement it.
  - `orphanInSwift` **must be empty** (or every entry explained) — a `// UTS:` tag that no longer matches
    any spec Test ID means a stale or hand-edited tag.
  - `duplicateInSwift` **must be empty** — a tag carried by more than one `@Test` means the audit only
    examined the last method with that tag; deduplicate the tags first.
- **`perTest[]`** — for each spec test case, every non-comment code line inside the spec's `pseudo` blocks,
  **grouped by section** (`Setup` / `Test Steps` / `Assertions` / …) in `sections[]` and each line tagged
  `assert` (an `ASSERT*` outcome), `await` (an `AWAIT*` / `EXPECT` wait), or `step` (setup, mock/client
  construction, an operation). `specAsserts` / `specAwaits` are flat convenience views of the first two;
  `specCodeLineTotal` is the size of the spec test. The matching Swift method's calls come alongside,
  counted **separately** so a surplus of waits can't hide a dropped assertion: assertions
  (`#expect`/`#require` → `swiftAssertionCount`) and waits (`awaitConnectionState`/`awaitChannelState`/
  `awaitState`/`pollUntil`/`poll` → `swiftAwaitCount`).

The audit is a review aid, not a gate — it never crashes, it degrades. It always prints one JSON object
(an `error` field instead of a report if a file is unreadable). If `idCoverage.specCount` is `0` for a file
you know is a real spec, the extractor couldn't find any `**Test ID**` markers (an unusual spec format) —
treat that as "couldn't verify deterministically" and fall back to a manual side-by-side read for that
file. The known case is a **fixture-driven** spec (e.g. `rest/unit/encoding/msgpack_interop.md` — one
parameterised test looping over external fixture data instead of enumerated test cases): there the audit
will also report your `// UTS:` tag as an *orphan* — expected, not a defect; explain it in the review and
verify that file by hand.

### Coverage check — every test case is present

From the audit's `idCoverage`:
- [ ] `missingInSwift` is empty (every spec Test ID has an `@Test` with that ID in its `// UTS:` comment)
- [ ] `orphanInSwift` is empty, or each orphan is a deliberate, explained rename
- [ ] `duplicateInSwift` is empty (no `// UTS:` tag is shared by two test methods)
- [ ] Each method name contains the spec ID and a meaningful description

### Line-by-line completeness — every spec line is translated

Walk the audit's `perTest[].sections` and reconcile **each** extracted spec line against the Swift method.
This is the guarantee that no setup step, operation, or assertion was dropped — the whole point of this step:
- [ ] Every `assert` line maps to a concrete Swift assertion (`#expect`, `try #require`, …) — not a
      comment, not a weaker check
- [ ] Every `await` line (state waits **and** awaited operations like `AWAIT channel.attach()` /
      `setup_synced_channel(...)`) is performed via `awaitConnectionState` / `awaitChannelState` /
      `poll` (unit tier) or `awaitState` / `awaitChannelState` / `pollUntil` (integration tiers) or
      the corresponding SDK call
- [ ] A value-assigned `poll_until` (`x = poll_until(…)`) maps to the generic value-returning
      `pollUntil` with later assertions on the returned value — **no re-read after the poll** (the
      rule lives in `writing-derived-tests.md`; the overloads in `infra/Utils.swift`)
- [ ] Every `step` line — client/mock construction, `ClientOptions`, installed mocks, channel ops — is
      reflected in the test setup or body. Multi-line spec constructs split across several `step` lines;
      reconcile them as a group.
- [ ] The pseudocode's inline `#` comments are carried over as `//` comments at the matching steps verbatim
- [ ] A spec line with no Swift equivalent is annotated per "Comments and assertion fidelity" (spec line
      kept + `//` note), never silently dropped
- [ ] `assertionShortfall > 0` for a test (`summary.testsWithShortfall`) is a **tripwire** — fewer Swift
      `#expect`/`#require` calls than spec `ASSERT`s strongly suggests a dropped assertion; open that test
      and account for each one. (A negative shortfall is fine — the SDK mapping often needs *more* Swift
      lines per spec `ASSERT`; an annotated omission — e.g. a type check satisfied by a helper's return
      type — is a valid account.)
- [ ] `awaitShortfall > 0` (`summary.testsWithAwaitShortfall`) is the **softer secondary signal** — fewer
      infra wait calls than spec `AWAIT`s. A custom continuation-bridged helper (like `awaitTime`)
      legitimately replaces a wait call, and on a **natively-async SDK API** (a module whose SDK
      surface is `async` methods — its translation notes will say) a
      spec `AWAIT op` correctly becomes a plain `try await` expression the counter doesn't see —
      expect a benign shortfall on nearly every such test. Account for those rather than treating
      this as a gate.

### Setup fidelity — preconditions match the spec

For each test case, verify:
- [ ] Client options (`autoConnect`, `recover`, timeouts, etc.) match the spec's `ClientOptions`
- [ ] Mock responses (success / refused / timeout / DNS error / custom messages) match the spec's prescribed network behaviour
- [ ] Timer setup (`enableFakeTimers`, `advanceTime(byMilliseconds:)`) matches every `enable_fake_timers` / `ADVANCE_TIME` in the spec
- [ ] Channel operations (attach, detach, publish) are performed in the order the spec requires

### Deviation honesty *(evaluate mode)*

Deviations are discovered by running, so this check applies in evaluate mode. For any place where the
generated test diverges from the spec pseudocode (adapted assertion, env-gated skip, or omitted step):
- [ ] A `// DEVIATION:` comment explains why
- [ ] The deviation is recorded in `Test/UTS/deviations.md`

If you find gaps during this review, fix them, then **re-run the audit script** until `missingInSwift` /
`orphanInSwift` / `duplicateInSwift` are empty and every `perTest` entry reconciles, and re-run Step 5
(compile) — and, in evaluate mode, Step 6 — before finishing.

---

## Integration tests (direct sandbox + proxy)

Some specs are **integration tests** — they run against the **real Ably sandbox** instead of a mocked transport. Two tiers share one foundation and differ only in *transport*:

- **Direct sandbox** — the client connects straight to the sandbox. Happy-path interop (connect, publish, subscribe, presence); no faults.
- **Proxy** — the client is routed through the [`ably/uts-proxy`](https://github.com/ably/uts-proxy), a programmable HTTP/WebSocket proxy that forwards traffic transparently but can inject faults (dropped connections, modified/injected/delayed frames, error responses) via rules.

**Shared foundation (both tiers, covered once):** `SandboxApp` provisioning and teardown via the tier's
base test case, real (unmocked) clients, and the async `awaitState` / `awaitChannelState` / `pollUntil`
waits — never a fixed sleep, since real network is involved. The helpers' defaults (15s) already
satisfy the spec's generous-timeout guidance: pass an explicit `timeout:` only when the spec itself
states one; for steps the spec doesn't time (including plumbing the port adds, per
`writing-derived-tests.md`), omit it. The `poll_until` form mapping (value-assigned → the generic
value-returning `pollUntil`, bare condition → the Bool overload) is documented on the helpers
themselves (`infra/Utils.swift` doc comments, `Test/UTS/README.md` §11.3) and its semantics in
`writing-derived-tests.md`. Swift Testing has no `setUp()`/`tearDown()` and `deinit` can't `await`, so the base cases
provide **scoped-resource methods** instead — each `with…` method provisions its resource, runs your body,
and *always* tears it down, rethrowing the body's error afterwards. **Never hand-roll teardown**; wrap the
scenario in the scopes. Only the *wiring* differs per tier; that's what the two tier subsections below
cover.

**Required reading for the proxy tier:** before translating any proxy spec, read
`uts/docs/proxy.md` (once per run) — it defines the proxy session/control API, the rule and action
vocabulary, and the protocol action-number table the subsections below rely on. Fetch
[the raw URL](https://raw.githubusercontent.com/ably/specification/refs/heads/main/uts/docs/proxy.md);
if that 404s (the `docs/` layout may not be merged upstream yet), read it from the spec checkout the
module directory came from instead: `<module-dir>/../docs/proxy.md`.

Recognise a **proxy** spec by a reference to `create_proxy_session()`, proxy `rules`, `trigger_action`,
`get_log`, or a pointer to `uts/docs/proxy.md`. A spec with none of those is **direct sandbox**.

### Which integration tier?

| Test type | When the spec uses it |
|---|---|
| **Unit test** (mock HTTP/WS — the rest of this skill) | Client-side logic, state machines, request formation, error parsing. Fast, deterministic. |
| **Direct sandbox integration** | Happy-path behaviour (connect, publish, subscribe, presence). No fault injection. |
| **Proxy integration test** | Fault behaviour against the real backend: connection failures, resume, heartbeat starvation, token renewal under network errors, channel error injection. |

### Direct-sandbox integration tests

A **direct-sandbox** spec (no `create_proxy_session`, no rules — just happy-path interop against
`nonprod:sandbox`) uses the same `SandboxApp` provisioning as a proxy test but **drops all proxy wiring**:
no `ProxyManager`, no `ProxySession`, no `connectThroughProxy`. The client connects straight to the
sandbox host. `Test/UTS/integration/standard/realtime/ChannelHistoryTests.swift` (RTL10d — ably-java's
`ChannelHistoryTest` is its sibling) is the reference example — read it before translating a
direct-sandbox spec. For the **proxy** tier the reference is
`Test/UTS/integration/proxy/realtime/AuthReauthTests.swift` (RTN22/RTC8a). Don't add env-var gating to
generated tests — integration suites run ungated (they just need network; see `Test/UTS/README.md` §10).

Suites subclass `IntegrationTestCase` and wrap the scenario in the scoped-resource methods:
`withSandboxApp { app in … }` provisions a throwaway sandbox app and always deletes it;
`withRealtimeClient(options) { client in … }` builds a real `ARTRealtime` and always closes it (waiting
for CLOSED).

**Client wiring** — point both transports at the sandbox host; TLS stays on, so the plain sandbox key
works (RSA1). Explicit hosts auto-disable fallback hosts (REC2c2), so no `fallbackHosts`:

```swift
let options = ARTClientOptions(key: app.defaultKey)
options.realtimeHost = SandboxApp.sandboxHost   // sandbox.realtime.ably-nonprod.net
options.restHost = SandboxApp.sandboxHost
options.useBinaryProtocol = useBinaryProtocol
options.autoConnect = false
```

For a **plugin-backed module**, the client options must also install the module's plugin — the
module's entry-point property traps without it. The module's translation notes name the exact
wiring, and the module packages it as a client-options builder in its module `helpers/` directory
(see **Module helpers** below) — use that builder; don't hand-wire the plugin per test.

**Class docstring** — use a direct-sandbox variant (no proxy/fault-injection wording):

```swift
/// Direct-sandbox integration test against the Ably Sandbox (`sandbox.realtime.ably-nonprod.net`,
/// via SandboxApp.sandboxHost) — no proxy, no fault injection. Provisions a throwaway SandboxApp
/// and connects real clients straight to the sandbox.
```

**Protocol variants (`json` / `msgpack`)** — when the spec header declares a `PROTOCOL` dimension and says
each test runs once per variant, translate it to a parameterised test over `useBinaryProtocol` (Swift
Testing has this built in — no extra imports), not a plain `@Test`. The `// UTS:` tag and method name stay
singular — the parameter expresses the variant:

```swift
// UTS: realtime/integration/RTL10d/history-cross-client-0
@Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
func test_RTL10d_history_contains_messages_published_by_another_client(useBinaryProtocol: Bool) async throws {
    // …
}
```

A spec with **no** protocol dimension stays a plain `@Test`. Only the direct-sandbox tier is
parameterised — the proxy tier is always JSON (see "Connecting through the proxy").

**Awaiting real server outcomes** — integration specs assert on real backend state, so never sleep; await
or poll:

| Pseudocode | Swift |
|---|---|
| `AWAIT channel.attach()` | `channel.attach()` then `guard await awaitChannelState(channel, .attached, timeout: 10) else { return }` |
| `AWAIT channel.publish(name, data)` (await the ack) | bridge the callback overload (`publish(_:data:callback:)`) with a continuation, resuming on the callback and recording an `Issue` on error — same helper pattern as Step 4's `awaitTime` |
| `poll_until(() => AWAIT channel.history().items.length == N, …)` | `await pollUntil("history has N items") { await historyItems(of: channel).count == N }` — with a continuation-bridged `history` helper (see `ChannelHistoryTests` and `Test/UTS/README.md` §11.4 for the concrete helpers) |

Use generous timeouts (10–30s) — real network is involved. Everything else is the shared foundation
described at the top of this section; a direct-sandbox test just skips the proxy-only subsections
(`ProxySession`, rule factories, the event log).

**Natively-async SDK APIs** (modules whose SDK surface is typed-throws `async` methods — their
translation notes will say): a spec `AWAIT op`
translates to a plain `try await op` — no continuation bridging, no infra wait call. Only core-SDK
callback APIs (attach/detach/publish/history) still need the continuation helpers above. Two
consequences:

- `AWAIT x WITH timeout: N seconds` on such an op has **no per-call Swift equivalent** (`await`
  takes no timeout). Keep the plain `try await` and note the spec's timeout in a comment — a hang
  surfaces as the test-runner timeout. (Only `AWAIT_STATE` timeouts map to a parameter:
  `awaitState(..., timeout: N)`.)
- The Step 7 audit counts only infra wait calls, so these tests report a benign `awaitShortfall` —
  see the Step 7 checklist for the valid account.

**`try?` in `pollUntil` conditions — SE-0230 trap.** Poll closures are non-throwing, so typed
throwing reads get wrapped in `try?` — and Swift **flattens** the nested optional:
`try? node.asPrimitive().value()` (a `throws → Primitive?` call) yields `Primitive?`, not
`Primitive??`, making both "threw" and "resolved to nil" read as `nil` (and making a further `?.`
chain on the unwrapped value a compile error). Package such reads as small non-throwing helpers
(`guard let value = try? … else { return nil }`) rather than inlining the `try?`.

**Module helpers** — wiring/read helpers shared by *several* of a module's suites (client-options
builders, channel builders, typed `value()` readers) go in a `helpers/` directory **next to the
suites**: `integration/standard/<module>/helpers/`. Do not put module-specific helpers under
`infra/` — that stays module-agnostic. Suite-specific helpers (a continuation bridge used by one
file) stay in the per-file extension as usual.

**File template — direct sandbox** (`integration/standard/<module>/`):

```swift
import Testing
import Foundation
import Ably

/// <Feature> (<spec points>)
/// Derived from <spec URL>
@Suite(.serialized)
final class <className>: IntegrationTestCase {

    // UTS: <spec-id>
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_<SPEC>_<description>(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            let options = ARTClientOptions(key: app.defaultKey)   // TLS stays on → plain key auth is fine
            options.realtimeHost = SandboxApp.sandboxHost
            options.restHost = SandboxApp.sandboxHost
            options.useBinaryProtocol = useBinaryProtocol
            options.autoConnect = false
            try await withRealtimeClient(options) { client in
                client.connect()
                guard await awaitState(client, .connected) else { return }
                // … spec steps — guard every wait; the scopes above handle all teardown …
            }
        }
    }
}
```

### Infrastructure

The helpers live under `Test/UTS/infra/integration/`. **Read the ones your tier uses before translating an
integration spec** — they hold the exact method signatures. `SandboxApp` and `IntegrationTestCase` serve
**both** tiers; `ProxyManager`, `ProxySession`, and `ProxyTestCase` are **proxy-only**.

- **`SandboxApp`** (`infra/integration/SandboxApp.swift`) — provisions/deletes a sandbox test app from the
  shared `test-app-setup.json` in ably-common. `SandboxApp.create()` returns a `SandboxApp` with `appId`,
  `defaultKey`, and `keys` (`defaultKey` is a full-capability `appId.keyId:keySecret`); `app.delete()`
  tears it down. Also owns the single upstream sandbox host constant `SandboxApp.sandboxHost`
  (`sandbox.realtime.ably-nonprod.net`, the resolved `nonprod:sandbox` endpoint) — the default target of
  every `ProxySession`, and what direct-sandbox clients set `realtimeHost` / `restHost` from.
- **`IntegrationTestCase`** (`infra/integration/IntegrationTestCase.swift`) — the direct-sandbox base
  class: `withSandboxApp`, `withRealtimeClient`, and the `runThenCleanUp(_:body:cleanup:)` engine they're
  built on (run body, always run cleanup, rethrow the body's error) — subclasses use it for their own
  scopes.
- **`ProxyManager`** (`infra/integration/proxy/ProxyManager.swift`) — actor that syncs (downloads,
  checksum-verifies, caches) and starts the shared `uts-proxy` process; `ensureProxy()` is idempotent.
  Spawning a local process makes the proxy tier **macOS-only** — wrap proxy test files in
  `#if os(macOS)`. (`UTS_PROXY_LOCAL_PATH` points it at a locally built binary instead.)
- **`ProxySession`** (`infra/integration/proxy/ProxySession.swift`) — one programmable session wrapping
  the proxy control API; also defines the `connectThroughProxy` extension, the rule-factory helpers, and
  the typed `ProxyEvent`.
- **`ProxyTestCase`** (`infra/integration/proxy/ProxyTestCase.swift`) — the proxy base class (extends
  `IntegrationTestCase`): `withProxySession(rules:)` and `proxyClientOptions(for:through:)`.

The `SandboxApp` and `ProxySession` methods are all **`async`** — call them with `try await` inside the
scoped bodies. Imports are simple: `import Testing`, `import Foundation`, `import Ably` (+
`import Ably.Private` only if the spec asserts on SDK internals) — the whole UTS target is one module, so
the infra helpers need no imports.

### Proxy test class docstring

Give every proxy integration test class this doc comment:

```swift
/// Proxy integration test against Ably Sandbox endpoint.
///
/// Uses the programmable uts-proxy to inject transport-level faults while the
/// SDK communicates with the real Ably backend. See
/// `uts/docs/proxy.md` for proxy infrastructure details.
```

### Session lifecycle

`create_proxy_session(endpoint: "nonprod:sandbox", rules: [...])` → the base class's
`withProxySession(rules:)` — it ensures the proxy is running, provisions the sandbox app, creates the
session, and **always** closes the session and deletes the app afterwards (the sandbox is already the
session's default target, so the endpoint argument drops). Never hand-roll the teardown:

```swift
try await withProxySession(rules: [wsConnectRule(action: ["type": "refuse_connection"], count: 2)]) { app, session in
    let options = proxyClientOptions(for: app, through: session)
    options.autoConnect = false
    try await withRealtimeClient(options) { client in
        client.connect()
        guard await awaitState(client, .connected, timeout: 15) else { return }
        // … scenario …
    }
}   // client closed, session closed, app deleted — even on failure
```

| Pseudocode | Swift |
|---|---|
| `create_proxy_session(endpoint: "nonprod:sandbox", rules: [...])` | `withProxySession(rules: [...]) { app, session in … }` |
| `session.add_rules(rules, position: "prepend")` | `try await session.addRules(rules, position: "prepend")` |
| `session.trigger_action({ type: "disconnect" })` | `try await session.triggerAction(["type": "disconnect"])` |
| `session.get_log()` | `try await session.getLog()` |
| `session.close()` | handled by `withProxySession` — don't call it yourself |
| `session.proxy_port` / `session.proxy_host` | `session.proxyPort` / `session.proxyHost` |

### Connecting through the proxy

Call `options.connectThroughProxy(session)` on the client options. It is an `ARTClientOptions` extension
(in `ProxySession.swift`) that wires the SDK through the proxy:

| Proxy-def option | What `connectThroughProxy` sets |
|---|---|
| `endpoint: "localhost"` | `realtimeHost` **and** `restHost` = `session.proxyHost` (`"localhost"`) |
| `port: proxy_port` | `port = session.proxyPort` |
| `tls: false` | `tls = false` |
| `useBinaryProtocol: false` | `useBinaryProtocol = false` — set explicitly (the proxy can only inspect text frames; the UTS proxy specs require JSON), so proxy tests are **always JSON** — never parameterise the protocol here |

It does **not** touch `autoConnect`, so set that yourself. Setting explicit hosts disables fallback hosts
automatically (REC2c2), so don't add `fallbackHosts`.

### Auth in proxy tests

The proxy serves plain ws (`tls = false`) and basic (key) auth is TLS-only (**RSA1**), so a proxied client
can't just use the sandbox key. Where the pseudocode "generates a JWT from the key parts", the idiomatic
ably-cocoa equivalent is a **locally-signed `TokenRequest`** from the same sandbox key — no JWT library
required: a separate TLS "token signer" `ARTRest` calls `auth.createTokenRequest(params, options:)` inside
an `authCallback`, and the realtime client exchanges it for a token through the proxy.

The base class packages all of this: **`proxyClientOptions(for: app, through: session)`** returns
`ARTClientOptions` with the token-signer `authCallback` and `connectThroughProxy` already wired. Its body
(in `ProxyTestCase.swift`) is the pattern to inline when a spec needs to count or intercept the auth
callbacks itself:

```swift
let signerOptions = ARTClientOptions(key: app.defaultKey)
signerOptions.restHost = SandboxApp.sandboxHost
let tokenSigner = ARTRest(options: signerOptions)   // TLS, real host — local signing plus one token fetch

let options = ARTClientOptions()
options.authCallback = { params, callback in
    tokenSigner.auth.createTokenRequest(params, options: nil) { tokenRequest, error in
        callback(tokenRequest, error)
    }
}
options.connectThroughProxy(session)
```

(The auth types are top-level classes in cocoa — `ARTTokenParams`, `ARTTokenRequest`, `ARTAuthDetails` —
unlike ably-java, where `TokenParams`/`TokenRequest` are nested in `Auth` and `AuthDetails` in
`ProtocolMessage`.)

### Rule factory helpers

Build rules with the factory helpers in `ProxySession.swift` rather than raw dictionary literals. Rules
are evaluated in order, first match wins, unmatched traffic passes through, and `times` auto-removes a
rule after N firings.

| Match condition | Swift |
|---|---|
| `{ "type": "ws_connect", "count": 2 }` | `wsConnectRule(action: …, count: 2)` |
| `{ "type": "ws_connect", "queryContains": { "resume": "*" } }` | `wsConnectRule(action: …, queryContains: ["resume": "*"])` |
| `{ "type": "ws_frame_to_client", "action": "ATTACHED", "channel": "c" }` | `wsFrameToClientRule(action: …, messageAction: 11, channel: "c")` |
| `{ "type": "ws_frame_to_server", "action": "ATTACH", "channel": "c" }` | `wsFrameToServerRule(action: …, messageAction: 10, channel: "c")` |
| `{ "type": "http_request", "method": "POST", "pathContains": "/keys/" }` | `httpRequestRule(action: …, method: "POST", pathContains: "/keys/")` |

`messageAction` is the protocol action **number** (e.g. `4` CONNECTED, `6` DISCONNECTED, `9` ERROR, `10`
ATTACH, `11` ATTACHED) — see the action-number table in `uts/docs/proxy.md` (the doc you fetched at the
top of this section).

Actions are passed as `ProxyRule` dictionary literals, e.g.:

```swift
["type": "refuse_connection"]
["type": "disconnect"]
["type": "suppress"]
["type": "delay", "delayMs": 2000]
["type": "inject_to_client", "message": ["action": 6]]
["type": "http_respond", "status": 401, "body": ["...": "..."]]
```

### Verifying the event log

`getLog()` returns a typed `[ProxyEvent]`. Access fields via dot notation (`$0.type`, `$0.direction`,
`$0.queryParams`, `$0.status`); numeric fields (`status`, `closeCode`) are already `Int?`. The raw protocol
message is exposed as `ProxyEvent.message` (a `[String: Any]?`) — introspect it with
`event.message?["action"] as? Int`.

```swift
let log = try await session.getLog()
let wsConnects = log.filter { $0.type == "ws_connect" }
#expect(wsConnects.count >= 2)
let queryParams = try #require(wsConnects.first?.queryParams)
#expect(queryParams["resume"] != nil)
```

### Conventions

1. Each test references the spec point and (where it exists) the corresponding unit test.
2. Setup/teardown (proxy launch, sandbox app, session, client close) is the **base class's** job — wrap
   scenarios in `withProxySession` / `withSandboxApp` / `withRealtimeClient`; never hand-roll it.
3. **Guard every wait** — `guard await awaitState(…) else { return }`: a timeout already records an
   `Issue`, so stop instead of driving a client in the wrong state (the scopes still tear down).
4. Use `awaitState` / `awaitChannelState` for state assertions; verify via SDK state **and** the proxy log
   where useful.
5. Use generous timeouts (10–30s) — real network is involved: `await awaitState(client, .connected, timeout: 15)`.
6. Don't set `fallbackHosts`; explicit hosts already disable fallbacks. Wrap proxy test files in
   `#if os(macOS)`.

Step 5 (compile) still applies; Step 6 (run) applies only in evaluate mode (Step E). Note that proxy tests
hit the live sandbox and download the proxy binary on first run, so they are slower and require network
access.

**File template — proxy** (`integration/proxy/<module>/`):

```swift
// Proxy tests spawn a local uts-proxy process — macOS-only.
#if os(macOS)

import Testing
import Foundation
import Ably

/// Proxy integration test against Ably Sandbox endpoint.
///
/// Uses the programmable uts-proxy to inject transport-level faults while the
/// SDK communicates with the real Ably backend. See
/// `uts/docs/proxy.md` for proxy infrastructure details.
@Suite(.serialized)
final class <className>: ProxyTestCase {

    // UTS: <spec-id>
    @Test
    func test_<SPEC>_<description>() async throws {
        try await withProxySession(rules: []) { app, session in   // rule-less start = late fault injection
            let options = proxyClientOptions(for: app, through: session)  // token auth; JSON forced
            options.autoConnect = false
            try await withRealtimeClient(options) { client in
                client.connect()
                guard await awaitState(client, .connected) else { return }
                // Late imperative fault injection, then poll — never sleep — and verify via the log:
                try await session.triggerAction(["type": "inject_to_client", "message": ["action": 17]])
                await pollUntil("client reacted to the injected frame") { /* observable state */ true }
                let log = try await session.getLog()
                #expect(log.contains { $0.type == "ws_frame" && $0.direction == "client_to_server" })
            }
        }   // client closed, session closed, app deleted — even on failure
    }
}

#endif
```
