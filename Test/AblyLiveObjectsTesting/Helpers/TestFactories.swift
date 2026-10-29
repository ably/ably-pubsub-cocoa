import _AblyPluginSupportPrivate
@testable import AblyLiveObjects
import Foundation

// Note that this file was created entirely by Cursor upon my giving it some guidelines — I have not checked its contents in any detail and it may well turn out that there are mistakes here which we need to fix in the future.

/// Factory for creating test objects with sensible defaults and override capabilities.
/// This follows a pattern similar to Ruby's factory_bot to reduce boilerplate in tests.
///
/// ## Key Principles
///
/// 1. **Sensible Defaults**: All factory methods provide reasonable default values
/// 2. **Override Capability**: You can override any default value when needed
/// 3. **No Assertions Against Defaults**: Tests should specify input values explicitly when making assertions about outputs
/// 4. **Common Scenarios**: Factory methods exist for common test scenarios
///
/// ## Usage Examples
///
/// ### Creating ObjectState instances
/// ```swift
/// // Basic map object state with defaults
/// let mapState = TestFactories.mapObjectState()
///
/// // Map object state with custom objectId and entries
/// let (key, entry) = TestFactories.stringMapEntry(key: "customKey", value: "customValue")
/// let customMapState = TestFactories.mapObjectState(
///     objectId: "map:custom@123",
///     entries: [key: entry]
/// )
///
/// // Counter object state with custom count
/// let counterState = TestFactories.counterObjectState(count: 100)
/// ```
///
/// ### Creating InboundObjectMessage instances
/// ```swift
/// // Simple map message
/// let mapMessage = TestFactories.simpleMapMessage(
///     objectId: "map:test@123",
///     key: "testKey",
///     value: "testValue"
/// )
///
/// // Counter message
/// let counterMessage = TestFactories.simpleCounterMessage(
///     objectId: "counter:test@123",
///     count: 42
/// )
///
/// // Root message with multiple entries
/// let rootMessage = TestFactories.rootMessageWithEntries([
///     "key1": "value1",
///     "key2": "value2"
/// ])
/// ```
///
/// ### Creating Map Entries
/// ```swift
/// // String entry
/// let (stringKey, stringEntry) = TestFactories.stringMapEntry(
///     key: "stringKey",
///     value: "stringValue"
/// )
///
/// // Number entry
/// let (numberKey, numberEntry) = TestFactories.numberMapEntry(
///     key: "numberKey",
///     value: NSNumber(value: 123.45)
/// )
///
/// // Boolean entry
/// let (boolKey, boolEntry) = TestFactories.booleanMapEntry(
///     key: "boolKey",
///     value: true
/// )
///
/// // Object reference entry
/// let (refKey, refEntry) = TestFactories.objectReferenceMapEntry(
///     key: "refKey",
///     objectId: "map:referenced@123"
/// )
/// ```
///
/// ## Migration Guide
///
/// When migrating existing tests to use factories:
///
/// 1. **Replace direct object creation** with factory calls
/// 2. **Remove arbitrary values** that don't affect the test
/// 3. **Keep only the values** that are relevant to the test assertions
/// 4. **Use descriptive factory method names** to make test intent clear
///
/// ### Before (with boilerplate)
/// ```swift
/// let state = ObjectState(
///     objectId: "arbitrary-id",
///     siteTimeserials: ["site1": "ts1"],
///     tombstone: false,
///     createOp: nil,
///     map: nil,
///     counter: WireObjectsCounter(count: 42), // Only this value matters
/// )
/// ```
///
/// ### After (using factory)
/// ```swift
/// let state = TestFactories.counterObjectState(count: 42) // Only specify what matters
/// ```
///
/// ## Best Practices
///
/// 1. **Use the most specific factory method** available for your use case
/// 2. **Override only the values** that are relevant to your test
/// 3. **Use descriptive parameter names** when overriding defaults
/// 4. **Document complex factory usage** with comments when needed
/// 5. **Group related factory calls** together for readability
///
/// ## Available Factory Methods
///
/// ### ObjectState Factories
/// - `objectState()` - Basic ObjectState with defaults
/// - `mapObjectState()` - ObjectState for map objects
/// - `counterObjectState()` - ObjectState for counter objects
/// - `rootObjectState()` - ObjectState for root object
///
/// ### InboundObjectMessage Factories
/// - `inboundObjectMessage()` - Basic InboundObjectMessage with defaults
/// - `mapObjectMessage()` - InboundObjectMessage with map ObjectState
/// - `counterObjectMessage()` - InboundObjectMessage with counter ObjectState
/// - `rootObjectMessage()` - InboundObjectMessage with root ObjectState
/// - `objectMessageWithoutState()` - InboundObjectMessage without ObjectState
/// - `simpleMapMessage()` - Simple map message with one string entry
/// - `simpleCounterMessage()` - Simple counter message
/// - `rootMessageWithEntries()` - Root message with multiple string entries
///
/// ### ObjectOperation Factories
/// - `objectOperation()` - Basic ObjectOperation with defaults
/// - `mapCreateOperation()` - Map create operation
/// - `counterCreateOperation()` - Counter create operation
///
/// ### Map Entry Factories
/// - `mapEntry()` - Basic ObjectsMapEntry with defaults
/// - `stringMapEntry()` - Map entry with string data
/// - `numberMapEntry()` - Map entry with number data
/// - `booleanMapEntry()` - Map entry with boolean data
/// - `bytesMapEntry()` - Map entry with bytes data
/// - `objectReferenceMapEntry()` - Map entry with object reference data
///
/// ### Other Factories
/// - `objectsMap()` - Basic ObjectsMap with defaults
/// - `objectsMapWithStringEntries()` - ObjectsMap with string entries
/// - `wireObjectsCounter()` - WireObjectsCounter with defaults
///
/// ## Extending the Factory System
///
/// When adding new factory methods, follow these patterns:
///
/// 1. **Use descriptive method names** that indicate the type and purpose
/// 2. **Provide sensible defaults** for all parameters
/// 3. **Group related methods** together with MARK comments
/// 4. **Include comprehensive documentation** explaining the purpose and usage
/// 5. **Follow the existing naming conventions** (e.g., `objectState()`, `mapObjectState()`)
/// 6. **Consider common test scenarios** and create convenience methods for them
/// 7. **Ensure all factory methods are static** for easy access
/// 8. **Use type-safe parameters** and avoid magic strings/numbers
/// 9. **Include examples in documentation** showing typical usage patterns
/// 10. **Test the factory methods** to ensure they work correctly
///
/// ### Example of Adding a New Factory Method
/// ```swift
/// /// Creates a LiveMap with specific data for testing
/// /// - Parameters:
/// ///   - objectId: The object ID for the map (default: "map:test@123")
/// ///   - entries: Dictionary of key-value pairs to populate the map
/// /// - Returns: A configured InternalDefaultLiveMap instance
/// static func liveMap(
///     objectId: String = "map:test@123",
///     entries: [String: String] = [:],
/// ) -> InternalDefaultLiveMap {
///     let map = InternalDefaultLiveMap.createZeroValued()
///     // Configure map with entries...
///     return map
/// }
/// ```
struct TestFactories {
    // MARK: - ObjectState Factory

    /// Creates an ObjectState with sensible defaults
    static func objectState(
        objectId: String = "test:object@123",
        siteTimeserials: [String: String] = ["site1": "ts1"],
        tombstone: Bool = false,
        createOp: ProtocolTypes.ObjectOperation? = nil,
        map: ProtocolTypes.ObjectsMap? = nil,
        counter: WireObjectsCounter? = nil,
    ) -> ProtocolTypes.ObjectState {
        ProtocolTypes.ObjectState(
            objectId: objectId,
            siteTimeserials: siteTimeserials,
            tombstone: tombstone,
            createOp: createOp,
            map: map,
            counter: counter,
        )
    }

    /// Creates an ObjectState for a map object
    static func mapObjectState(
        objectId: String = "map:test@123",
        siteTimeserials: [String: String] = ["site1": "ts1"],
        tombstone: Bool = false,
        createOp: ProtocolTypes.ObjectOperation? = nil,
        entries: [String: ProtocolTypes.ObjectsMapEntry]? = nil,
    ) -> ProtocolTypes.ObjectState {
        objectState(
            objectId: objectId,
            siteTimeserials: siteTimeserials,
            tombstone: tombstone,
            createOp: createOp,
            map: ProtocolTypes.ObjectsMap(
                semantics: .known(.lww),
                entries: entries,
            ),
            counter: nil,
        )
    }

    /// Creates an ObjectState for a counter object
    static func counterObjectState(
        objectId: String = "counter:test@123",
        siteTimeserials: [String: String] = ["site1": "ts1"],
        tombstone: Bool = false,
        createOp: ProtocolTypes.ObjectOperation? = nil,
        count: Int? = 42,
    ) -> ProtocolTypes.ObjectState {
        objectState(
            objectId: objectId,
            siteTimeserials: siteTimeserials,
            tombstone: tombstone,
            createOp: createOp,
            map: nil,
            counter: WireObjectsCounter(count: count.map { NSNumber(value: $0) }),
        )
    }

    /// Creates an ObjectState for the root object
    static func rootObjectState(
        siteTimeserials: [String: String] = ["site1": "ts1"],
        entries: [String: ProtocolTypes.ObjectsMapEntry]? = nil,
    ) -> ProtocolTypes.ObjectState {
        mapObjectState(
            objectId: "root",
            siteTimeserials: siteTimeserials,
            entries: entries,
        )
    }

    // MARK: - InboundObjectMessage Factory

    /// Creates an InboundObjectMessage with sensible defaults
    static func inboundObjectMessage(
        id: String? = nil,
        clientId: String? = nil,
        connectionId: String? = nil,
        extras: [String: JSONValue]? = nil,
        timestamp: Date? = nil,
        operation: ProtocolTypes.ObjectOperation? = nil,
        object: ProtocolTypes.ObjectState? = nil,
        serial: String? = nil,
        siteCode: String? = nil,
        serialTimestamp: Date? = nil,
    ) -> ProtocolTypes.InboundObjectMessage {
        ProtocolTypes.InboundObjectMessage(
            id: id,
            clientId: clientId,
            connectionId: connectionId,
            extras: extras,
            timestamp: timestamp,
            operation: operation,
            object: object,
            serial: serial,
            siteCode: siteCode,
            serialTimestamp: serialTimestamp,
        )
    }

    /// Creates an InboundObjectMessage with a map ObjectState
    static func mapObjectMessage(
        objectId: String = "map:test@123",
        siteTimeserials: [String: String] = ["site1": "ts1"],
        entries: [String: ProtocolTypes.ObjectsMapEntry]? = nil,
    ) -> ProtocolTypes.InboundObjectMessage {
        inboundObjectMessage(
            object: mapObjectState(
                objectId: objectId,
                siteTimeserials: siteTimeserials,
                entries: entries,
            ),
        )
    }

    /// Creates an InboundObjectMessage with a counter ObjectState
    static func counterObjectMessage(
        objectId: String = "counter:test@123",
        siteTimeserials: [String: String] = ["site1": "ts1"],
        count: Int? = 42,
    ) -> ProtocolTypes.InboundObjectMessage {
        inboundObjectMessage(
            object: counterObjectState(
                objectId: objectId,
                siteTimeserials: siteTimeserials,
                count: count,
            ),
        )
    }

    /// Creates an InboundObjectMessage with a root ObjectState
    static func rootObjectMessage(
        siteTimeserials: [String: String] = ["site1": "ts1"],
        entries: [String: ProtocolTypes.ObjectsMapEntry]? = nil,
    ) -> ProtocolTypes.InboundObjectMessage {
        inboundObjectMessage(
            object: rootObjectState(
                siteTimeserials: siteTimeserials,
                entries: entries,
            ),
        )
    }

    /// Creates an InboundObjectMessage without an ObjectState
    static func objectMessageWithoutState() -> ProtocolTypes.InboundObjectMessage {
        inboundObjectMessage(object: nil)
    }

    // MARK: - ObjectOperation Factory

    /// Creates an ObjectOperation with sensible defaults
    static func objectOperation(
        action: WireEnum<ProtocolTypes.ObjectOperationAction> = .known(.mapCreate),
        objectId: String = "test:object@123",
        mapCreate: ProtocolTypes.MapCreate? = nil,
        mapSet: ProtocolTypes.MapSet? = nil,
        mapRemove: WireMapRemove? = nil,
        counterCreate: WireCounterCreate? = nil,
        counterInc: WireCounterInc? = nil,
        objectDelete: WireObjectDelete? = nil,
        mapCreateWithObjectId: ProtocolTypes.MapCreateWithObjectId? = nil,
        counterCreateWithObjectId: ProtocolTypes.CounterCreateWithObjectId? = nil,
        mapClear: WireMapClear? = nil,
    ) -> ProtocolTypes.ObjectOperation {
        ProtocolTypes.ObjectOperation(
            action: action,
            objectId: objectId,
            mapCreate: mapCreate,
            mapSet: mapSet,
            mapRemove: mapRemove,
            counterCreate: counterCreate,
            counterInc: counterInc,
            objectDelete: objectDelete,
            mapCreateWithObjectId: mapCreateWithObjectId,
            counterCreateWithObjectId: counterCreateWithObjectId,
            mapClear: mapClear,
        )
    }

    /// Creates a map create operation
    static func mapCreateOperation(
        objectId: String = "map:test@123",
        entries: [String: ProtocolTypes.ObjectsMapEntry]? = nil,
    ) -> ProtocolTypes.ObjectOperation {
        objectOperation(
            action: .known(.mapCreate),
            objectId: objectId,
            mapCreate: ProtocolTypes.MapCreate(
                semantics: .known(.lww),
                entries: entries,
            ),
        )
    }

    /// Creates a counter create operation
    static func counterCreateOperation(
        objectId: String = "counter:test@123",
        count: Int? = 42,
    ) -> ProtocolTypes.ObjectOperation {
        objectOperation(
            action: .known(.counterCreate),
            objectId: objectId,
            counterCreate: WireCounterCreate(count: count.map { NSNumber(value: $0) }),
        )
    }

    /// Creates a WireCounterInc
    static func counterInc(number: Int = 10) -> WireCounterInc {
        WireCounterInc(number: NSNumber(value: number))
    }

    // MARK: - ObjectsMapEntry Factory

    /// Creates an ObjectsMapEntry with sensible defaults
    static func mapEntry(
        tombstone: Bool? = false,
        timeserial: String? = "ts1",
        data: ProtocolTypes.ObjectData?,
    ) -> ProtocolTypes.ObjectsMapEntry {
        ProtocolTypes.ObjectsMapEntry(
            tombstone: tombstone,
            timeserial: timeserial,
            data: data,
        )
    }

    /// Creates an InternalObjectsMapEntry with sensible defaults
    ///
    /// This should be kept in sync with ``mapEntry``.
    static func internalMapEntry(
        tombstonedAt: Date? = nil,
        timeserial: String? = "ts1",
        data: ProtocolTypes.ObjectData,
    ) -> InternalObjectsMapEntry {
        InternalObjectsMapEntry(
            tombstonedAt: tombstonedAt,
            timeserial: timeserial,
            data: data,
        )
    }

    /// Creates a map entry with string data
    static func stringMapEntry(
        key: String = "testKey",
        value: String = "testValue",
        tombstone: Bool? = false,
        timeserial: String? = "ts1",
    ) -> (key: String, entry: ProtocolTypes.ObjectsMapEntry) {
        (
            key: key,
            entry: mapEntry(
                tombstone: tombstone,
                timeserial: timeserial,
                data: ProtocolTypes.ObjectData(string: value),
            ),
        )
    }

    /// Creates an internal map entry with string data
    ///
    /// This should be kept in sync with ``stringMapEntry``.
    static func internalStringMapEntry(
        key: String = "testKey",
        value: String = "testValue",
        tombstonedAt: Date? = nil,
        timeserial: String? = "ts1",
    ) -> (key: String, entry: InternalObjectsMapEntry) {
        (
            key: key,
            entry: internalMapEntry(
                tombstonedAt: tombstonedAt,
                timeserial: timeserial,
                data: ProtocolTypes.ObjectData(string: value),
            ),
        )
    }

    /// Creates a map entry with number data
    static func numberMapEntry(
        key: String = "testKey",
        value: NSNumber = NSNumber(value: 42),
        tombstone: Bool? = false,
        timeserial: String? = "ts1",
    ) -> (key: String, entry: ProtocolTypes.ObjectsMapEntry) {
        (
            key: key,
            entry: mapEntry(
                tombstone: tombstone,
                timeserial: timeserial,
                data: ProtocolTypes.ObjectData(number: value),
            ),
        )
    }

    /// Creates a map entry with boolean data
    static func booleanMapEntry(
        key: String = "testKey",
        value: Bool = true,
        tombstone: Bool? = false,
        timeserial: String? = "ts1",
    ) -> (key: String, entry: ProtocolTypes.ObjectsMapEntry) {
        (
            key: key,
            entry: mapEntry(
                tombstone: tombstone,
                timeserial: timeserial,
                data: ProtocolTypes.ObjectData(boolean: value),
            ),
        )
    }

    /// Creates a map entry with bytes data
    static func bytesMapEntry(
        key: String = "testKey",
        value: Data = Data([0x01, 0x02, 0x03]),
        tombstone: Bool? = false,
        timeserial: String? = "ts1",
    ) -> (key: String, entry: ProtocolTypes.ObjectsMapEntry) {
        (
            key: key,
            entry: mapEntry(
                tombstone: tombstone,
                timeserial: timeserial,
                data: ProtocolTypes.ObjectData(bytes: value),
            ),
        )
    }

    /// Creates a map entry with object reference data
    static func objectReferenceMapEntry(
        key: String = "testKey",
        objectId: String = "map:referenced@123",
        tombstone: Bool? = false,
        timeserial: String? = "ts1",
    ) -> (key: String, entry: ProtocolTypes.ObjectsMapEntry) {
        (
            key: key,
            entry: mapEntry(
                tombstone: tombstone,
                timeserial: timeserial,
                data: ProtocolTypes.ObjectData(objectId: objectId),
            ),
        )
    }

    // MARK: - ObjectsMap Factory

    /// Creates an ObjectsMap with sensible defaults
    static func objectsMap(
        semantics: WireEnum<ProtocolTypes.ObjectsMapSemantics> = .known(.lww),
        entries: [String: ProtocolTypes.ObjectsMapEntry]? = nil,
        clearTimeserial: String? = nil,
    ) -> ProtocolTypes.ObjectsMap {
        ProtocolTypes.ObjectsMap(
            semantics: semantics,
            entries: entries,
            clearTimeserial: clearTimeserial,
        )
    }

    /// Creates an ObjectsMap with string entries
    static func objectsMapWithStringEntries(
        entries: [String: String] = ["key1": "value1", "key2": "value2"],
    ) -> ProtocolTypes.ObjectsMap {
        let mapEntries = entries.mapValues { value in
            mapEntry(data: ProtocolTypes.ObjectData(string: value))
        }
        return objectsMap(entries: mapEntries)
    }

    // MARK: - WireObjectsCounter Factory

    /// Creates a WireObjectsCounter with sensible defaults
    static func wireObjectsCounter(count: Int? = 42) -> WireObjectsCounter {
        WireObjectsCounter(count: count.map { NSNumber(value: $0) })
    }

    // MARK: - Operation Message Factories

    /// Creates an InboundObjectMessage with a MAP_SET operation
    static func mapSetOperationMessage(
        objectId: String = "map:test@123",
        key: String = "testKey",
        value: String = "testValue",
        serial: String = "ts1",
        siteCode: String = "site1",
    ) -> ProtocolTypes.InboundObjectMessage {
        inboundObjectMessage(
            operation: objectOperation(
                action: .known(.mapSet),
                objectId: objectId,
                mapSet: ProtocolTypes.MapSet(
                    key: key,
                    value: ProtocolTypes.ObjectData(string: value),
                ),
            ),
            serial: serial,
            siteCode: siteCode,
        )
    }

    /// Creates an InboundObjectMessage with a MAP_REMOVE operation
    static func mapRemoveOperationMessage(
        objectId: String = "map:test@123",
        key: String = "testKey",
        serial: String = "ts1",
        siteCode: String = "site1",
    ) -> ProtocolTypes.InboundObjectMessage {
        inboundObjectMessage(
            operation: objectOperation(
                action: .known(.mapRemove),
                objectId: objectId,
                mapRemove: WireMapRemove(key: key),
            ),
            serial: serial,
            siteCode: siteCode,
        )
    }

    /// Creates an InboundObjectMessage with a MAP_CLEAR operation
    static func mapClearOperationMessage(
        objectId: String = "map:test@123",
        serial: String = "ts1",
        siteCode: String = "site1",
    ) -> ProtocolTypes.InboundObjectMessage {
        inboundObjectMessage(
            operation: objectOperation(
                action: .known(.mapClear),
                objectId: objectId,
                mapClear: WireMapClear(),
            ),
            serial: serial,
            siteCode: siteCode,
        )
    }

    /// Creates an InboundObjectMessage with a MAP_CREATE operation
    static func mapCreateOperationMessage(
        objectId: String = "map:test@123",
        entries: [String: ProtocolTypes.ObjectsMapEntry]? = nil,
        serial: String = "ts1",
        siteCode: String = "site1",
    ) -> ProtocolTypes.InboundObjectMessage {
        inboundObjectMessage(
            operation: mapCreateOperation(
                objectId: objectId,
                entries: entries,
            ),
            serial: serial,
            siteCode: siteCode,
        )
    }

    /// Creates an InboundObjectMessage with a COUNTER_CREATE operation
    static func counterCreateOperationMessage(
        objectId: String = "counter:test@123",
        count: Int? = 42,
        serial: String = "ts1",
        siteCode: String = "site1",
    ) -> ProtocolTypes.InboundObjectMessage {
        inboundObjectMessage(
            operation: counterCreateOperation(
                objectId: objectId,
                count: count,
            ),
            serial: serial,
            siteCode: siteCode,
        )
    }

    /// Creates an InboundObjectMessage with a COUNTER_INC operation
    static func counterIncOperationMessage(
        objectId: String = "counter:test@123",
        number: Int = 10,
        serial: String = "ts1",
        siteCode: String = "site1",
    ) -> ProtocolTypes.InboundObjectMessage {
        inboundObjectMessage(
            operation: objectOperation(
                action: .known(.counterInc),
                objectId: objectId,
                counterInc: counterInc(number: number),
            ),
            serial: serial,
            siteCode: siteCode,
        )
    }

    // MARK: - Common Test Scenarios

    /// Creates a simple map object message with one string entry
    static func simpleMapMessage(
        objectId: String = "map:simple@123",
        key: String = "testKey",
        value: String = "testValue",
    ) -> ProtocolTypes.InboundObjectMessage {
        let (entryKey, entry) = stringMapEntry(key: key, value: value)
        return mapObjectMessage(
            objectId: objectId,
            entries: [entryKey: entry],
        )
    }

    /// Creates a simple counter object message
    static func simpleCounterMessage(
        objectId: String = "counter:simple@123",
        count: Int = 42,
    ) -> ProtocolTypes.InboundObjectMessage {
        counterObjectMessage(
            objectId: objectId,
            count: count,
        )
    }

    /// Creates a root object message with multiple entries
    static func rootMessageWithEntries(
        entries: [String: String] = ["key1": "value1", "key2": "value2"],
    ) -> ProtocolTypes.InboundObjectMessage {
        let mapEntries = entries.mapValues { value in
            mapEntry(data: ProtocolTypes.ObjectData(string: value))
        }
        return rootObjectMessage(entries: mapEntries)
    }

    // MARK: - Test Queue Helpers

    /// Creates a unique internal queue for testing purposes.
    /// This ensures that internalQueue is separate from userCallbackQueue (which is typically .main).
    static func createInternalQueue(label: String? = nil) -> DispatchQueue {
        let queueLabel = label ?? "test.internal.\(UUID().uuidString)"
        return DispatchQueue(label: queueLabel, qos: .userInitiated)
    }
}
