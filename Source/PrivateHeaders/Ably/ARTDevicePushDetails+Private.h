#import <AblyPubSubDevice/ARTDevicePushDetails.h>

@class ARTErrorInfo;

NS_ASSUME_NONNULL_BEGIN

@interface ARTDevicePushDetails ()

@property (nonatomic, readwrite) NSMutableDictionary<NSString *, NSObject *> *recipient;
@property (nonatomic, readwrite) ARTDevicePushState state;
@property (nullable, nonatomic, readwrite) ARTErrorInfo *errorReason;

@end

/// Maps a PCP4 wire value (`active`, `failing` or `failed`) to an `ARTDevicePushState`. Returns `ARTDevicePushStateUnknown` for `nil` or any other value.
ARTDevicePushState ARTDevicePushStateFromWireValue(NSString *_Nullable value);

/// Returns the PCP4 wire value for a state, or `nil` for `ARTDevicePushStateUnknown`.
NSString *_Nullable ARTDevicePushStateToWireValue(ARTDevicePushState state);

NS_ASSUME_NONNULL_END
