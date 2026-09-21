#import "ARTWrapperSDKProxyPush+Private.h"
#import "ARTWrapperSDKProxyPushAdmin+Private.h"

NS_ASSUME_NONNULL_BEGIN

@interface ARTWrapperSDKProxyPush ()

@property (nonatomic, readonly) ARTPush *underlyingPush;
@property (nonatomic, readonly) ARTWrapperSDKProxyOptions *proxyOptions;

@end

NS_ASSUME_NONNULL_END

@implementation ARTWrapperSDKProxyPush

- (instancetype)initWithPush:(ARTPush *)push proxyOptions:(ARTWrapperSDKProxyOptions *)proxyOptions {
    if (self = [super init]) {
        _underlyingPush = push;
        _proxyOptions = proxyOptions;
        _admin = [[ARTWrapperSDKProxyPushAdmin alloc] initWithPushAdmin:push.admin
                                                           proxyOptions:proxyOptions];
    }

    return self;
}

#if TARGET_OS_IOS

- (void)registerPushToStartToken:(nonnull NSData *)token {
    [self.underlyingPush registerPushToStartToken:token];
}

- (void)activate {
    [self.underlyingPush activate];
}

- (void)deactivate {
    [self.underlyingPush deactivate];
}

+ (void)didFailToRegisterForLocationNotificationsWithError:(nonnull NSError *)error pubsub:(nonnull ARTPubSubClient *)pubsub {
    [ARTPush didFailToRegisterForLocationNotificationsWithError:error pubsub:pubsub];
}

+ (void)didFailToRegisterForRemoteNotificationsWithError:(nonnull NSError *)error pubsub:(nonnull ARTPubSubClient *)pubsub {
    [ARTPush didFailToRegisterForRemoteNotificationsWithError:error pubsub:pubsub];
}

+ (void)didRegisterForLocationNotificationsWithDeviceToken:(nonnull NSData *)deviceToken pubsub:(nonnull ARTPubSubClient *)pubsub {
    [ARTPush didRegisterForLocationNotificationsWithDeviceToken:deviceToken pubsub:pubsub];
}

+ (void)didRegisterForRemoteNotificationsWithDeviceToken:(nonnull NSData *)deviceToken pubsub:(nonnull ARTPubSubClient *)pubsub {
    [ARTPush didRegisterForRemoteNotificationsWithDeviceToken:deviceToken pubsub:pubsub];
}

#endif

@end
