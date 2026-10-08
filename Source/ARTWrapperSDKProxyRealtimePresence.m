#import "ARTWrapperSDKProxyRealtimePresence+Private.h"
#import "ARTRealtimePresence+Private.h"
#import "ARTWrapperSDKProxyOptions.h"

NS_ASSUME_NONNULL_BEGIN

@interface ARTWrapperSDKProxyRealtimePresence ()

@property (nonatomic, readonly) ARTRealtimePresence *underlyingRealtimePresence;
@property (nonatomic, readonly) ARTWrapperSDKProxyOptions *proxyOptions;

@end

NS_ASSUME_NONNULL_END

@implementation ARTWrapperSDKProxyRealtimePresence

- (instancetype)initWithRealtimePresence:(ARTRealtimePresence *)push proxyOptions:(ARTWrapperSDKProxyOptions *)proxyOptions {
    if (self = [super init]) {
        _underlyingRealtimePresence = push;
        _proxyOptions = proxyOptions;
    }

    return self;
}

- (BOOL)syncComplete {
    return self.underlyingRealtimePresence.syncComplete;
}

- (void)enter:(id _Nullable)data {
    [self.underlyingRealtimePresence enter:data];
}

- (void)enter:(id _Nullable)data callback:(nullable ARTCallback)callback {
    [self.underlyingRealtimePresence enter:data callback:callback];
}

- (void)enterClient:(nonnull NSString *)clientId data:(id _Nullable)data {
    [self.underlyingRealtimePresence enterClient:clientId data:data];
}

- (void)enterClient:(nonnull NSString *)clientId data:(id _Nullable)data callback:(nullable ARTCallback)callback {
    [self.underlyingRealtimePresence enterClient:clientId data:data callback:callback];
}

- (void)get:(nonnull ARTPresenceMessagesCallback)callback {
    [self.underlyingRealtimePresence get:callback];
}

- (void)get:(nonnull ARTRealtimePresenceQuery *)query callback:(nonnull ARTPresenceMessagesCallback)callback {
    [self.underlyingRealtimePresence get:query callback:callback];
}

- (void)history:(nonnull ARTPaginatedPresenceCallback)callback {
    [self.underlyingRealtimePresence.internal historyWithWrapperSDKAgents:self.proxyOptions.agents
                                                               completion:callback];
}

- (void)history:(ARTRealtimeHistoryQuery * _Nullable)query callback:(nonnull ARTPaginatedPresenceCallback)callback {
    [self.underlyingRealtimePresence.internal history:query
                                     wrapperSDKAgents:self.proxyOptions.agents
                                             callback:callback];
}

- (void)leave:(id _Nullable)data {
    [self.underlyingRealtimePresence leave:data];
}

- (void)leave:(id _Nullable)data callback:(nullable ARTCallback)callback {
    [self.underlyingRealtimePresence leave:data callback:callback];
}

- (void)leaveClient:(nonnull NSString *)clientId data:(id _Nullable)data {
    [self.underlyingRealtimePresence leaveClient:clientId data:data];
}

- (void)leaveClient:(nonnull NSString *)clientId data:(id _Nullable)data callback:(nullable ARTCallback)callback {
    [self.underlyingRealtimePresence leaveClient:clientId data:data callback:callback];
}

- (ARTEventListener *)subscribe:(nonnull ARTPresenceMessageCallback)callback {
    return [self.underlyingRealtimePresence subscribe:callback];
}

- (ARTEventListener *)subscribe:(ARTPresenceAction)action callback:(nonnull ARTPresenceMessageCallback)callback {
    return [self.underlyingRealtimePresence subscribe:action callback:callback];
}

- (ARTEventListener *)subscribe:(ARTPresenceAction)action onAttach:(nullable ARTCallback)onAttach callback:(nonnull ARTPresenceMessageCallback)callback {
    return [self.underlyingRealtimePresence subscribe:action onAttach:onAttach callback:callback];
}

- (ARTEventListener *)subscribeWithAttachCallback:(nullable ARTCallback)onAttach callback:(nonnull ARTPresenceMessageCallback)callback {
    return [self.underlyingRealtimePresence subscribeWithAttachCallback:onAttach callback:callback];
}

- (void)unsubscribe {
    [self.underlyingRealtimePresence unsubscribe];
}

- (void)unsubscribe:(nonnull ARTEventListener *)listener {
    [self.underlyingRealtimePresence unsubscribe:listener];
}

- (void)unsubscribe:(ARTPresenceAction)action listener:(nonnull ARTEventListener *)listener {
    [self.underlyingRealtimePresence unsubscribe:action listener:listener];
}

- (void)update:(id _Nullable)data {
    [self.underlyingRealtimePresence update:data];
}

- (void)update:(id _Nullable)data callback:(nullable ARTCallback)callback {
    [self.underlyingRealtimePresence update:data callback:callback];
}

- (void)updateClient:(nonnull NSString *)clientId data:(id _Nullable)data {
    [self.underlyingRealtimePresence updateClient:clientId data:data];
}

- (void)updateClient:(nonnull NSString *)clientId data:(id _Nullable)data callback:(nullable ARTCallback)callback {
    [self.underlyingRealtimePresence updateClient:clientId data:data callback:callback];
}

@end
