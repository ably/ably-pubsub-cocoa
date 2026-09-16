#import <AblyPubSubDevice/ARTRealtimeClient.h>
#import <AblyPubSubDevice/ARTClientOptions.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Creates Pub/Sub clients for apps running on an end user's device.
 *
 * A client created here tells Ably that it is running on an end user's device. That declaration
 * determines how the connection is counted: on an account billed by monthly active users, device
 * traffic counts toward the total, the connection must carry a `clientId`, and that `clientId` is
 * subject to a concurrency limit.
 *
 * The returned object is an `ARTRealtimeClient`, and it behaves like any other client of that
 * class, so all of the Ably Pub/Sub documentation applies to it unchanged.
 */
NS_SWIFT_NAME(PubSubDevice)
@interface ARTPubSubDevice : NSObject

- (instancetype)init NS_UNAVAILABLE;

/**
 * Creates a client with the given options.
 *
 * The options are not modified; any `agents` entries they carry are preserved alongside the
 * device declaration.
 *
 * @param options The client options. Set `clientId` on them, or use token authentication that
 * supplies one.
 *
 * @return A realtime client that declares it is running on an end user's device.
 */
+ (ARTRealtimeClient *)createClientWithOptions:(ARTClientOptions *)options NS_SWIFT_NAME(createClient(options:));

/**
 * Creates a client that authenticates with an API key.
 *
 * Prefer token authentication in code that ships to a device; an API key embedded in an app is
 * readable by anyone who has the app.
 *
 * @param key A full Ably API key.
 *
 * @return A realtime client that declares it is running on an end user's device.
 */
+ (ARTRealtimeClient *)createClientWithKey:(NSString *)key NS_SWIFT_NAME(createClient(key:));

/**
 * Creates a client that authenticates with an existing token.
 *
 * @param token An Ably authentication token.
 *
 * @return A realtime client that declares it is running on an end user's device.
 */
+ (ARTRealtimeClient *)createClientWithToken:(NSString *)token NS_SWIFT_NAME(createClient(token:));

@end

NS_ASSUME_NONNULL_END
