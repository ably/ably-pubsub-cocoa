#import <AblyPubSubDevice/ARTDefault.h>

NS_ASSUME_NONNULL_BEGIN

@interface ARTDefault (Private)

/// The endpoint a client uses when `ARTClientOptions.endpoint` is nil (REC1a).
+ (NSString *)endpoint;

/// The URL a client requests to check its internet connection when `ARTClientOptions.connectivityCheckUrl` is nil (REC3a).
+ (NSURL *)connectivityCheckUrl;

/// The five fallback hosts `[id].[a-e].fallback.[domain]` for a routing policy (REC2c).
+ (NSArray<NSString *> *)fallbackHostsForRoutingPolicyId:(NSString *)routingPolicyId domain:(NSString *)domain;

+ (void)setConnectionStateTtl:(NSTimeInterval)value;
+ (void)setMaxMessageSize:(NSInteger)value;

+ (NSInteger)maxSandboxMessageSize;
+ (NSInteger)maxProductionMessageSize;

@end

NS_ASSUME_NONNULL_END
