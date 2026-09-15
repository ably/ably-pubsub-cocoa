#import <AblyPubSubDevice/ARTDevicePushDetails.h>

@class ARTErrorInfo;

NS_ASSUME_NONNULL_BEGIN

@interface ARTDevicePushDetails ()

@property (nonatomic, readwrite) NSMutableDictionary<NSString *, NSObject *> *recipient;
@property (nullable, nonatomic, readwrite) NSString *state;
@property (nullable, nonatomic, readwrite) ARTErrorInfo *errorReason;

@end

NS_ASSUME_NONNULL_END
