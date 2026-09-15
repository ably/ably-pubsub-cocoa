# `objects` UTS → ably-cocoa `AblyLiveObjects`: ably-js ⇄ Swift type/interface map

Read this **before translating any spec from the `objects` module** (target module
`AblyLiveObjects`, in `LiveObjects/Sources/AblyLiveObjects`). The `objects` UTS specs are written
in a language-agnostic pseudocode that mirrors the **ably-js** LiveObjects API — a
dynamically-typed surface with a single polymorphic `PathObject` / `Instance`, `Promise`-returning
mutators, and raw JS values. ably-cocoa is a **statically-typed SDK** and implements the *Typed-SDK
variant* of the spec (`RTTS1`–`RTTS10` in `objects-features.md`) — with two deliberate,
Swift-idiomatic consolidations recorded on AIT-1023 and in the API's doc comments:

1. the spec's six primitive path-object / instance sub-types collapse into a single
   `PrimitivePathObject` / `PrimitiveInstance` resolving to a pattern-matchable `Primitive` enum
   (divergence from `RTTS6c`/`RTTS10c`), and
2. `Instance` is an **enum** (`.liveMap` / `.liveCounter` / `.primitive`), not a base type with
   throwing `as*` casts (`RTTS9`), so discrimination is compile-time-exhaustive.

So almost every spec line needs a mechanical rewrite, not a literal transcription. This doc is that
rewrite table. The canonical bridge is the spec's own Interface Definition
(`## Interface Definition {#idl}`) and its `=== Typed-SDK variant (RTTS1-RTTS10) ===` block; where
this doc and the IDL disagree, check the Swift source (`Path Based API/Public/*.swift`) — it is the
ground truth for this SDK, including the two consolidations above.

> ✅ **Runtime status.** The path-based public API is **implemented** — the `Default*` path-object
> and instance types no longer trap, so `objects` specs are translate **and** evaluate (Steps 5
> and 6), with **no** `.disabled` trait required. (The `.disabled("…not yet implemented…")` traits
> the earlier skeleton needed have been removed; evaluate mode is now the normal path.)

## Table of contents

1. [The three layers (don't conflate them)](#1-the-three-layers)
2. [Entry point & channel access](#2-entry-point)
3. [Async: Promise/await → Swift `try await` (typed throws)](#3-async)
4. [Dynamic `PathObject` → typed `PathObject` views](#4-pathobject)
5. [Dynamic `Instance` → the `Instance` enum](#5-instance)
6. [Creation value types & the `LiveMapValue` union](#6-value-types)
7. [Mutations (set / remove / increment / decrement)](#7-mutations)
8. [Subscriptions, listeners & events](#8-subscriptions)
9. [Sync-state events (`object.on('synced')`)](#9-sync-state)
10. [`ValueType` & type discrimination](#10-valuetype)
11. [Message / operation types (`PublicAPI::ObjectMessage` →)](#11-messages)
12. [Errors & error codes](#12-errors)
13. [Internal-graph types (unit specs) — important caveats](#13-internal-graph)
14. [Integration-test helpers — REST fixture provisioning](#14-integration-helpers)
15. [Worked example](#15-worked-example)
16. [Quick symbol index](#16-symbol-index)

---

## 1. The three layers <a id="1-the-three-layers"></a>

The single biggest source of confusion: the spec uses the names `LiveMap` / `LiveCounter` for **two
different things**, and a third *internal* layer underneath. Keep them straight:

| Layer | Spec name | ably-js | ably-cocoa | Where |
|---|---|---|---|---|
| **Creation value type** — immutable blueprint you pass *into* `set` | `LiveMap` / `LiveCounter` (the `RTLMV*` / `RTLCV*` classes) | `LiveMap.create()` / `LiveCounter.create()` | `struct LiveMap` / `struct LiveCounter` | `Path Based API/Public/ValueTypes.swift` |
| **Public read/write view** — what you navigate & subscribe on | `PathObject`, `Instance` | `PathObject`, `Instance` | `PathObject` protocol + typed views (§4); `Instance` enum (§5) | `Path Based API/Public/PathObject.swift` / `Instance.swift` |
| **Internal graph object** — the live CRDT node | `InternalLiveMap` / `InternalLiveCounter` (`RTLM*` / `RTLC*`), `ObjectsPool` | internal | `InternalDefaultLiveMap` / `InternalDefaultLiveCounter` / `ObjectsPool` — `internal`, not visible to importers | `Internal/` — see §13 |

So when a spec says `counter = LiveCounter.create(5)` and passes it to `set`, that's the **value
type** (`LiveCounter.create(initialCount: 5)`). When a spec says "the resolved value is an
`InternalLiveCounter` with `.data == 5`", that's the **internal graph node** (§13). When a spec
navigates `root.get("counter").value()`, that's the **public view** (`PathObject`).

---

## 2. Entry point & channel access <a id="2-entry-point"></a>

| Spec / ably-js | ably-cocoa (Swift) |
|---|---|
| `channel.object` (objects entry point) | `channel.object` — a **property** on `ARTRealtimeChannel` of type `any RealtimeObject` (`RTL27`). |
| `root = AWAIT channel.object.get()` | `let root = try await channel.object.get()` — `async throws(ARTErrorInfo)`, returns `any LiveMapPathObject` (always a map view, per `RTTS6d`/`RTO23f`). |
| `channel.object.get<MyType>()` (ably-js generic) | **No generic.** The root is always `any LiveMapPathObject`; narrow downstream with the `as*` views (§4). Drop the type parameter entirely. |
| Channel needs object modes | `let options = ARTRealtimeChannelOptions(); options.modes = [.objectPublish, .objectSubscribe]; let channel = realtime.channels.get(name, options: options)` |

Accessing `channel.object` without the `LiveObjects` plugin in `ARTClientOptions.plugins` is a
programmer error (traps). The exact wiring is
`options.plugins = [.liveObjects: AblyLiveObjects.Plugin.self]` plus `import AblyLiveObjects` — on
the integration tier it is packaged as `objectsClientOptions(key:useBinaryProtocol:)` in
`Test/UTS/integration/standard/objects/helpers/ObjectsIntegrationHelpers.swift`; **use that
builder, don't hand-wire the plugin per test**.

---

## 3. Async: Promise / await → Swift `try await` (typed throws) <a id="3-async"></a>

Every spec `AWAIT`/Promise-returning call is a Swift `async throws(ARTErrorInfo)` method — no
future type to unwrap, and the thrown error is **already** an `ARTErrorInfo` (typed throws):

| Spec / ably-js | ably-cocoa |
|---|---|
| `AWAIT channel.object.get()` | `try await channel.object.get()` → `any LiveMapPathObject` |
| `AWAIT pathObj.set(k, v)` / `.remove(k)` | `try await mapView.set(key: k, value: v)` / `.remove(key: k)` → `Void` |
| `AWAIT counterObj.increment(n)` / `.decrement(n)` | `try await counterView.increment(amount: n)` / `.decrement(amount: n)` → `Void` |
| `AWAIT instance.set(...)` etc. | `try await` on the matching `LiveMapInstance` / `LiveCounterInstance` method |

Subscriptions are **not** async — `subscribe(...)` returns synchronously (but `throws`, §8).
Path-resolving reads (`exists()`, `type()`, `value()`, `entries()`, …) are synchronous throwing
**methods** — the `try` is for the `RTO25` access-precondition check, not for I/O.

**Deferred awaits (`x_future = op()` … `AWAIT x_future`).** `realtime_object.md` repeatedly starts
an operation, does something else (e.g. delivers a mock message), *then* awaits — including
`AWAIT inc_future FAILS WITH error`. Swift has no bare future: wrap the operation in a `Task` at
the "start" line and await its `value` at the `AWAIT` line. `Task`'s error type is untyped, so
re-narrow to `ARTErrorInfo` when asserting a failure:

```text
# spec
get_future = channel.object.get()
mock_ws.send_to_client(...)            # unblocks the get
root = AWAIT get_future
```
```swift
let getTask = Task { try await channel.object.get() }
mockWs.sendToClient(...)
let root = try await getTask.value
// failure form: AWAIT inc_future FAILS WITH error (code N)
do {
    _ = try await incTask.value
    Issue.record("expected the deferred operation to fail")
} catch {
    #expect(try #require(error as? ARTErrorInfo).code == N)   // Task erases the typed throw
}
```

---

## 4. Dynamic `PathObject` → typed `PathObject` views <a id="4-pathobject"></a>

In the spec/ably-js a `PathObject` is polymorphic: `get`, `at`, `value`, `set`, `increment`,
`entries`… all hang off the one object. In ably-cocoa the base `PathObject` protocol exposes
**only** the type-agnostic members; everything type-specific lives on a view protocol you reach via
an `as*` refinement. There are exactly **three** views (not the eight the spec's typed variant
sketches): map, counter, and one consolidated primitive view.

**Base `PathObject`** — always available:

| Spec / ably-js | ably-cocoa |
|---|---|
| `pathObj.path()` | `pathObj.path` — a **property** (`String`; the root's is `""`) |
| `pathObj.instance()` | `try pathObj.instance()` → `Instance?` (nil when resolution fails or the value is a primitive — note this is narrower than ably-js/`RTPO8f`; check the Swift doc comment when a spec wraps a primitive) |
| `pathObj.compactJson()` | `try pathObj.compactJson()` → `JSONValue?` |
| `pathObj.compact()` | **Not implemented in ably-cocoa** (`RTTS3f`: typed SDKs need not implement `compact`). Use `compactJson()`; if a spec genuinely needs the non-JSON `compact()` shape, that's a deviation — flag it. |
| `pathObj.subscribe(listener[, opts])` | `try pathObj.subscribe(options:listener:)` → `any Subscription` (§8) |
| *(typed-SDK addition)* exists check | `try pathObj.exists()` → `Bool` (`RTTS4a`) |
| `pathObj.getType()` | `try pathObj.type()` → `ValueType?` — nil when nothing resolves (§10) |
| — view refinements — | `asLiveMap()`, `asLiveCounter()`, `asPrimitive()` — pure type refinements, **never throw**, don't resolve the path (`RTTS5`) |

**View casts never throw** (`RTTS5d`) — they only re-wrap. A wrong cast surfaces later: read ops on
the wrong-typed view return `nil`/empty; write ops throw (§12). So
`try root.get(key: "k").asLiveCounter().value()` returns `nil` if `k` isn't a counter, rather than
throwing.

**Map-only members** — require `asLiveMap()` → `any LiveMapPathObject`:

| Spec / ably-js (on a `PathObject`) | ably-cocoa |
|---|---|
| `pathObj.get(key)` | `mapView.get(key: key)` → `any PathObject` (non-resolving navigation) |
| `pathObj.at("a.b.c")` | `mapView.at(path: "a.b.c")` → `any PathObject` (non-resolving) |
| `pathObj.entries()` | `try mapView.entries()` → `[(key: String, value: any PathObject)]` |
| `pathObj.keys()` / `.values()` | `try mapView.keys()` → `[String]` / `try mapView.values()` → `[any PathObject]` |
| `pathObj.size()` | `try mapView.size()` → `Int?` (nil off-map) |
| `pathObj.set(key, value)` | `try await mapView.set(key: key, value: <LiveMapValue>)` (§6, §7) |
| `pathObj.remove(key)` | `try await mapView.remove(key: key)` |

> The **root** is already an `any LiveMapPathObject` (from `channel.object.get()`), so
> `root.get(key:)` / `root.set(key:value:)` need no cast — only deeper, freshly-navigated
> `PathObject`s do.

**Iterating & membership.** `entries()` returns an array of labelled tuples; `keys()` / `values()`
return arrays. The spec's tuple-destructuring loops and `IN` membership map directly:

```text
# spec
FOR [key, pathObj] IN root.entries(): …
ASSERT "name" IN root.keys()
keys = list(root.keys())
```
```swift
for (key, pathObj) in try root.entries() { … }
#expect(try root.keys().contains("name"))
let keys = try root.keys()                      // already an Array — no materialisation step
```

These live on `LiveMapPathObject`, so a *navigated* node needs `asLiveMap()` first
(`try root.get(key: "score").asLiveMap().entries()`); `root` itself doesn't.

**Counter-only members** — require `asLiveCounter()` → `any LiveCounterPathObject`:

| Spec / ably-js | ably-cocoa |
|---|---|
| `pathObj.value()` *(when it's a counter)* | `try counterView.value()` → `Double?` (counter value, else nil) |
| `pathObj.increment([n])` | `try await counterView.increment()` / `.increment(amount: n)` |
| `pathObj.decrement([n])` | `try await counterView.decrement()` / `.decrement(amount: n)` |

**Primitive value reads — the consolidation to know.** The spec's typed-SDK variant defines
six primitive sub-types (`NumberPathObject`, `StringPathObject`, …); ably-cocoa **collapses them
into one** `PrimitivePathObject` whose `value()` returns a `Primitive?` enum you pattern-match or
read via convenience getters (documented divergence from `RTTS6c`; the six-way split appears
nowhere in this SDK):

| Spec resolves to | ably-cocoa |
|---|---|
| number | `try node.asPrimitive().value()?.numberValue` → `Double?` |
| string | `try node.asPrimitive().value()?.stringValue` → `String?` |
| boolean | `try node.asPrimitive().value()?.boolValue` → `Bool?` |
| binary | `try node.asPrimitive().value()?.dataValue` → `Data?` |
| JSON object | `try node.asPrimitive().value()?.jsonObjectValue` → `[String: JSONValue]?` |
| JSON array | `try node.asPrimitive().value()?.jsonArrayValue` → `[JSONValue]?` |

So a spec's `pathObj.asNumber().value()` becomes `pathObj.asPrimitive().value()?.numberValue`, and
a spec's `pathObj.asString()` *cast on its own* has no Swift counterpart — fold it into the
`asPrimitive()` read. The getters are stricter the same way the spec's typed accessors are: each
returns `nil` unless the primitive is exactly that case.

> **Counter vs number.** The dynamic `PathObject#value` (`RTPO7`) returns "the resolved counter
> value *or* any primitive". Translate "ASSERT pathObj.value() == 5" against a **counter** as
> `#expect(try root.get(key: "c").asLiveCounter().value() == 5)`, not via `asPrimitive()`.
>
> **Numbers are just `Double`.** Counter `value()` is `Double?`, `Primitive.number` carries
> `Double`, and `size()` is `Int?` — Swift literals convert, so `== 110` and `size() == 7` work
> as written, no numeric-suffix normalisation needed. A spec `size() == null` (called on a
> non-map) is `#expect(try node.asLiveMap().size() == nil)` — the cast doesn't throw and `size()`
> returns nil off-map.
>
> **Dynamic `value()` reads in `poll_until` conditions (integration tier).** `pollUntil` closures
> are non-throwing, so the typed reads above get wrapped in `try?` — and SE-0230 **flattens** the
> nested optional (`try? node.asPrimitive().value()` yields `Primitive?`, not `Primitive??`; a
> further `?.` chain on the `guard let`-unwrapped value is a compile error). Don't inline the
> `try?`: use the packaged non-throwing readers in
> `Test/UTS/integration/standard/objects/helpers/ObjectsIntegrationHelpers.swift` —
> `counterValue(at:)` / `stringValue(at:)` / `numberValue(at:)`. They return `nil` when the path
> doesn't resolve or resolves to a different type, which is also how the spec's `value() == null`
> (the tombstoned/absent case, `RTLM5d2h`) is asserted. A thrown `RTO25` precondition error also
> reads as `nil` there — fine on the integration tier, which only reads on ATTACHED channels.

**Path strings & dot-escaping (`RTPO4`/`RTPO4b`/`RTPO6`).** `path` is a dot-delimited `String`
property; the root's is `""`. A literal dot *inside* a segment is escaped as `\.`, and `at(path:)`
parses `\.` back — so `path` round-trips. Mind Swift's own backslash escaping (`"a\\.b.c"` is the
string `a\.b.c`):

```text
# spec                                     # ably-cocoa (Swift)
ASSERT root.path() == ""                    #expect(root.path == "")
ASSERT root.get("a").get("b").path()        #expect(root.get(key: "a").asLiveMap().get(key: "b").path == "a.b")
       == "a.b"
po = root.at("a\.b.c")                      let po = root.at(path: "a\\.b.c")     // segments ["a.b", "c"]
ASSERT po.path() == "a\.b.c"                #expect(po.path == "a\\.b.c")
```

---

## 5. Dynamic `Instance` → the `Instance` enum <a id="5-instance"></a>

**Structural divergence from ably-js and from the spec's typed variant:** `Instance` is a Swift
**enum** with three
cases carrying the typed payload — there are no `as*` casts and no throwing-cast mismatch path
(`RTTS9d` is unrepresentable by construction). Discriminate by `switch` / `guard case`:

```swift
let instance = try #require(try root.get(key: "game").instance())
guard case let .liveMap(map) = instance else { Issue.record("expected a map instance"); return }
```

> **`Instance` has no convenience getters.** Unlike `LiveMapValue` (which offers `liveCounterValue`
> etc.), the `Instance` enum exposes only its cases — extracting a payload (e.g. for a spec's
> `pathObj.instance().id`) always needs the `guard case` above. For the recurring counter-id read
> the integration tier packages it as `counterInstanceId(at:)` in
> `Test/UTS/integration/standard/objects/helpers/ObjectsIntegrationHelpers.swift` (uses
> `try #require` + `guard case`, stopping the test on a mismatch).

**On the enum itself** (`Instance`):

| Spec / ably-js | ably-cocoa |
|---|---|
| `instance.getType()` | `instance.type` — non-optional `ValueType` (`RTTS8`), O(1) property |
| `instance.compactJson()` | `try instance.compactJson()` → `JSONValue` (**non-optional**, `RTINS11c`) |
| `instance.compact()` | **Not implemented** (`RTTS7d`, same as `PathObject`). Use `compactJson()`; flag a deviation if a spec needs `compact()`. |
| `instance.asLiveMap()` / `.asLiveCounter()` / throwing casts | **No casts.** `switch instance { case let .liveMap(map): … }` — a spec case asserting "cast on wrong type throws" is not expressible (the mismatch is a compile-time impossibility); note it as a deviation, don't force it. |

**`LiveMapInstance`** (payload of `.liveMap`):

| Spec / ably-js | ably-cocoa |
|---|---|
| `instance.id` | `map.id` → `String` (non-optional, `RTINS3`) |
| `instance.get(key)` | `try map.get(key: key)` → `Instance?` |
| `instance.entries()` / `.keys()` / `.values()` | `try map.entries()` → `[(key: String, value: Instance)]` / `try map.keys()` → `[String]` / `try map.values()` → `[Instance]` |
| `instance.size()` | `try map.size` → `Int` (**throwing property**, non-optional — the instance is already resolved; `throws` only for the `RTO25` precondition) |
| `instance.set(key, value)` / `.remove(key)` | `try await map.set(key:value:)` / `.remove(key:)` |
| `instance.subscribe(listener)` | `try map.subscribe(listener:)` → `any Subscription` |
| `instance.compactJson()` | `try map.compactJson()` → `JSONValue` |

**`LiveCounterInstance`** (payload of `.liveCounter`):

| Spec / ably-js | ably-cocoa |
|---|---|
| `instance.id` | `counter.id` → `String` |
| `instance.value()` | `try counter.value` → `Double` (**throwing property**, non-optional, `RTTS10b`) |
| `instance.increment([n])` / `.decrement([n])` | `try await counter.increment()` / `.increment(amount: n)` / `.decrement()` / `.decrement(amount: n)` |
| `instance.subscribe(listener)` | `try counter.subscribe(listener:)` → `any Subscription` |

**`PrimitiveInstance`** (payload of `.primitive`) is **read-only** — `try prim.value` → `Primitive`
(non-optional throwing property), `prim.type` (the *specific* primitive `ValueType`, e.g.
`.string`), `try prim.compactJson()`. No `id`, no `get`/`set`, no `subscribe` — one consolidated
type instead of the spec's six (`RTTS10c` divergence, same rationale as §4).

---

## 6. Creation value types & the `LiveMapValue` union <a id="6-value-types"></a>

ably-cocoa can't accept "any JS value" into `set`, so writes take the `LiveMapValue` enum
(`.primitive(Primitive)` / `.liveMap(LiveMap)` / `.liveCounter(LiveCounter)`) — but **literals need
no wrapper at all**: `LiveMapValue` conforms to
`ExpressibleBy{String,Integer,Float,Boolean,Array,Dictionary}Literal`.

| Spec / ably-js | ably-cocoa |
|---|---|
| `LiveCounter.create()` | `LiveCounter.create()` (initial count 0) |
| `LiveCounter.create(5)` | `LiveCounter.create(initialCount: 5)` |
| `LiveMap.create()` | `LiveMap.create()` |
| `LiveMap.create({ a: 1, b: "x" })` | `LiveMap.create(entries: ["a": 1, "b": "x"])` — entries are `[String: LiveMapValue]`, literals convert |
| a raw string/number/bool/JSON into `set` | pass the literal directly: `set(key: "name", value: "alice")`, `set(key: "n", value: 42)`, `set(key: "cfg", value: ["depth": 2])` |
| a raw **binary** value into `set` | no literal form — `set(key: "blob", value: .primitive(.data(someData)))` |
| a non-literal Swift value (e.g. a `String` variable) | `.primitive(.string(s))` / `.primitive(.number(d))` etc. (or construct the `Primitive` and wrap) |
| creation value into `set` | `.liveCounter(.create(initialCount: 5))` / `.liveMap(.create(entries: …))` |

Inspect a constructed `LiveMapValue` with its convenience getters (`stringValue`, `numberValue`,
`boolValue`, `dataValue`, `jsonObjectValue`, `jsonArrayValue`, `liveMapValue: LiveMap?`,
`liveCounterValue: LiveCounter?`) when a spec asserts on a value's contents.

> **Type-safety turns several "invalid input" spec cases into compile errors, not runtime
> assertions.** Where a spec feeds a deliberately wrong type and expects an `ErrorInfo`, the Swift
> signatures reject it at compile time, so the test isn't expressible — note it as a deviation
> rather than forcing it:
> - Passing a **graph object / public view** (`PathObject`, `Instance`, a live object) as a map
>   value (`RTLMV4c1`, runtime `40013` in the dynamic API) — blocked by the `LiveMapValue` enum.
> - **Wrong-typed `create` args**, e.g. `LiveCounter.create("not_a_number")` (spec expects
>   `40003`) — blocked by `create(initialCount: Double)`; `LiveMap.create(entries:)` likewise
>   takes `[String: LiveMapValue]`, so non-`Dict` / non-`String`-key / unsupported-value entry
>   cases (`RTLMV4a`/`b`/`c`) can't be constructed either.
>
> Validation cases on *values the type system still allows* (e.g. NaN / out-of-range `Double`)
> remain real runtime assertions — only the cases the signature outright forbids become deviations.

---

## 7. Mutations (set / remove / increment / decrement) <a id="7-mutations"></a>

Putting §4 + §6 together — the canonical write translations:

```text
# spec
AWAIT root.set("count", LiveCounter.create(0))
AWAIT root.get("count").increment(5)
AWAIT root.set("name", "alice")
AWAIT root.remove("name")
```
```swift
// ably-cocoa (root is `any LiveMapPathObject`)
try await root.set(key: "count", value: .liveCounter(.create()))
try await root.get(key: "count").asLiveCounter().increment(amount: 5)
try await root.set(key: "name", value: "alice")
try await root.remove(key: "name")
```

- `set` / `remove` live on `LiveMapPathObject` (or `LiveMapInstance`); navigate + `asLiveMap()`
  first unless you're on the root or an already-typed map view.
- `increment` / `decrement` live on `LiveCounterPathObject` (or `LiveCounterInstance`);
  `asLiveCounter()` first.
- Default-amount forms exist: `increment()` ≡ `increment(amount: 1)`, `decrement()` ≡
  `decrement(amount: 1)`.

### Wrong-type write failures still go *through* the cast

A common spec shape is a write on the wrong kind of object, expecting a runtime error — e.g.
`AWAIT root.increment(5) FAILS WITH error` (increment on a map) or `counter.set("k", v) FAILS WITH
error`. In the dynamic API every method exists on every `PathObject`, so the call is expressible
and throws at runtime. In ably-cocoa the typed view **doesn't have that method at all**
(`LiveMapPathObject` has no `increment`; `LiveCounterPathObject` has no `set`), so calling it
directly is a *compile* error — not the runtime failure the spec is testing.

To translate these, cast to the view whose write method you need (the `PathObject` cast never
throws, `RTTS5d`), then assert the **operation** throws — that's where the `92007` surfaces:

```text
# spec: increment on a map fails
AWAIT root.increment(5) FAILS WITH error   # code 92007
```
```swift
do {
    try await root.asLiveCounter().increment(amount: 5)
    Issue.record("expected increment on a map to throw")
} catch {
    #expect(error.code == 92007)    // typed throws: `error` is already ARTErrorInfo
}
```

So "can't call increment on a map" is **not** "not expressible" — it's
`asLiveCounter().increment(...)` plus an assertion on the throw. (Contrast §6: invalid *value* /
*argument-type* cases genuinely aren't expressible, because the enum/`create` signatures reject
them at compile time. Contrast also §5: a wrong `Instance` **cast** is unrepresentable — but a
wrong-type *write* through a path view stays translatable via this pattern.)

---

## 8. Subscriptions, listeners & events <a id="8-subscriptions"></a>

ably-js passes a closure and gets back a `Subscription` with `.unsubscribe()`. ably-cocoa is the
same shape — closures, no listener interfaces — plus an `AsyncStream` variant:

| Spec / ably-js | ably-cocoa |
|---|---|
| `sub = pathObj.subscribe((event) => { … })` | `let sub = try pathObj.subscribe { event in … }` |
| `pathObj.subscribe(listener, { depth: 2 })` | `try pathObj.subscribe(options: .init(depth: 2)) { event in … }` (nil options = default) |
| `sub = instance.subscribe((event) => { … })` | `let sub = try mapOrCounterInstance.subscribe { event in … }` (`InstanceSubscriptionEvent`) |
| `sub.unsubscribe()` | `sub.unsubscribe()` (idempotent, `SUB2b`) |
| `event.object` | `event.object` — `any PathObject` (path sub) / `Instance` (instance sub) |
| `event.message` | `event.message` → `ObjectMessage?` (§11) |
| — Swift-only alternative — | `for await event in try pathObj.events() { … }` / `instance payloads' events()` — an `AsyncStream` that unsubscribes on stream termination. Prefer the closure form when translating (it matches the spec's shape 1:1); the stream form is fine where a spec loops over events. |

Callback typealiases: `PathObjectSubscriptionCallback = @Sendable (PathObjectSubscriptionEvent) ->
Void`, `InstanceSubscriptionCallback = @Sendable (InstanceSubscriptionEvent) -> Void`. Both events
carry only `object` + `message` — there is **no per-key diff** on the public event (see the
`LiveObjectUpdate` note below). Because the callbacks are `@Sendable`, collect results with the UTS
harness's `Captured<T>` (see the main skill's Captured section), not a bare `var`.

`subscribe` **throws** (`RTO25` precondition; also `40003` for a non-positive `depth`,
`RTPO19c1`) — so `try` it, and translate a `FAILS WITH` on subscribe as a do/catch (§12).

> **`LiveObjectUpdate` is not the public event.** `live_object_subscribe.md` cites the internal
> `RTLO4b` `LiveObjectUpdate` (fields `update` / `noop` / `objectMessage` / `tombstone`), but it
> subscribes through the *public* `instance.subscribe(...)`, whose Swift event is
> `InstanceSubscriptionEvent` — only `object` + `message`, **no diff/`noop`/`tombstone`
> accessors**. So "listener fired N times" and "returns a `Subscription`" translate directly, but
> any assertion on the `LiveObjectUpdate` *diff* fields is internal (§13) — adapt or skip with a
> deviation.

---

## 9. Sync-state events (`object.on('synced')`) <a id="9-sync-state"></a>

The ably-js string-event API becomes an enum + closure on `RealtimeObject` (`RTO18`). Note the UTS
pseudocode writes the events as **bare constants**, not strings —
`channel.object.on(SYNCED, () => events.append("SYNCED"))` (`realtime_object.md`):

| Spec / ably-js | ably-cocoa |
|---|---|
| `channel.object.on(SYNCED, cb)` / ably-js `on('synced', cb)` | `let sub = channel.object.on(event: .synced) { … }` → `any StatusSubscription` |
| `channel.object.on(SYNCING, cb)` / `on('syncing', cb)` | `channel.object.on(event: .syncing) { … }` |
| `channel.object.off(cb)` | `sub.off()` — deregistration is **per-subscription** (`RTO18f`); there is no `off(listener)` |
| remove all (`offAll()`) | **No `offAll()` in ably-cocoa.** Call `off()` on each retained `StatusSubscription`; if a spec's assertion depends on a true remove-all, flag a deviation. |

`ObjectsEvent` cases: `.syncing`, `.synced`. The `on` callback takes no payload
(`@Sendable () -> Void`). Note `on(event:callback:)` does **not** throw, unlike `subscribe` (§8).

---

## 10. `ValueType` & type discrimination <a id="10-valuetype"></a>

ably-js uses string-literal type tags; ably-cocoa has `enum ValueType` (`RTTS2`):

| Spec value category | `ValueType` case |
|---|---|
| string / number / boolean / binary | `.string` / `.number` / `.boolean` / `.binary` |
| JSON object / JSON array | `.jsonObject` / `.jsonArray` |
| live map / live counter | `.liveMap` / `.liveCounter` |
| present but unrecognised | `.unknown` |

`try pathObj.type()` returns `ValueType?` — nil when nothing resolves (distinct from `.unknown`);
`instance.type` is non-optional. Use `type()` for "what is it" assertions, then the matching `as*`
view (path) or `case` (instance) to read the value. Translate string tags mechanically:
`"LiveMap"`→`.liveMap`, `"number"`→`.number`, etc.

---

## 11. Message / operation types <a id="11-messages"></a>

The spec's `PublicAPI::ObjectMessage` / `PublicAPI::ObjectOperation` (the `PAOM*` / `PAOOP*` types,
delivered to subscription listeners) map to ably-cocoa **structs with plain `var` properties**
(`Path Based API/Public/PublicObjectMessage.swift`). The `PublicAPI::` prefix is dropped — they are
exposed as `ObjectMessage` / `ObjectOperation` (their internal wire namesakes live under the
`ProtocolTypes` namespace and are invisible to importers).

**The Swift structs have public
memberwise initializers** — a spec that constructs an expected message for comparison can build one
directly and use `==` (everything here is `Equatable`). What ably-cocoa does *not* expose is the
`PAOM3`/`PAOOP3` construction-from-wire (`fromObjectMessage` / `fromObjectOperation`) — that
conversion is internal, so `public_object_message.md`'s from-wire cases need internal access (§13).

`ObjectMessage` properties: `id: String?`, `clientId: String?`, `connectionId: String?`,
`timestamp: Date?`, `channel: String`, `operation: ObjectOperation`, `serial: String?`,
`serialTimestamp: Date?`, `siteCode: String?`, `extras: [String: JSONValue]?`.
**Timestamps are `Date`, not epoch millis** — a spec's numeric timestamp `N` compares as
`Date(timeIntervalSince1970: N / 1000)` (or assert on
`timestamp?.timeIntervalSince1970` × 1000).

`ObjectOperation`: `action: ObjectOperationAction`, `objectId: String`, and optional payloads —
`mapCreate`, `mapSet`, `mapRemove`, `counterCreate`, `counterInc`, `objectDelete`, `mapClear` —
exactly one non-nil, matching the action.

**The spec accesses these as dotted property chains and compares `action` to a *string literal*;
ably-cocoa uses the same property chains but an *enum case*:**

```text
# spec
ASSERT msg.operation.action == "MAP_SET"
ASSERT msg.operation.mapSet.key == "name"
ASSERT msg.operation.mapSet.value.string == "blue"
ASSERT msg.operation.counterInc.number == 42
ASSERT msg.operation.mapCreate == null
```
```swift
let op = msg.operation
#expect(op.action == .mapSet)                 // string "MAP_SET" -> enum case
#expect(op.mapSet?.key == "name")
#expect(op.mapSet?.value.string == "blue")    // ObjectData.string
#expect(op.counterInc?.number == 42)          // Double; literal converts
#expect(op.mapCreate == nil)
```

String action tags map SCREAMING_SNAKE → lowerCamel: `"MAP_SET"`→`.mapSet`,
`"COUNTER_INC"`→`.counterInc`, `"OBJECT_DELETE"`→`.objectDelete`, `"MAP_CLEAR"`→`.mapClear`, etc.
Same rule for semantics (`"lww"`→`.lww`) and value types (§10).

| Spec type | ably-cocoa | Notable members |
|---|---|---|
| `ObjectOperationAction` | `enum ObjectOperationAction` | `.mapCreate, .mapSet, .mapRemove, .counterCreate, .counterInc, .objectDelete, .mapClear` — **no `.unknown` case**; a spec asserting an `UNKNOWN` action is a deviation |
| `MapSet` | `struct MapSet` | `key: String`, `value: ObjectData` |
| `MapRemove` | `struct MapRemove` | `key: String` |
| `MapCreate` | `struct MapCreate` | `semantics: ObjectsMapSemantics`, `entries: [String: ObjectsMapEntry]` (non-optional) |
| `CounterCreate` | `struct CounterCreate` | `count: Double` |
| `CounterInc` | `struct CounterInc` | `number: Double` |
| `ObjectDelete` / `MapClear` | empty structs | no members (assert non-nil-ness) |
| `ObjectData` (leaf value) | `struct ObjectData` | `objectId: String?`, `encoding: String?`, `boolean: Bool?`, `bytes: Data?`, `number: Double?`, `string: String?`, `json: String?` — **`json` is a JSON-encoded `String`**, not a parsed value; decode before structural assertions |
| `ObjectsMapEntry` | `struct ObjectsMapEntry` | `tombstone: Bool?`, `timeserial: String?`, `serialTimestamp: Date?`, `data: ObjectData?` |
| map semantics | `enum ObjectsMapSemantics` | `.lww` only — **no `.unknown`** (deviation if a spec needs it) |

> Note `PublicAPI::ObjectOperation` carries only `mapCreate`/`counterCreate` (the `*WithObjectId`
> outbound variants are resolved back to their `MapCreate`/`CounterCreate` forms, `PAOOP1`). Don't
> expect a `mapCreateWithObjectId` on the public type — those exist only on the internal
> `ProtocolTypes` wire types.

---

## 12. Errors & error codes <a id="12-errors"></a>

Spec assertions like `FAILS WITH error code 92007` map to `ARTErrorInfo`. Everything in this API
uses **typed throws** (`throws(ARTErrorInfo)`), so in a `catch` block `error` *is* the
`ARTErrorInfo` — no casting, no future unwrapping:

```swift
do {
    _ = try await channel.object.get()
    Issue.record("expected get() to throw")
} catch {
    #expect(error.code == 40024)
}
```

| Spec failure | ably-cocoa |
|---|---|
| async op rejects with `ErrorInfo` code N | `try await` throws `ARTErrorInfo`; do/catch and assert `error.code == N` |
| wrong write method for the type (e.g. `increment` on a map, `set` on a counter) | the typed view lacks the method — cast first (`asLiveCounter()` / `asLiveMap()`, never throws, `RTTS5d`), then the **operation** throws `92007`. See §7 |
| `Instance` cast on wrong type (`RTTS9d`) | **not expressible** — `Instance` is an enum; the mismatch case doesn't exist. Deviation. |
| `PathObject` `as*` cast on wrong type | **never throws** (`RTTS5d`) — failure shows up on the subsequent read (nil) or write (throws) |
| invalid value into `set` (graph object / view; `RTLMV4c1`, `40013`) | not expressible in the typed `set` — deviation (§6) |
| non-positive subscription `depth` (`RTPO19c1`) | `subscribe(options: .init(depth: 0))` — the `subscribe` call throws `40003` |
| write where path doesn't resolve | `92005` |
| write where value isn't the required type | `92007` |
| `get()` / op when channel lacks the object mode (`RTO23a`/`RTO2a2`) | `40024` |
| access methods when channel is DETACHED or FAILED (`RTO25b`) | `90001` |
| `get()` when channel is FAILED (`RTO23e`/`RTL33c`) | `90001`. **But `get()` on a DETACHED channel does *not* throw** — ensure-active-channel re-attaches and `get()` resolves (`RTO23e`/`RTL33b`); only the access methods gate on DETACHED |
| channel enters DETACHED/SUSPENDED/FAILED while awaiting SYNCED (`RTO20e`/`RTO23c`) | `92008` |
| write while `echoMessages` is false (`RTO26c`) | `40000` |

Assert the code as a plain `Int` — `#expect(error.code == 90001)` — matching the spec's
`error.code == 90001`; error codes are int literals, not enums (unlike the action / semantics /
value-type tags).

> **Never write `error as? ARTErrorInfo` in a typed-throws `catch`.** The catch binding is already
> `ARTErrorInfo` there, so the cast is an "always succeeds" compiler warning — and the LiveObjects
> CI build treats warnings as errors, so it FAILS the SPM job even though a local
> `swift build --build-tests` only warns (check build output for warnings, not just the tail). The
> re-narrowing cast is correct in exactly one place: the `catch` of a deferred `try await task.value`
> (§3 — `Task` erases the typed throw). The `90000` a spec injects via a mocked `ERROR`/`DETACHED` `ProtocolMessage` is
the channel-level error, not an objects code — it's what drives the channel into the state that
makes the objects call fail.

**Nested cause (`error.cause.code`).** A spec's nested `error.cause.code` (e.g. `RTO20e`:
top-level `92008` plus cause `90000`): `ARTErrorInfo` has no public typed `cause` accessor —
inspect the underlying `NSError` chain (`error.userInfo[NSUnderlyingErrorKey]`) and verify what the
implementation actually populates **at translation time** (the implementation now exists — check
what it emits rather than assuming). If the cause isn't reachable, assert the top-level code
and flag the cause assertion as a deviation.

---

## 13. Internal-graph types (unit specs) — important caveats <a id="13-internal-graph"></a>

Several **unit** specs assert on the **internal CRDT graph**, not the public API:
`InternalLiveCounter.data`, `InternalLiveMap.siteTimeserials`, `ObjectsPool.syncState`,
`LiveObjectUpdate`, `applyOperation(msg, source)`, object-id generation (`RTO14`), the
`*CreateWithObjectId` wire variants, etc. Specs that are wholly or mostly internal:

- `objects_pool.md`, `parent_references.md`, `object_id.md` — pool sync state, the reverse
  parent-reference graph, object-id generation: entirely internal.
- the internal-state assertions in `internal_live_counter*.md` / `internal_live_map*.md` (`.data`,
  `.siteTimeserials`, `.createOperationIsMerged`, `.isTombstone`, `applyOperation`, `replaceData`)
  — internal; their public-facing read/write counterparts are the `path_object*.md` /
  `instance.md` specs.
- `value_types.md` — the *public* `LiveMap.create` / `LiveCounter.create` surface maps via §6, but
  the evaluation half (`COUNTER_CREATE` / `MAP_CREATE` `ObjectMessage` generation,
  nonce/`initialValue`/`objectId` derivation, the `*WithObjectId` wire forms) is
  internal/wire-level.
- `realtime_object.md` — **mixed**: `get()` (`RTO23`, incl. the `40024`/`90001`/`92008`
  precondition cases) is public and maps via §2/§12, but `publish` / `publishAndApply`
  (`RTO15`/`RTO20`, marked `internal` in the IDL) and the OBJECT/ACK wire assertions are internal.
- `public_object_message.md` — the public getters map via §11, but the `PAOM3`/`PAOOP3`
  construction-from-wire is internal (`ProtocolTypes.InboundObjectMessage` → public
  `ObjectMessage`); translating it needs the internal access described below.

In ably-cocoa the internal layer lives in the `AblyLiveObjects` module (`Internal/` + `Protocol/`
directories: `InternalDefaultLiveMap`, `InternalDefaultLiveCounter`,
`InternalDefaultRealtimeObjects`, `ObjectsPool`, and the `ProtocolTypes.*` wire types) with
`internal` access — no reflection tricks needed. The objects unit suites live in the shared `UTS`
test target under **`Test/UTS/unit/objects/`** (the standard UTS location; the resolver routes them
there) and reach the internal layer through `@testable` imports:
`@testable import AblyLiveObjects` (the internal types themselves — present in **every** suite)
plus `@testable import AblyLiveObjectsTesting` (the dedicated test-support module — relocated to
`Test/AblyLiveObjectsTesting` — hosting the `testsOnly_*` accessors) **added when a case uses one
of those accessors**; suites that drive internal types directly need only the first import.
(The previously-generated port suites have been removed pending regeneration against the aligned
helpers — only the harness `ObjectsUTSHelpers.swift` currently lives in `Test/UTS/unit/objects/`.)

### Internal-access ladder (unit tier only)

When a unit spec needs to reach an internal accessor, work down this ladder — it is the objects
counterpart of SKILL.md Step 4's `import AblyPubSubDevice.Private` ladder (which stays the rule for core-SDK
modules; it does **not** apply here):

1. The internal symbols are reachable via `@testable import AblyLiveObjects` plus the
   test-support module `@testable import AblyLiveObjectsTesting` — add the latter to the suite
   file if it doesn't import it yet (only suites that use `testsOnly_` accessors do). Use the
   existing accessor.
1a. Internal-graph specs that call an apply/replace operation assert on the **update value
   returned by that internal call** (e.g. the `LiveObjectUpdate` from `testsOnly_applyMapSetOperation`),
   not only on public subscription events — check what the spec's `ASSERT` actually reads before
   reaching for the event-based helpers.
2. **Check first — always.** Before adding ANY test-support code (a `testsOnly_` seam **or** a
   helper/factory/mock), grep the existing module for it:
   `grep -rn "<symbol>" Test/AblyLiveObjectsTesting --include="*.swift"`. If an existing
   `testsOnly_` member or helper/factory/mock covers the need, **reuse it — never duplicate it**.
3. Only if it is missing, **extend the test-support module** (never `Sources/`), by kind:
   - **Internal-access seam** (a missing `testsOnly_` method/property): add it to the matching
     `Test/AblyLiveObjectsTesting/Internals/<Type>+TestsOnly.swift` — extend the existing file for
     that type if present; create a new `Internals/<Type>+TestsOnly.swift` only when no file for
     that type exists. Follow the recipe in the module's `README.md` — a **dumb accessor only**
     (read/write existing internal state, or 1:1 delegation; no computation, branching, or state of
     its own), `testsOnly_` prefix, `@available(macOS 11.0, iOS 14.0, tvOS 14.0, *)`. If the
     backing member is `private`, raise it to `internal` in `Sources/` with the
     `// internal (not private) for AblyLiveObjectsTesting` intent comment. If **more than a
     visibility raise** is needed (stored state, production write hooks), **stop** — that is a
     residual-class seam: check the README's residual allowlist and escalate to the lead dev rather
     than hacking around it in a helper.
   - **Helper/mock/factory**: add it to the matching file under
     `Test/AblyLiveObjectsTesting/Helpers/` — extend the existing file if one fits (message/state
     factories into `TestFactories.swift`, spec-pool vocabulary/builders into
     `StandardTestPool.swift`, mock behaviour into the relevant `Mock*.swift`); create a new
     `Helpers/` file only when nothing fits.
   - **Placement boundary — shared module vs port harness.** `Test/AblyLiveObjectsTesting` is for
     code consumed by **both** test targets (the native `AblyLiveObjectsTests` suite and `UTS`).
     A helper needed **only by the UTS port suites** (an `ObjectsUTS*`-style double or fixture)
     belongs in `Test/UTS/unit/objects/ObjectsUTSHelpers.swift` instead — do **not** move that
     harness (or add port-only types) into the shared module: it is single-consumer by design and
     imports the `Testing` framework, which the shared non-test module must not.
4. This ladder is for the **unit tier only.** The integration and proxy objects tiers exercise the
   public path-based API exclusively and never touch `AblyLiveObjectsTesting` — see §14 and the
   integration helpers under `Test/UTS/integration/standard/objects/helpers/`.

**One-time wiring** — both prerequisites are now **done**:

1. ✅ **The `UTS` test target depends on `AblyLiveObjects` and `AblyLiveObjectsTesting`.**
   The objects unit ports live in `Test/UTS/unit/objects/` (a flat directory — no per-module subdir)
   and consume the seams via the two `@testable import`s above. The Swift 6 language mode compiles
   the fully `Sendable` LiveObjects API without friction, and every top-level declaration carries the
   standard `@available` annotation.
2. ✅ **The spec helpers are implemented.** Every objects unit spec opens with a synced-channel
   setup and builds messages with `build_*` helpers, all specified in
   `uts/objects/helpers/standard_test_pool.md`. The Swift implementations exist:
   - `Test/AblyLiveObjectsTesting/Helpers/StandardTestPool.swift` — the shared-module mirror of
     the spec helper file: the serial helpers (`SITE_CODE`, `POOL_SERIAL`, `ack_serial`,
     `remote_serial`, `below_ack_serial`) as the `StandardTestPool` constants/functions
     (`siteCode`, `poolSerial`, `ackSerial(msgSerial:i:)`, `remoteSerial(_:)`,
     `belowAckSerial(_:)`) — always call them; never inline a `"t:N"` serial or siteCode
     literal — plus the shared spec-pool `build_*` builders on `TestFactories`
     (`objectDeleteOperationMessage`, the `ObjectData`-taking/`serialTimestamp:`
     `mapSetOperationMessage`/`mapRemoveOperationMessage` overloads) and
     `SyncObjectsPool.testsOnly_fromStates` for pool construction. The rest of the `build_*`
     operation and `*ObjectState` builders live in `Helpers/TestFactories.swift`.
   - `Test/UTS/unit/objects/ObjectsUTSHelpers.swift` — the port-only mock/harness types
     (`ObjectsUTSCoreSDK`, the seeded `InternalRealtimeObjectsProtocol` fixtures, the pool
     delegate, and the event collectors) that stand in for the spec's `setup_synced_channel` /
     `setup_synced_channel_no_ack` on top of the internal machinery.

   **Call these helpers; never hand-roll the mock setup, message JSON, or serial/siteCode strings.**
   Serials compare as strings (RTLM9e) and ad-hoc values silently sort wrong — every serial in a port
   comes from `StandardTestPool` (`poolSerial`, `ackSerial(msgSerial:i:)`, `remoteSerial(_:)`,
   `belowAckSerial(_:)`) and every siteCode from `StandardTestPool.siteCode` or the spec's literal
   remote siteCode (e.g. `"remote"`).

### Harness surface — `Test/UTS/unit/objects/ObjectsUTSHelpers.swift`

The port-only harness. It rides in the `UTS` target alongside the suites — deliberately **not** in
`Test/AblyLiveObjectsTesting/Helpers/` — because it exists purely for these ports: the native
`AblyLiveObjectsTests` suite never uses it (the shared module is reserved for code both test targets
consume), and it imports the `Testing` framework, which the shared non-test module must not. New
port-only doubles/fixtures go here; anything genuinely needed by both suites goes to the shared
module per the §13 ladder. Types and their roles:

| Type | Role | Key members |
|---|---|---|
| `ObjectsUTS` (enum) | Node-construction + blueprint-evaluation + inbound-message builders; the standard-pool seeder | `createInternalQueue()`, `makeCounter(objectID:data:internalQueue:)`, `makeMap(objectID:data:internalQueue:)`, `mapEntry(data:timeserial:)`, `freshPool(internalQueue:)`, `standardPool(internalQueue:prefsBackRef:)`, `evaluationTimestamp`, `evaluate(counter:)` / `evaluate(map:internalQueue:)`, `inboundOperation(_:serial:siteCode:)`, `mapSetMessage`/`counterIncMessage`/`mapClearMessage`/`objectDeleteMessage`/`counterIncNoopMessage`, `counterSyncMessage`/`rootSyncMessage`, `wireMapEntry(data:)` |
| `ObjectsUTSCoreSDK` (`CoreSDK`) | Minimal `CoreSDK`: fixed channel state (so the RTO25/RTO26 access guards pass) + a canned server time | `init(channelState:serverTime:)`, `nosync_fetchServerTime`, `nosync_channelState`, `nosync_objectChannelModes`, `nosync_attach`; publish paths `fatalError` (writes go through the realtime-objects doubles) |
| `ObjectsUTSRealtimeObjects` (`InternalRealtimeObjectsProtocol`) | Realtime-objects double that **captures** the messages passed to `publishAndApply` (the RTO20 write seam) without a real channel | `init(poolDelegate:)`, `setPublishAndApplyHandler(_:)`, `nosync_publishAndApply`, `nosync_objectsPool`, `nosync_pathObjectSubscriptionRegister` |
| `ObjectsUTSSeededRealtimeObjects` (`InternalRealtimeObjectsProtocol`) | Realtime-objects double exposing a **pre-seeded full `ObjectsPool`** (root + nested) for path resolution; auto-captures published messages | `init(pool:internalQueue:)`, `capturedMessages`, `nosync_publishAndApply`, `nosync_objectsPool`, `nosync_pathObjectSubscriptionRegister` |
| `ObjectsUTSPoolDelegate` (`LiveMapObjectsPoolDelegate`) | Pool delegate holding a fixed `objectId → Entry` map so map `get`/`entries` resolve object references | `init(internalQueue:entries:)`, `nosync_objectsPool` |
| `ObjectsUTSEventCollector` (`Sendable`) | Thread-safe `InstanceSubscriptionEvent` collector; `events()` drains its own `.main` callback queue **async** before reading | `listener`, `events() async` |
| `ObjectsUTSInstanceEventCollector` (`@unchecked Sendable`) | Same but read **synchronously** after the engine's `userCallbackQueue` is drained (`queue.sync {}`) — for engine-driven instance-subscribe ports | `listener`, `events` |
| `ObjectsUTSPathEventCollector` (`@unchecked Sendable`) | Thread-safe `PathObjectSubscriptionEvent` collector | `listener`, `events`, `sortedPaths` |
| `ObjectsUTSPublished` (`Sendable`) | Thread-safe holder for the `[OutboundObjectMessage]` a `publishAndApply` handler captures | `set(_:)`, `get()` |

### Spec-helper coverage — `uts/objects/helpers/standard_test_pool.md` → cocoa

Every symbol the standard test pool defines, and its cocoa implementation. The serial vocabulary and
the shared spec-pool builders live in `Test/AblyLiveObjectsTesting/Helpers/StandardTestPool.swift`
(the shared-module mirror of the spec helper file); the remaining builders live in
`Helpers/TestFactories.swift`; the pool/harness stand-ins live in
`Test/UTS/unit/objects/ObjectsUTSHelpers.swift`.

| Spec symbol | cocoa implementation (file · symbol) |
|---|---|
| `SITE_CODE` | `Helpers/StandardTestPool.swift` · `StandardTestPool.siteCode` — spec `siteCode: SITE_CODE` → `siteCode: StandardTestPool.siteCode` |
| `POOL_SERIAL` | `Helpers/StandardTestPool.swift` · `StandardTestPool.poolSerial` — spec `timeserial: POOL_SERIAL` → `timeserial: StandardTestPool.poolSerial` |
| `ack_serial(msgSerial, i)` | `Helpers/StandardTestPool.swift` · `StandardTestPool.ackSerial(msgSerial:i:)` — spec `ack_serial(0, 0)` → `StandardTestPool.ackSerial(msgSerial: 0, i: 0)` (== `"t:1:0"`) |
| `remote_serial(i)` | `Helpers/StandardTestPool.swift` · `StandardTestPool.remoteSerial(_:)` — spec `remote_serial(1)` → `StandardTestPool.remoteSerial(1)` (== `"t:2"`) |
| `below_ack_serial(i)` | `Helpers/StandardTestPool.swift` · `StandardTestPool.belowAckSerial(_:)` — spec `below_ack_serial(9)` → `StandardTestPool.belowAckSerial(9)` (== `"t:0:9"`) |
| `build_counter_inc` | `Helpers/TestFactories.swift` · `TestFactories.counterIncOperationMessage(objectId:number:serial:siteCode:)` (also `ObjectsUTS.counterIncMessage`) |
| `build_map_set` | `Helpers/TestFactories.swift` / `Helpers/StandardTestPool.swift` · `TestFactories.mapSetOperationMessage(objectId:key:value:serial:siteCode:)` — one `value:` label, `String` convenience and `ObjectData` general overloads (also `ObjectsUTS.mapSetMessage(objectId:key:value:serial:siteCode:)`). Spec `build_map_set("root", "name", { string: "Bob" }, remote_serial(0), "remote")` → `TestFactories.mapSetOperationMessage(objectId: "root", key: "name", value: "Bob", serial: StandardTestPool.remoteSerial(0), siteCode: "remote")` |
| `build_map_remove` | `Helpers/TestFactories.swift` / `Helpers/StandardTestPool.swift` · `TestFactories.mapRemoveOperationMessage(…)` (incl. the `serialTimestamp:` overload for RTLM8f) |
| `build_map_clear` | `Helpers/TestFactories.swift` · `TestFactories.mapClearOperationMessage(…)` (also `ObjectsUTS.mapClearMessage`) |
| `build_object_delete` | `Helpers/StandardTestPool.swift` · `TestFactories.objectDeleteOperationMessage(…)` (also `ObjectsUTS.objectDeleteMessage`) |
| `build_counter_create` | `Helpers/TestFactories.swift` · `TestFactories.counterCreateOperationMessage(…)` |
| `build_map_create` | `Helpers/TestFactories.swift` · `TestFactories.mapCreateOperationMessage(…)` |
| `build_object_state` | `Helpers/TestFactories.swift` · `TestFactories.objectState` / `mapObjectState` / `counterObjectState` / `rootObjectState` |
| `build_object_message_with_state` | `Helpers/TestFactories.swift` · `TestFactories.inboundObjectMessage(object:)` (and `mapObjectMessage`/`counterObjectMessage`/`rootObjectMessage`) |
| `build_public_object_message` | `LiveObjects/Sources/…/Protocol/ObjectMessage.swift` · `ProtocolTypes.InboundObjectMessage.toPublicObjectMessage(channelName:)` (the PAOM3 conversion) |
| `STANDARD_POOL_OBJECTS` (the tree) | `ObjectsUTSHelpers.swift` · `ObjectsUTS.standardPool(internalQueue:prefsBackRef:)` (seeds the same tree straight into an `ObjectsPool`). Spec serial baseline: every entry `timeserial: StandardTestPool.poolSerial` (`"t:0"`, the `ObjectsUTS.mapEntry` default), every object `siteTimeserials: ["aaa": StandardTestPool.poolSerial]` — so `remoteSerial(i)` ops win entry-level LWW as the spec intends. `prefsBackRef` is a non-spec cocoa extension (the RTPO14b2 cycle fixture). The spec's message-array form deliberately has no cocoa counterpart (the unit tier consumes the seeded pool; a message-array wrapper is deferred unless a mock-transport tier lands). |
| `assert_unchanged_after_quiescence` | no named helper (deliberate — the specs inline the pattern, zero named uses): capture `before`, drain the collector's dispatch (`ObjectsUTSEventCollector.events()` awaits `.main`; `ObjectsUTSInstanceEventCollector` / `ObjectsUTSPathEventCollector` read after `queue.sync {}`), then `#expect(count == before)`. The drained dispatch must be one the control signal was already enqueued on (the spec's same-dispatch guarantee) — never a bare sleep. |
| `provision_objects_via_rest` (integration only) | `Test/UTS/integration/standard/objects/helpers/ObjectsRestProvisioning.swift` · `provisionObjectsViaRest(apiKey:channelName:operations:)` (§14) |

#### Sanctioned patterns — spec builder shapes cocoa deliberately does not mirror

Three spec-builder conveniences have a documented cocoa pattern instead of a 1:1 helper. Use the
pattern; do not add the missing shorthand:

- **`build_object_state` createOp auto-fill.** The spec builder fills a terse
  `createOp: { counterCreate: {...} }` with the missing `action`/`objectId` (OOP2). Cocoa's
  `createOp:` takes a fully-formed `ObjectOperation`; build it with the create-op factories, which
  set both fields:
  `TestFactories.counterObjectState(objectId: id, createOp: TestFactories.counterCreateOperation(objectId: id, count: 100), count: 0)`
  (map form: `mapObjectState(...createOp: TestFactories.mapCreateOperation(objectId: id, entries: [:]))`).
  There is deliberately no auto-fill shortcut.
- **`build_counter_create` / `build_map_create` payload objects.** The spec passes a
  `counterCreate` / `mapCreate` object; cocoa takes the scalar payload directly —
  `counterCreateOperationMessage(objectId:count:serial:siteCode:)` /
  `mapCreateOperationMessage(objectId:entries:serial:siteCode:)` (semantics is always `.lww`). A
  deliberate simplification, not a gap.
- **Negative-assertion quiescence.** No named helper (the specs inline it, zero named uses): write
  the before/drain/expect triple via the event collectors, per the
  `assert_unchanged_after_quiescence` coverage-table row — the control must ride the same dispatch
  as the message under test (the spec's same-dispatch guarantee); never a sleep.

**Transport-level stand-ins (sanctioned unit-scope infra design — NOT a deviation).** The four spec
helpers that materialise a mock WebSocket transport have **no** cocoa builder — the unit tier drops the
mock transport entirely and seeds the CRDT graph directly, so there is no PROTOCOL frame to build. This is
a deliberate infra-driving choice, **not** an SDK deviation and **not** a mock-capability gap: every
ported case still runs. **Do not record it in `deviations.md`** (SKILL.md Step 6 — infra-driving
differences are explained in a code comment, not the deviations file). Describe it in the suite's
file-header comment instead:

| Spec symbol | cocoa stand-in (file · symbol) · rationale |
|---|---|
| `setup_synced_channel(channel_name)` | `ObjectsUTSHelpers.swift` · `ObjectsUTS.standardPool(…)` + `ObjectsUTSSeededRealtimeObjects` — seed the pool directly; the unit tier has no channel/connection to sync |
| `setup_synced_channel_no_ack(channel_name)` | same direct seeding; ACK timing is modelled by seeding `StandardTestPool.ackSerial(msgSerial:i:)` directly rather than a live ACK frame |
| `build_object_sync_message(channel, channelSerial, objectMessages)` | `SyncObjectsPool.testsOnly_fromStates(_:logger:)` (accumulate states) / `ObjectsUTS.standardPool` (seed the pool); for engine-driven ports, `ObjectsUTS.counterSyncMessage` / `rootSyncMessage` build the inbound OBJECT_SYNC state message applied directly — no OBJECT_SYNC PROTOCOL frame is built |
| `build_ack_message(msgSerial, serials)` | no ACK frame — apply-on-ACK is modelled by seeding `StandardTestPool.ackSerial(msgSerial:i:)` directly; there is no mock transport to ACK |

### Publish-capture recipe (the spec's `capturedObjectMessages` equivalent)

Ported write cases assert on the **outbound** `ObjectMessage`(s) an operation publishes. There is no mock
WebSocket to read a sent frame from; instead capture at the `publishAndApply` seam. Two flavours, both in
`ObjectsUTSHelpers.swift`:

- **`ObjectsUTSRealtimeObjects.setPublishAndApplyHandler(_:)`** (`ObjectsUTSHelpers.swift`) — install a
  handler that receives the outbound `[ProtocolTypes.OutboundObjectMessage]`; store them (e.g. into an
  `ObjectsUTSPublished`) and assert afterwards. Return `.success(())` unless the case asserts a publish
  failure.
- **`ObjectsUTSSeededRealtimeObjects.capturedMessages`** (`ObjectsUTSHelpers.swift`) — the seeded double
  auto-captures the most recent `publishAndApply`'s messages; just read the property after the write. Used
  by the path-object / seeded-pool ports. It retains **only the most recent** publish, so a spec case that
  indexes an *accumulated* array across multiple publishes (`captured_messages[0]`/`[1]`/`[2]` — only
  `objects/unit/RTLM20/set-value-types-0` does this today) reads `capturedMessages[0]` **after each write**
  rather than one array. That read-after-each-write shape is an infra-driving choice, not a deviation —
  note it in a code comment, never in `deviations.md`. (If a future tier needs true accumulation, extend
  the double with a `capturedPublishes: [[OutboundObjectMessage]]` accessor that appends per publish.)

Either is cocoa's equivalent of ably-java's `mockWs.capturedObjectMessages()`. **Note:** the native
`AblyLiveObjects` suite instead uses `MockCoreSDK.setPublishHandler(_:)`
(`Test/AblyLiveObjectsTesting/Helpers/MockCoreSDK.swift`); the port-tier `ObjectsUTSCoreSDK`'s publish paths
deliberately `fatalError`, so writes in the ports go through the realtime-objects doubles above, never
through the CoreSDK.

> **Async-delivery caution.** The engine applies inbound messages **asynchronously** — mock delivery is
> not synchronous. When a later step depends on an applied operation or a subscribe delivery, **await the
> observable effect, not the call**: drain the collector's callback queue (`events() async`, or
> `queue.sync {}` for the engine's own `userCallbackQueue`) before asserting a count, and read a value
> only after the apply has settled. Never assume `apply(...)`/`send_to_client(...)` has taken effect the
> instant it returns.

> **Queue-confinement caution.** The harness's pool/state holders are `DispatchQueueMutex`-backed and
> `dispatchPrecondition`-assert their internal queue — reading `nosync_objectsPool` (or calling any
> `nosync_*` accessor / `nosync_apply`) off that queue **traps at runtime** (a `dispatchPrecondition`
> failure, surfaced as a platform-dependent trap/abort), it doesn't just race. When a port drives an internal node directly (e.g. the `mock_ws.send_to_client` stand-in that
> applies an inbound operation to a seeded node), do the pool read, entry lookup, and
> `nosync_apply(...)` all inside one `internalQueue.ably_syncNoDeadlock { … }` block — mirroring how
> `ObjectsUTSSeededRealtimeObjects`'s own echo does it.

### Objects-unit file template

Mirror the moved suites (e.g. `Test/UTS/unit/objects/ObjectIdTests.swift`,
`InternalLiveCounterTests.swift`). A plain `struct <Stem>Tests` — **no `UTSTestCase` base class**
(that belongs to the core-SDK unit tier); use `@Suite(.serialized) final class <Stem>Tests` only when
the suite genuinely needs serialization. `// UTS:` tag immediately above each `@Test`. Import
`AblyLiveObjects` + `AblyLiveObjectsTesting` `@testable`; add `Ably` / `_AblyPluginSupportPrivate` only
when the case touches `ARTErrorInfo` / plugin-facing types (channel state, modes).

**Method naming — objects unit tier OVERRIDES SKILL.md Step 4's `test_<SPEC>_<description>` rule:**
use bare descriptive camelCase names with no `test_` prefix and no embedded spec point (e.g.
`objectIdIsDeterministicForSameInputs`), matching every existing suite in `Test/UTS/unit/objects/`.
Spec traceability lives entirely in the `// UTS:` tag, not the method name.

**Two suite names collide with native suites (by design).** `ObjectsPoolTests` and
`ParentReferencesTests` also exist as native suites in the `AblyLiveObjectsTests` target. This is
accepted — they live in different targets — so always run objects-unit ports with the
target-qualified filter form, `swift test --filter "UTS.<SuiteName>"`, which disambiguates them.

**Pure-function specs** (no channel/pool/sync interaction — e.g. `object_id.md`): the Step 3
reading list collapses — you only need the §16 symbol mapping and this file template; skip
`ObjectsUTSHelpers.swift` and the pool factories.

**Audit `awaitShortfall` is benign on this tier — expect it on nearly every test.** The Step 7
audit counts only the core-tier infra wait calls (`awaitConnectionState`/`poll`/…), which the
objects unit ports never use: spec `AWAIT op` lines become plain `try await` expressions
(natively-async SDK, §3), and the spec's `AWAIT setup_synced_channel(...)` maps to the
*synchronous* direct-seeding fixture (`ObjectsUTS.standardPool` + the doubles). Both are invisible
to the await counter, so a positive `awaitShortfall` here needs no investigation as long as every
spec `AWAIT` line is visibly accounted for in the code (a `try await`, the fixture builder, or an
event-collector drain). The hard gates (`missingInSwift`/`orphanInSwift`/`duplicateInSwift`,
`assertionShortfall`) apply unchanged.

**Deviations file** (no override — SKILL.md Step 6's shared-file default applies): objects-unit
deviations go in the shared `Test/UTS/deviations.md`, like every other tier, **inserted into the
respective section** of the manual's four-section structure (*UTS Spec Errors* / *Failing Tests* /
*Adapted Tests* / *Mock Infrastructure Limitations*) — never appended at the file end. The entry
format and section semantics come from `writing-derived-tests.md` (already fetched per the "Required
reading — fetch first" list); follow it there rather than duplicating its rules here. Do **not** create
a module-scoped `Test/UTS/unit/objects/deviations.md`. Unit-tier internal-API **shape** differences are
named once in that file's "Shape-deviation vocabulary (objects unit tier)" section (S-1…S-n) and
cited by tag per entry.

```swift
// Derived from the UTS spec `objects/unit/<spec_file>.md`.
//
// <one line: what these ports drive and why (e.g. drive InternalDefaultLiveCounter directly, no channel)>.
//
// Deviations from the UTS spec (only if there are genuine SDK deviations recorded in deviations.md):
// - (D-1) <SDK-behaviour deviation the reader must know before reading the cases; see deviations.md>
// Infra-driving stand-ins (direct seeding, the publishAndApply capture seam, the async ACK echo) are
// NOT deviations — describe them in the "what these ports drive" line above, not here.

import _AblyPluginSupportPrivate      // only if you touch plugin-facing types (channel state/modes)
import AblyPubSubDevice                            // only if you touch ARTErrorInfo / core types
@testable import AblyLiveObjects
@testable import AblyLiveObjectsTesting  // only if the suite uses testsOnly_ accessors
import Foundation
import Testing

struct <Stem>Tests {
    private static let channelName = "test-channel"

    // MARK: - Helpers
    private static func makeCounter(objectID: String, internalQueue: DispatchQueue) -> InternalDefaultLiveCounter {
        InternalDefaultLiveCounter.createZeroValued(
            objectID: objectID,
            logger: TestLogger(),
            internalQueue: internalQueue,
            userCallbackQueue: .main,
            clock: MockSimpleClock(),
        )
    }

    // UTS: objects/unit/<full-spec-id>
    @Test
    func <descriptiveName>() throws {
        // Setup — seed via the harness/factories; never hand-roll serials or message JSON.
        let internalQueue = ObjectsUTS.createInternalQueue()
        let counter = Self.makeCounter(objectID: "counter:1@0", internalQueue: internalQueue)

        // Test Steps — build an inbound op with TestFactories / ObjectsUTS, apply it.
        // Assertions — one #expect / try #require per spec ASSERT.
        #expect(/* … */ true)
    }
}
```

Spec name → ably-cocoa impl (for orientation, not public use): `InternalLiveMap` →
`InternalDefaultLiveMap`, `InternalLiveCounter` → `InternalDefaultLiveCounter`, the public-view
impls are `DefaultLiveMapPathObject` / `DefaultLiveCounterInstance` / … (`Path Based API/Default/`,
now fully implemented), wire forms are `ProtocolTypes.ObjectMessage` / `WireObjectMessage` /
`WireObjectOperation` etc.

> **Runtime status recap (top of doc):** the path-based public surface is **implemented** (the
> skeleton that trapped on every call is gone). Both the internal-layer specs and the public-API specs are
> runnable — pick translate-and-evaluate for either; just check what the spec actually calls so you
> import and assert at the right layer.

---

## 14. Integration-test helpers — REST fixture provisioning <a id="14-integration-helpers"></a>

Some objects **integration** specs (tier `integration/standard`) seed object state over REST
*before* the realtime client connects, via the spec's `## REST Fixture Provisioning` helper
`provision_objects_via_rest` (`standard_test_pool.md`).

**Implemented** at `Test/UTS/integration/standard/objects/helpers/ObjectsRestProvisioning.swift`
(module helpers live in a `helpers/` directory next to the module's suites, not under the
module-agnostic `infra/`; shared client/channel wiring and `value()` read helpers sit alongside in
`ObjectsIntegrationHelpers.swift`):
`provisionObjectsViaRest(apiKey:channelName:operations:) -> [String]` plus the op/value builders
(`mapSetOp`, `mapRemoveOp`, `mapCreateOp`, `counterCreateOp`, `counterIncOp`; `valueString`,
`valueNumber`, `valueBoolean`, `valueBytes`, `valueObjectId`). Two facts the implementation
encodes (hard-won — don't re-derive them):

- **V2 REST format** (OpenAPI is the source of truth): `POST /channels/{channel}/object`
  (**singular**), body is a single operation **or** a bare array (no `messages` wrapper), each op
  named by its payload key (`mapSet` / `mapRemove` / `mapCreate` / `counterInc` / `counterCreate`)
  with an `objectId`/`path` target and optional idempotency `id`. The spec's legacy
  `POST …/objects` + `{ messages: [...] }` shape was aligned to V2 in ably/specification#497.
- **Sandbox host**: use `SandboxApp.sandboxHost` (`sandbox.realtime.ably-nonprod.net`,
  `Test/UTS/infra/integration/SandboxApp.swift`) — the same nonprod host every UTS integration
  client uses; do not use the legacy `sandbox-rest.ably.io`.

Implementation details settled by the port (don't re-derive them):

- `operations` must be non-empty (`precondition`).
- **Response parsing**: the body is a single result object *or* a JSON array of them, each carrying
  an `objectIds` string array; the helper flattens those into its `[String]` return. The UTS spec
  helper documents no response contract — flagged upstream.
- The cocoa port posts through the UTS infra's plain `URLSession` helpers
  (`jsonRequest`/`httpRequest`, `infra/Utils.swift`) rather than an `ARTRest` client, so the spec's
  "REST client must be closed after use" note doesn't apply here.

The realtime client then observes the provisioned data through OBJECT_SYNC +
`channel.object.get()` — which the path-based implementation now supports, so these specs are
translate-and-evaluate like the rest of the module.

**The GC spec** (`objects_gc_test.md`, RTO10/RTLM19 tombstone semantics) needs no extra infra, but
it is the only integration spec that reads `instance().id` (hence `counterInstanceId(at:)` in
`ObjectsIntegrationHelpers.swift`, §5).

**Sandbox-app scoping.** The `IntegrationTestCase` pattern provisions per test via
`withSandboxApp`, so each parameterised case (×2 protocol variants) creates and deletes its own
app. Deliberate — Swift Testing has no suite-level async fixtures — but keep it in mind if sandbox
provisioning ever becomes a bottleneck.

**Proxy tier.** The objects module also has a proxy spec
(`integration/proxy/objects_faults.md`) — fault injection against `channel.object.get()` and
friends. Nothing objects-specific is needed for the proxy *infrastructure*: use the main skill's
proxy tier (session/rules/actions, `AuthReauthTests.swift` as the reference) and this doc purely
for the API mapping.

---

## 15. Worked example <a id="15-worked-example"></a>

Spec pseudocode (public-API style):

```text
test "increments a nested counter and observes it"
  root = AWAIT channel.object.get()
  AWAIT root.set("game", LiveMap.create({ score: LiveCounter.create(0) }))
  scoreSub = root.at("game.score").subscribe((event) => { received = event })
  AWAIT root.at("game.score").increment(10)
  ASSERT root.at("game.score").value() == 10
  ASSERT received.object.value() == 10
  scoreSub.unsubscribe()
```

ably-cocoa / Swift translation:

```swift
let root = try await channel.object.get()   // `any LiveMapPathObject`

try await root.set(
    key: "game",
    value: .liveMap(.create(entries: ["score": .liveCounter(.create())]))
)

let received = Captured<PathObjectSubscriptionEvent>()   // @Sendable callback -> harness collector
let scoreSub = try root.at(path: "game.score").subscribe { event in
    received.append(event)
}

try await root.at(path: "game.score").asLiveCounter().increment(amount: 10)

#expect(try root.at(path: "game.score").asLiveCounter().value() == 10)
#expect(try #require(received.all.last).object.asLiveCounter().value() == 10)
scoreSub.unsubscribe()
```

Note the mechanical rewrites: `AWAIT` → `try await` (no future); nested creation via the
`.liveMap(.create(entries:))` / `.liveCounter(.create())` enum cases (primitive literals would need
no wrapper at all); `at(...)` followed by `asLiveCounter()` before counter ops; the `@Sendable`
listener capturing through `Captured`; `event.object` re-cast with `asLiveCounter()`.

---

## 16. Quick symbol index <a id="16-symbol-index"></a>

| ably-js / spec symbol | ably-cocoa |
|---|---|
| `channel.object` | `channel.object: any RealtimeObject` (property) |
| `channel.object.get()` | `try await channel.object.get()` → `any LiveMapPathObject` |
| `PathObject` (polymorphic) | `PathObject` protocol + `asLiveMap()` / `asLiveCounter()` / `asPrimitive()` (3 views, not 8) |
| `Instance` (polymorphic) | `enum Instance { .liveMap / .liveCounter / .primitive }` — `switch`, no casts |
| `pathObj.path()` | `pathObj.path` (property) |
| `pathObj.get(k)` / `.at(p)` | `pathObj.asLiveMap().get(key: k)` / `.at(path: p)` |
| `pathObj.value()` | counter: `asLiveCounter().value()` → `Double?`; primitive: `asPrimitive().value()?.numberValue` etc. |
| `pathObj.set(k, v)` / `.remove(k)` | `try await pathObj.asLiveMap().set(key: k, value: v)` / `.remove(key: k)` |
| `pathObj.increment(n)` / `.decrement(n)` | `try await pathObj.asLiveCounter().increment(amount: n)` / `.decrement(amount: n)` |
| `op FAILS WITH <code>` (wrong method for type) | cast to the needed view, do/catch the op, `#expect(error.code == <code>)` (§7, §12) |
| `FOR [k, v] IN x.entries()` | `for (k, v) in try x.asLiveMap().entries()` |
| `"k" IN x.keys()` / `list(x.keys())` | `try x.asLiveMap().keys().contains("k")` / `try x.asLiveMap().keys()` |
| `size() == 7` / `== null` | `#expect(try …size() == 7)` (`Int?`) / `#expect(try node.asLiveMap().size() == nil)` |
| `op.action == "MAP_SET"` | `#expect(op.action == .mapSet)` (string tag → enum case, lowerCamel) |
| `op.mapSet.value.string` | `op.mapSet?.value.string` (`ObjectData` properties) |
| `LiveMap.create(entries)` | `LiveMap.create(entries: [String: LiveMapValue])` (value type) |
| `LiveCounter.create(n)` | `LiveCounter.create(initialCount: n)` (value type) |
| raw value into `set` | literals pass directly (`ExpressibleBy*Literal`); non-literals via `.primitive(.string(s))` etc.; binary always `.primitive(.data(d))` |
| `subscribe(cb)` → `Subscription` | `try subscribe { event in … }` → `any Subscription` (also `events()` AsyncStream) |
| `{ depth: n }` | `PathObjectSubscriptionOptions(depth: n)` |
| `event.object` / `event.message` | `event.object` / `event.message: ObjectMessage?` |
| `object.on('synced', cb)` | `channel.object.on(event: .synced) { … }` → `any StatusSubscription`; `off()` per subscription (no `off(listener)`/`offAll`) |
| type tag `'LiveMap'` etc. | `ValueType.liveMap` etc.; `type()` optional on paths, `type` non-optional on instances |
| `PublicAPI::ObjectMessage` | `struct ObjectMessage` (properties + public init; timestamps are `Date`) |
| `PublicAPI::ObjectOperation` | `struct ObjectOperation` (one payload non-nil; no `.unknown` action) |
| `InternalLiveMap` / `InternalLiveCounter` / `ObjectsPool` | `internal` in `AblyLiveObjects` — reach via `@testable import AblyLiveObjects` + `@testable import AblyLiveObjectsTesting`, §13 |
| `generateObjectId(type, initialValue, nonce, timestamp)` | `ObjectCreationHelpers.testsOnly_createObjectID(type:initialValue:nonce:timestamp:)` (`Test/AblyLiveObjectsTesting/Internals/ObjectCreationHelpers+TestsOnly.swift`) — use this sanctioned wrapper, not the raw internal `createObjectID`. The spec passes an epoch-**ms** integer; cocoa takes a `Date` — convert with `Date(timeIntervalSince1970: TimeInterval(ms) / 1000)` |
| `setup_synced_channel` / `build_*` (unit) | **implemented** — `Test/AblyLiveObjectsTesting/Helpers/StandardTestPool.swift` (+ `Helpers/TestFactories.swift`) + `Test/UTS/unit/objects/ObjectsUTSHelpers.swift`, §13 |
| `provision_objects_via_rest` (integration) | **implemented** — `Test/UTS/integration/standard/objects/helpers/ObjectsRestProvisioning.swift`, §14 |
