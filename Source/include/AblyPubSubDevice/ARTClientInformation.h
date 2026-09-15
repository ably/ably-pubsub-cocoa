#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Use this pointer as a dictionary value in the `ARTClientOptions.agents` property and the `ARTClientInformation.additionalAgents` method to indicate that an agent does not have a version.
 */
extern NSString *const ARTClientInformationAgentNotVersioned;

/**
 Provides information about the Ably client library and the environment in which it's running.
 */
@interface ARTClientInformation : NSObject

- (instancetype)init NS_UNAVAILABLE;

/**
 * Returns the default key-value entries that the Ably client library uses to identify itself, and the environment in which it's running, to the Ably service. Its keys are the names of the software components, and its values are their optional versions. The full list of keys that this method might return can be found [here](https://github.com/ably/ably-common/tree/main/protocol#agents). For example, users of this client library can find out the library version by fetching the value for the `"ably-pubsub-cocoa"` key from the return value of this method.
 */
@property (class, readonly) NSDictionary<NSString *, NSString *> *agents;

/**
 * Returns the `Agent` library identifier. This method should only be used by Ably-authored SDKs.
 *
 * @param additionalAgents A set of additional entries for the `Agent` library identifier. Its keys are the names of the agents, and its values are their optional versions. Pass `ARTClientInformationAgentNotVersioned` as the dictionary value for an agent that does not have a version.
 *
 * @return The `Agent` library identifier.
 */
+ (NSString *)agentIdentifierWithAdditionalAgents:(nullable NSDictionary<NSString *, NSString *> *)additionalAgents;

@end

NS_ASSUME_NONNULL_END
