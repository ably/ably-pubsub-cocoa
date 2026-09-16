#import <AblyPubSubDevice/ARTPush.h>
#import "ARTPushAdmin+Private.h"
#import "ARTQueuedDealloc.h"

@class ARTPushActivationStateMachine;
@class ARTHttpClientInternal;
@protocol ARTPushRegistererDelegate;

NS_ASSUME_NONNULL_BEGIN

@interface ARTPushInternal : NSObject

@property (nonatomic, readonly) ARTPushAdminInternal *admin;

- (instancetype)initWithRest:(ARTHttpClientInternal *)rest logger:(ARTInternalLog *)logger;

#if TARGET_OS_IOS
/// Note that in certain edge cases (if the related ARTHttpClientInternal instance is being deallocated and the UIApplication delegate is being used as the push registerer delegate) this callback may be called with nil.
- (void)getActivationMachine:(void (^)(ARTPushActivationStateMachine * _Nullable))block;

/// Direct access to _activationMachine var for internal testing.
/// Throws an exception if there is no activation machine or it could not be locked immediately.
@property (readonly) ARTPushActivationStateMachine *activationMachine;

/// Create the _activationMachine manually with a custom delegate for internal testing.
- (ARTPushActivationStateMachine *)createActivationStateMachineWithDelegate:(id<ARTPushRegistererDelegate, NSObject>)delegate;
#endif

#if TARGET_OS_IOS

+ (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken rest:(ARTHttpClient *)rest;

+ (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken realtime:(ARTRealtime *)realtime;

+ (void)didFailToRegisterForRemoteNotificationsWithError:(NSError *)error rest:(ARTHttpClient *)rest;

+ (void)didFailToRegisterForRemoteNotificationsWithError:(NSError *)error realtime:(ARTRealtime *)realtime;

+ (void)didRegisterForLocationNotificationsWithDeviceToken:(NSData *)deviceToken rest:(ARTHttpClient *)rest;

+ (void)didRegisterForLocationNotificationsWithDeviceToken:(NSData *)deviceToken realtime:(ARTRealtime *)realtime;

+ (void)didFailToRegisterForLocationNotificationsWithError:(NSError *)error rest:(ARTHttpClient *)rest;

+ (void)didFailToRegisterForLocationNotificationsWithError:(NSError *)error realtime:(ARTRealtime *)realtime;

- (void)registerPushToStartToken:(NSData *)token;

- (void)activate;

- (void)deactivate;

#endif

@end

@interface ARTPush ()

@property (nonatomic, readonly) ARTPushInternal *internal;

- (instancetype)initWithInternal:(ARTPushInternal *)internal queuedDealloc:(ARTQueuedDealloc *)dealloc;

@end

NS_ASSUME_NONNULL_END
