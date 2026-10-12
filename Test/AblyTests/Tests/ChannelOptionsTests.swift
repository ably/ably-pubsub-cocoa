import AblyPubSubDevice
import AblyTestingObjC
import XCTest

class ChannelOptionsTests: XCTestCase {
    // MARK: - ChannelOptions

    func test_copyChannelOptions() throws {
        let options = ChannelOptions()
        options.cipher = Crypto.getDefaultParams(CipherParamOptions(key: Crypto.generateRandomKey() as NSData))

        let copied = try XCTUnwrap(options.copy() as? ChannelOptions)

        // Check it creates a new object
        XCTAssertFalse(options === copied)

        // Check properties
        XCTAssertIdentical(options.cipher, copied.cipher)
    }

    func test_copyingFrozenChannelOptions_createsUnfrozenCopy() throws {
        let options = ChannelOptions()
        options.isFrozen = true

        let copied = try XCTUnwrap(options.copy() as? ChannelOptions)
        XCTAssertFalse(copied.isFrozen)
    }

    // TB2b2
    func test_initWithCipherParamOptions_callsGetDefaultParams() throws {
        let key = Crypto.generateRandomKey(128)
        let options = ChannelOptions(cipher: CipherParamOptions(key: key as NSData))

        let cipher = try XCTUnwrap(options.cipher)
        XCTAssertEqual(cipher.algorithm, "AES")
        XCTAssertEqual(cipher.key, key)
        XCTAssertEqual(cipher.keyLength, 128)
        XCTAssertEqual(cipher.mode, "CBC")
    }

    // TB2b2
    func test_initWithInvalidCipherParamOptions_raises() {
        XCTAssertNotNil(tryInObjC {
            _ = ChannelOptions(cipher: CipherParamOptions(key: Crypto.generateRandomKey(128) as NSData, algorithm: nil, keyLength: 256, mode: nil))
        })
    }

    // TB3
    func test_initWithCipherKey_acceptsBase64String() throws {
        let key = Crypto.generateRandomKey()
        let options = ChannelOptions(cipherKey: key.base64EncodedString() as NSString)

        let cipher = try XCTUnwrap(options.cipher)
        XCTAssertEqual(cipher.key, key)
        XCTAssertEqual(cipher.keyLength, 256)
    }

    // MARK: - RealtimeChannelOptions

    // TB2b2
    func test_realtimeInitWithCipherParamOptions_callsGetDefaultParams() throws {
        let key = Crypto.generateRandomKey()
        let options = RealtimeChannelOptions(cipher: CipherParamOptions(key: key as NSData))

        let cipher = try XCTUnwrap(options.cipher)
        XCTAssertEqual(cipher.key, key)
        XCTAssertEqual(cipher.keyLength, 256)
        XCTAssertTrue(options.attachOnSubscribe)
    }

    func test_copyRealtimeChannelOptions() throws {
        let options = RealtimeChannelOptions()
        options.cipher = Crypto.getDefaultParams(CipherParamOptions(key: Crypto.generateRandomKey() as NSData))
        options.params = ["foo": "bar"]
        options.modes = [.subscribe]
        options.attachOnSubscribe = false

        let copied = try XCTUnwrap(options.copy() as? RealtimeChannelOptions)

        // Check it creates a new object
        XCTAssertFalse(options === copied)

        // Check properties
        XCTAssertIdentical(options.cipher, copied.cipher)
        XCTAssertIdentical(options.params as NSDictionary?, copied.params as NSDictionary?)
        XCTAssertEqual(options.modes, copied.modes)
        XCTAssertEqual(options.attachOnSubscribe, copied.attachOnSubscribe)
    }

    func test_copyingFrozenRealtimeChannelOptions_createsUnfrozenCopy() throws {
        let options = RealtimeChannelOptions()
        options.isFrozen = true

        let copied = try XCTUnwrap(options.copy() as? RealtimeChannelOptions)
        XCTAssertFalse(copied.isFrozen)
    }
}
