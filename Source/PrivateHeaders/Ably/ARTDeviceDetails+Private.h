#import <Foundation/Foundation.h>
#import <AblyPubSubDevice/ARTPush.h>

@class ARTDevicePushDetails;

NS_ASSUME_NONNULL_BEGIN

@interface ARTDeviceDetails ()

@property (nonatomic, readwrite) ARTDeviceId *id;
@property (nullable, nonatomic, readwrite) NSString *clientId;
@property (nonatomic, readwrite) NSString *platform;
@property (nonatomic, readwrite) NSString *formFactor;
@property (nonatomic, readwrite) NSDictionary<NSString *, NSString *> *metadata;
@property (nonatomic, readwrite) ARTDevicePushDetails *push;

@end

NS_ASSUME_NONNULL_END
