@import XCTest;
@import AblyPubSubDevice;
// For ARTPubSubClient.internal, to read back the options the client was built with.
@import AblyPubSubDevice.Private;

@interface ARTPubSubDeviceTests : XCTestCase
@end

@implementation ARTPubSubDeviceTests

// Importing AblyPubSubDevice alone has to be enough to reach the core's types,
// otherwise every caller needs a second import to use what the door returns.
- (void)test_createClient_returns_a_realtime_client_declaring_the_device_agent {
    ARTClientOptions *const options = [[ARTClientOptions alloc] initWithKey:@"xxxx:xxxx"];
    options.autoConnect = NO;

    ARTPubSubClient *const client = [ARTPubSubDevice createClientWithOptions:options];

    XCTAssertTrue([client isKindOfClass:[ARTPubSubClient class]]);
    XCTAssertEqual(client.internal.options.agents[@"ably-pubsub-device"], ARTClientInformationAgentNotVersioned);
    XCTAssertNil(options.agents);

    [client close];
}

- (void)test_createClientWithKey_declares_the_device_agent {
    ARTPubSubClient *const client = [ARTPubSubDevice createClientWithKey:@"xxxx:xxxx"];

    XCTAssertEqualObjects(client.internal.options.key, @"xxxx:xxxx");
    XCTAssertEqual(client.internal.options.agents[@"ably-pubsub-device"], ARTClientInformationAgentNotVersioned);

    [client close];
}

@end
