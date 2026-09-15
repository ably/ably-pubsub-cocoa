#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_SENDABLE

/**
 * A set of options for controlling the creation of an `ARTWrapperSDKProxyRealtime` object.
 */
@interface ARTWrapperSDKProxyOptions: NSObject

/**
 * A set of additional entries for the Ably agent header and the `agent` realtime channel param.
 *
 * If an agent does not have a version, represent this by using the `ARTClientInformationAgentNotVersioned` pointer as the version.
 */
@property (nonatomic, readonly, nullable) NSDictionary<NSString *, NSString *> *agents;

- (instancetype)initWithAgents:(nullable NSDictionary<NSString *, NSString *> *)agents NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
