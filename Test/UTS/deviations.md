# UTS Deviations (ably-cocoa)

This file records gaps found while running UTS-derived tests against ably-cocoa, per
`uts/docs/writing-derived-tests.md`, grouped into the manual's four sections (*UTS Spec Errors* /
*Failing Tests* / *Adapted Tests* / *Mock Infrastructure Limitations*). *Failing Tests* keep the
**spec-correct** assertion but are gated behind the `RUN_DEVIATIONS` environment variable so normal
runs stay green; *Adapted Tests* assert the SDK's actual behaviour and run **ungated**:

```swift
@Test(.enabled(if: ProcessInfo.processInfo.environment["RUN_DEVIATIONS"] != nil))
```

Reproduce a single deviation with:

```bash
RUN_DEVIATIONS=1 swift test --filter UTS.<TestClass>/<testMethod>
```

## UTS Spec Errors

*(none)*

## Failing Tests (SDK non-compliance, spec-correct test skipped)

### RSL1l1 — no publish-with-params API

1. **Spec point**: RSL1l1 (UTS `rest/integration/RSL1l1/publish-params-force-nack-0`)
2. **Spec requirement**: Additional publish params can be supplied with a publish and are
   transmitted to the server as request query params (the UTS test exercises this with the
   `_forceNack: "true"` test param, expecting the publish to fail with error code 40099).
3. **Actual SDK behaviour**: ably-cocoa exposes no publish overload accepting request params.
   `params:` exists only on the message-edit methods (`updateMessage:operation:params:callback:`,
   `deleteMessage:…`, `appendMessage:…` — RSL15f), on both `ARTChannelProtocol` and the internal
   `ARTChannel`, so the spec's `channel.publish(message:, params:)` cannot be expressed at all.
4. **Root cause**: `Source/include/AblyPubSubDevice/ARTChannelProtocol.h` / `Source/ARTHttpChannel.m` — the
   publish family (`publish:data:…`, `publish:` messages array) has no `params:` variant; RSL1l1 is
   unimplemented.
5. **Test impact**: `UTS.PublishTests/test_RSL1l1_publish_params_with_forceNack` — the spec-correct
   test cannot compile, so the method carries the spec pseudocode as comments, is gated behind
   `RUN_DEVIATIONS`, and fails via `Issue.record` pointing here when enabled. Reproduce:
   `RUN_DEVIATIONS=1 swift test --filter UTS.PublishTests/test_RSL1l1_publish_params_with_forceNack`.

## Adapted Tests (assert actual SDK behaviour, deviation documented)

### RTLM20e7f — outbound binary is raw `Data`, base64 applies at wire serialization

1. **Spec point**: RTLM20e7f (UTS `objects/unit/RTLM20/set-bytes-value-0`)
2. **Spec requirement**: `set()` with a binary value produces `mapSet.value.bytes == "AQID"` (a
   base64-encoded string).
3. **Actual SDK behaviour**: the outbound `ProtocolTypes.ObjectData.bytes` holds raw `Data`; the
   base64 encoding is applied at wire (JSON) serialization, below the `publishAndApply` capture
   point the unit tier asserts at.
4. **Root cause**: `LiveObjects/Sources/AblyLiveObjects/Protocol/ObjectMessage.swift` — OD4
   encoding runs in `toWire(format:)`, after the capture seam.
5. **Test impact**: `UTS.InternalLiveMapApiTests/setWithBytesValue` and the bytes row of
   `UTS.ValueTypesTests/evaluateMapAllValueTypesTable` (`objects/unit/RTLMV4d/map-set-all-types-table-0`)
   assert `Data([1, 2, 3])` (which base64-encodes to `AQID`); the spec lines are kept as comments.
6. **Status**: intentional deviation (layering — same wire bytes, asserted pre-encoding).

### RTLC12e1 — non-numeric increment amounts are compile-time-unrepresentable

1. **Spec point**: RTLC12e1 (UTS `objects/unit/RTLC12e1/increment-non-number-0` and
   `objects/unit/RTLC12e1/increment-invalid-amounts-table-0`)
2. **Spec requirement**: `increment()` with a null / non-Number / non-finite amount throws 40003.
3. **Actual SDK behaviour**: `increment(amount:)` takes a `Double`, so the `null` / `"10"` /
   `true` / `[1,2]` / `{n:1}` rows cannot be constructed at all; only the non-finite doubles
   (`NaN` / `Infinity` / `-Infinity`) reach the runtime 40003 check.
4. **Root cause**: typed Swift API surface (`LiveCounterPathObject.increment(amount: Double)`) —
   the invalid inputs are rejected by the compiler, a stronger guarantee than the runtime check.
5. **Test impact**: `UTS.InternalLiveCounterApiTests/incrementWithNonNumberThrows` and
   `incrementInvalidAmountsTable` port the expressible non-finite rows as runtime 40003
   assertions; all spec table rows are kept as comments. Per the spec's own nullish-language
   note, `null` ≡ omitted argument, pinned via the no-argument `increment()` default of 1.
6. **Status**: intentional deviation (type-system guarantee; same class as RTLMV4c below).

### RTLMV4c — `set()` invalid value types are compile-time-unrepresentable

1. **Spec point**: RTLM20e1 / RTLMV4c (UTS `objects/unit/RTLM20/set-invalid-values-table-0`)
2. **Spec requirement**: `set()` with an unsupported value type (`function` / `undefined` /
   `symbol`) throws 40013.
3. **Actual SDK behaviour**: `LiveMapValue` is a closed enum (`.primitive` / `.liveMap` /
   `.liveCounter`); the spec's JavaScript-only constructs have no representation, so the invalid
   call cannot be written.
4. **Root cause**: typed Swift API surface (`LiveMapPathObject.set(key:value: LiveMapValue)`).
5. **Test impact**: `UTS.InternalLiveMapApiTests/setInvalidValuesTableIsCompileTimeUnrepresentable`
   retains the spec pseudocode as comments and passes trivially, documenting the compile-time
   guarantee.
6. **Status**: intentional deviation (type-system guarantee).

### RTINS3b / RTINS4d / RTINS9c — Instance payloads expose only kind-applicable members

1. **Spec point**: RTINS3b, RTINS4d, RTINS9c (UTS `objects/unit/RTINS3/id-0`,
   `objects/unit/RTINS4/value-counter-0`, `objects/unit/RTINS9/size-0`)
2. **Spec requirement**: on the polymorphic `Instance`, `id()` returns null for a primitive,
   `value()` returns null for a map, and `size()` returns null for a non-map.
3. **Actual SDK behaviour**: the `Instance` enum's payload protocols expose only members
   applicable to the wrapped kind — `PrimitiveInstance` has no `id`, `LiveMapInstance` no
   `value()`, `LiveCounterInstance` no `size()` — so the wrong-kind-returns-null cases are
   absent-member compile-time guarantees.
4. **Root cause**: typed Swift API surface (`Path Based API/Public/Instance.swift`,
   objects-mapping §5).
5. **Test impact**: `UTS.InstanceTests/idReturnsObjectId`, `valueReturnsCounterNumberOrPrimitive`,
   and `sizeReturnsNonTombstonedCount` port the expressible right-kind half of each case; the
   null-returning spec lines are kept as comments noting the structural guarantee.
6. **Status**: intentional deviation (type-system guarantee).

### RTINS12d / RTINS14d / RTINS16c — wrong-type Instance calls are unreachable (no casts)

1. **Spec point**: RTINS12d, RTINS14d, RTINS16c (UTS `objects/unit/RTINS12d/set-non-map-throws-0`,
   `objects/unit/RTINS14d/increment-non-counter-throws-0`,
   `objects/unit/RTINS16c/subscribe-primitive-throws-0`)
2. **Spec requirement**: `set` on a non-map, `increment` on a non-counter, and `subscribe` on a
   primitive instance each fail with error 92007.
3. **Actual SDK behaviour**: `Instance` is a Swift enum with no `as*` casts (the RTTS9d mismatch
   path is unrepresentable); a `.liveCounter` payload has no `set`, a `.liveMap` payload no
   `increment`, and a `.primitive` payload no `subscribe` — the failing call cannot be issued.
4. **Root cause**: typed Swift API surface (objects-mapping §5/§12).
5. **Test impact**: `UTS.InstanceTests/setOnNonMapThrows`, `incrementOnNonCounterThrows`, and
   `subscribeOnPrimitiveThrows` retain the spec pseudocode as comments, `guard case`-confirm the
   wrong payload kind, and pass documenting the compile-time guarantee.
6. **Status**: intentional deviation (type-system guarantee).

### RTINS10 / RTTS7d / RTTS3f — `compact()` is not implemented; adapted to `compactJson()`

1. **Spec point**: RTINS10, RTPO13, RTPO13c, RTPO3c1 (UTS `objects/unit/RTINS10/compact-0`,
   `objects/unit/RTPO13/compact-recursive-0`, `objects/unit/RTPO13c/compact-counter-0`, the
   `compact()` line of `objects/unit/RTPO3c1/read-null-on-failure-0`)
2. **Spec requirement**: `instance.compact()` / `pathObj.compact()` recursively compact the object
   graph into plain language values.
3. **Actual SDK behaviour**: ably-cocoa does not implement the non-JSON `compact()` — RTTS7d /
   RTTS3f permit typed SDKs to omit it; `compactJson()` is the provided equivalent, whose
   recursive compaction values are identical (nested counter → its number, nested map → JSON
   object). Within RTPO13, binary is additionally base64-encoded by `compactJson` (RTPO14b1)
   where `compact()` would return raw bytes — the `avatar` line asserts `"AQID"`.
4. **Root cause**: deliberate API surface decision (objects-mapping §5).
5. **Test impact**: `UTS.InstanceTests/compactRecursivelyCompacts`,
   `UTS.PathObjectTests/compactRecursivelyCompacts`, `compactReturnsNumberForCounter`, and the
   `compact()` line of `readOperationsReturnNullOnResolutionFailure` assert the spec's values
   against the `compactJson()` result; the `compact()` spec lines are kept as comments.
6. **Status**: intentional deviation (documented API omission per RTTS7d/RTTS3f).

### RTLCV4a — non-Number counter initial value is compile-time-unrepresentable

1. **Spec point**: RTLCV4a (UTS `objects/unit/RTLCV4a/evaluate-validates-count-0`)
2. **Spec requirement**: evaluating a counter blueprint whose count is not a Number (or not
   finite) throws 40003.
3. **Actual SDK behaviour**: `LiveCounter.create(initialCount: Double)` rejects a non-Number at
   compile time; only a non-finite `Double` (`NaN` / `Infinity`) reaches the runtime RTLCV4a
   check.
4. **Root cause**: typed Swift API surface (same class as RTLC12e1 / RTLMV4c).
5. **Test impact**: `UTS.ValueTypesTests/evaluateCounterValidatesCountType` ports the expressible
   non-finite case as a runtime 40003 assertion (via the production
   `ObjectCreationHelpers.evaluate(liveCounter:...)`); the `"not_a_number"` spec line is kept as
   a comment.
6. **Status**: intentional deviation (type-system guarantee).

### RTLMV4a / RTLMV4b — invalid map entries container / non-string keys are compile-time-unrepresentable

1. **Spec point**: RTLMV4a, RTLMV4b (UTS `objects/unit/RTLMV4a/evaluate-validates-entries-0`,
   `objects/unit/RTLMV4b/evaluate-validates-keys-0`)
2. **Spec requirement**: entries that are null / not a Dict (RTLMV4a) or contain a non-String key
   (RTLMV4b) throw 40003 at evaluation.
3. **Actual SDK behaviour**: `LiveMap.create(entries: [String: LiveMapValue])` takes a Swift
   dictionary with `String` keys; null/non-dict entries and non-string keys cannot be
   constructed. `LiveMap.create()` (no entries) is a valid empty map (RTLMV4e2), not an error.
4. **Root cause**: typed Swift API surface. RTLMV4b is additionally marked non-applicable by the
   spec for string-keyed languages.
5. **Test impact**: `UTS.ValueTypesTests/evaluateMapValidatesEntriesType` and
   `evaluateMapValidatesKeyTypes` retain the spec pseudocode as comments and pass trivially,
   documenting the compile-time guarantee.
6. **Status**: intentional deviation (type-system guarantee).

### RTLO4b4c1 — noop increment shape is an absent `counterInc`, not an empty `{}`

1. **Spec point**: RTLO4b4c1 / RTLC9h (UTS `objects/unit/RTLO4b4c1/noop-no-trigger-0`)
2. **Spec requirement**: an increment with no `number` — modelled as `counterInc: {}` (present
   but empty) — yields a `.noop` LiveObjectUpdate (RTLC9h) that must not fire subscribe
   listeners.
3. **Actual SDK behaviour**: cocoa's `WireCounterInc.number` is non-optional, so a
   present-but-empty `counterInc` cannot be constructed; the same RTLC9h noop branch is reached
   with an **absent** `counterInc`. (A `number: 0` would EXIST per RTLC9g and produce a non-noop
   amount-0 update, so it is not a valid noop stand-in.)
4. **Root cause**: wire-type surface (`ProtocolTypes.WireCounterInc.number: NSNumber`) — no
   representation for an empty counterInc object.
5. **Test impact**: `UTS.LiveObjectSubscribeTests/noopUpdateDoesNotTriggerListener` builds the
   noop via `ObjectsUTS.counterIncNoopMessage` (absent counterInc); the spec-correct assertion
   (`updates.length == 2`, noop suppressed) runs ungated. (`counterIncNoopMessage`'s doc comment
   references this entry.)
6. **Status**: intentional deviation (wire-representation; identical RTLC9h branch and observable
   behaviour).

### RTO8a — OBJECT messages in INITIALIZED are applied immediately, not buffered

1. **Spec point**: RTO8a (UTS `objects/unit/RTO7-RTO8/buffer-without-attached-0`)
2. **Spec requirement**: if sync state is not SYNCED, buffer ObjectMessages — including the
   INITIALIZED state (before any ATTACHED), so `bufferedObjectOperations.length == 1`.
3. **Actual SDK behaviour**: cocoa buffers iff SYNCING; an OBJECT message received in INITIALIZED
   is applied immediately (RTO8b path), so no buffer is created and the object lands in the pool.
4. **Root cause**: `LiveObjects/Sources/AblyLiveObjects/Internal/InternalDefaultRealtimeObjects.swift`
   (`nosync_handleObjectProtocolMessage`) — the code documents that "buffer iff SYNCING" is
   equivalent because operations only arrive after ATTACHED (→ SYNCING) in production.
5. **Test impact**: `UTS.ObjectsPoolTests/objectMessagesBufferedEvenWithoutPrecedingAttached`
   asserts the actual behaviour (no buffer, counter applied to 5); the spec
   `bufferedObjectOperations.length == 1` ASSERT is kept as a comment.
6. **Status**: intentional deviation (production-equivalent — INITIALIZED never receives OBJECT
   messages in a real connection).

### RTO24b2c — subscription listeners are non-throwing; a throwing listener is not expressible

1. **Spec point**: RTO24b2c (UTS `objects/unit/RTO24b2c/listener-exception-caught-0`)
2. **Spec requirement**: a subscription listener that throws must not affect delivery to other
   listeners.
3. **Actual SDK behaviour**: `PathObjectSubscriptionCallback` is a non-throwing
   `@Sendable (PathObjectSubscriptionEvent) -> Void` (objects-mapping §8), so a throwing
   listener cannot be written; the failure mode the spec guards against is unrepresentable.
4. **Root cause**: typed Swift API surface (non-throwing callback signature).
5. **Test impact**: `UTS.PathObjectSubscribeTests/listenerExceptionDoesNotAffectOthers` models
   the first listener as a benign no-op and still asserts the second listener fires exactly once
   (the observable behaviour); the spec's `THROW` line is kept as a comment.
6. **Status**: intentional deviation (type-system guarantee).

### RTPO13c5 — `compact()` shared-reference cycle reuse is not expressible via `compactJson()`

1. **Spec point**: RTPO13c5 (UTS `objects/unit/RTPO13c5/compact-cycle-detection-0`)
2. **Spec requirement**: `compact()` reuses the already-compacted in-memory object for a cyclic
   reference (`result["prefs"]["back_ref"] IS result` — reference identity).
3. **Actual SDK behaviour**: ably-cocoa does not implement the non-JSON `compact()` (RTTS3f);
   `compactJson()` encodes cycles as `{objectId: ...}` (RTPO14b2), a value-shaped form in which
   an identity (`IS`) comparison is meaningless.
4. **Root cause**: deliberate API surface decision (objects-mapping §5; same class as the
   RTINS10/RTTS7d entry above).
5. **Test impact**: `UTS.PathObjectTests/compactHandlesCyclesViaSharedReference` retains the spec
   pseudocode as comments and passes trivially; the JSON cycle behaviour is asserted by
   `UTS.PathObjectTests/compactJsonEncodesCyclesAsObjectId`
   (`objects/unit/RTPO14/compact-json-0`).
6. **Status**: intentional deviation (documented API omission per RTTS3f).

### RTPO5b / RTPO6b — non-string path/key inputs are compile-time-unrepresentable

1. **Spec point**: RTPO5b, RTPO6b (UTS `objects/unit/RTPO5b/get-non-string-throws-0`,
   `objects/unit/RTPO6b/at-non-string-throws-0`)
2. **Spec requirement**: `get(123)` / `at(123)` (non-String input) throw 40003.
3. **Actual SDK behaviour**: `LiveMapPathObject.get(key: String)` / `at(path: String)` reject a
   non-string at compile time, so the invalid call cannot be written; the 40003 rejection is
   compile-time-unrepresentable — a stronger guarantee than the runtime check.
4. **Root cause**: typed Swift API surface (same class as RTLMV4c / RTLC12e1).
5. **Test impact**: `UTS.PathObjectTests/getNonStringKeyIsCompileTimeBlocked` and
   `atNonStringIsCompileTimeBlocked` retain the spec pseudocode as comments and pass trivially.
6. **Status**: intentional deviation (type-system guarantee).

### RTLM6h / RTLC6 — `replaceData` updates carry no `objectMessage`

1. **Spec point**: RTLM6h and its counter counterpart (UTS `objects/unit/RTLM6/*` and
   `objects/unit/RTLC6/*` replaceData cases)
2. **Spec requirement**: `replaceData(state_msg)` takes the whole `ObjectMessage` and sets
   `LiveObjectUpdate.objectMessage` on the returned update to it (`objects-features.md` RTLM6h:
   "set `LiveMapUpdate.objectMessage` on the resulting update to the provided `ObjectMessage`").
3. **Actual SDK behaviour**: `nosync_replaceData(using:objectMessageSerialTimestamp:)` takes only
   the `ObjectState` (plus the extracted `serialTimestamp`), and its returned update carries
   `objectMessage == nil` — cocoa generalizes RTO4b2a ("without populating
   `LiveMapUpdate.objectMessage`", specified there for the ATTACHED empty-reset case) to all
   sync-originated updates; the op-apply path (RTLM7f/RTLM8e via `nosync_apply`) does stamp
   `objectMessage`, so all op-path `update.objectMessage == msg` assertions hold.
4. **Root cause**: `LiveObjects/Sources/AblyLiveObjects/Internal/` — the OBJECT_SYNC pipeline
   deliberately does not pass the message down to `replaceData` (the public message is projected
   per PAOM3 at delivery; sync emits via `nosync_emit`, not the stamping `nosync_emitAndTearDown`).
   Note the tension between RTLM6h (stamp always) and the RTO4b2a generalization is worth raising
   upstream in the features spec.
5. **Test impact**: the replaceData / tombstone-via-sync cases of `UTS.InternalLiveCounterTests`
   and `UTS.InternalLiveMapTests` assert the substantive state/diff coverage and the actual
   `objectMessage == nil`; each `update.objectMessage == state_msg` spec ASSERT is kept as a
   comment citing S-4.
6. **Status**: intentional deviation (internal-level; observable public behaviour unchanged —
   sync-originated public events carry no message either way).

## Mock Infrastructure Limitations

*(none)*

## Shape-deviation vocabulary (objects unit tier)

Recurring internal-API **shape** differences (white-box unit ports only, per
`writing-derived-tests.md`'s unit-only deviation rule): each is named once here and cited by tag
from the suites that hit it. Observable coverage is always preserved.

- **(S-1) The pool sync state machine lives on `InternalDefaultRealtimeObjects`, not
  `ObjectsPool`.** The UTS specs model the sync state machine (INITIALIZED→SYNCING→SYNCED,
  `bufferedObjectOperations`, `appliedOnAckSerials`) as methods/fields on the `ObjectsPool`; in
  cocoa the pool value type is only the object dictionary, and the state machine lives on
  `InternalDefaultRealtimeObjects`, which owns the pool. `pool.processAttached` /
  `pool.processObjectSync` / `pool.processObjectMessage` / `pool.syncState` map onto
  `nosync_onChannelAttached` / `nosync_handleObjectSyncProtocolMessage` /
  `nosync_handleObjectProtocolMessage` and `testsOnly_syncState`. Where a spec asserts
  `pool.syncState` in a fixture that seeds the pool directly (no realtime-objects layer), the
  assertion is kept as an annotated comment. Cited by: `UTS.ObjectsPoolTests`,
  `UTS.ParentReferencesTests` (the RTO5c10 `syncState == SYNCED` annotations).
- **(S-2) The retained local create lives on `*CreateWithObjectId.derivedFrom`.** The spec's
  outbound `operation.counterCreate` / `operation.mapCreate` (RTLCV4g5 / RTLMV4j5) map to
  `operation.counterCreateWithObjectId.derivedFrom` / `operation.mapCreateWithObjectId.derivedFrom`
  on cocoa's `ProtocolTypes.OutboundObjectMessage` — the `*WithObjectId` variant carries the wire
  `initialValue` + `nonce`, and the retained create is local-only on `derivedFrom` (not a wire
  field). The public `ObjectOperation` resolves it back per PAOOP3b2/PAOOP3c2. Cited by:
  `UTS.ValueTypesTests`, `UTS.PublicObjectMessageTests`.
- **(S-3) The apply seam returns an optional `LiveObjectUpdate`, not a Bool.** The spec's
  `applyOperation(msg, source)` returns a Bool (applied/discarded);
  `InternalDefault{LiveCounter,LiveMap}.nosync_apply(...)` returns `LiveObjectUpdate?` — `nil`
  for a discarded op (RTLO4a gate, RTLC7b/RTLC7e, unsupported actions), a non-nil update
  (possibly `.noop`) when applied. Spec `result == false` → `#expect(result == nil)`;
  `result == true` / `IS NOT false` → `#expect(result != nil)`. Cited by:
  `UTS.InternalLiveCounterTests`, `UTS.InternalLiveMapTests`.
- **(S-4) `replaceData` takes an `ObjectState` and its update carries no `objectMessage`.** The
  spec's `replaceData(state_msg)` takes the full ObjectMessage and stamps it on the returned
  update (RTLM6h); cocoa's `nosync_replaceData(using:objectMessageSerialTimestamp:)` takes only
  the `ObjectState` (+ serialTimestamp) and returns `objectMessage == nil` — see the
  "RTLM6h / RTLC6 — `replaceData` updates carry no `objectMessage`" Adapted Tests entry for the
  behaviour half. Cited by: `UTS.InternalLiveCounterTests`, `UTS.InternalLiveMapTests`.
