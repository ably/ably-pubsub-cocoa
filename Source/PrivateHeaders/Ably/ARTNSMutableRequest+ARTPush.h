#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTTypes.h>

@class ARTLocalDevice;
@class ARTInternalLog;

NS_ASSUME_NONNULL_BEGIN

@interface NSMutableURLRequest (ARTPush)

- (void)setDeviceAuthentication:(ARTDeviceId *)deviceId localDevice:(ARTLocalDevice *)localDevice;
- (void)setDeviceAuthentication:(ARTDeviceId *)deviceId localDevice:(ARTLocalDevice *)localDevice logger:(nullable ARTInternalLog *)logger;
- (void)setDeviceAuthentication:(ARTLocalDevice *)localDevice;
- (void)setDeviceAuthentication:(ARTLocalDevice *)localDevice logger:(nullable ARTInternalLog *)logger;

@end

NS_ASSUME_NONNULL_END
