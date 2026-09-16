#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTErrorInfo.h>

typedef NS_ENUM(NSUInteger, ARTState) {
    ARTStateOk = 0,
    ARTStateConnectionClosedByClient,
    ARTStateConnectionDisconnected,
    ARTStateConnectionSuspended,
    ARTStateConnectionFailed,
    ARTStateAccessRefused,
    ARTStateNeverConnected,
    ARTStateConnectionTimedOut,
    ARTStateAttachTimedOut,
    ARTStateDetachTimedOut,
    ARTStateNotAttached,
    ARTStateInvalidArgs,
    ARTStateCryptoBadPadding,
    ARTStateNoClientId,
    ARTStateMismatchedClientId,
    ARTStateRequestTokenFailed,
    ARTStateAuthorizationFailed,
    ARTStateAuthUrlIncompatibleContent,
    ARTStateBadConnectionState,
    ARTStateError = 99999
};

NS_ASSUME_NONNULL_BEGIN

/**
 * An object representing the status of an internal operation.
 */
@interface ARTStatus : NSObject

@property (nullable, readonly, nonatomic) ARTErrorInfo *errorInfo;
@property (nonatomic) ARTState state;

+ (ARTStatus *)state:(ARTState) state;
+ (ARTStatus *)state:(ARTState) state info:(nullable ARTErrorInfo *) info;

- (NSString *)description;

@end

@interface ARTException : NSException
@end

NS_ASSUME_NONNULL_END
