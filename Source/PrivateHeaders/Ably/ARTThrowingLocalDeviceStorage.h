#import <Foundation/Foundation.h>
#import "ARTDeviceStorage.h"

NS_ASSUME_NONNULL_BEGIN

/**
 An `ARTDeviceStorage` whose every method raises
 `NSInternalInconsistencyException`. Used as the storage of an
 `ARTHttpClientInternal` when `ARTTestClientOptions.disableLocalDevice` is set.
 */
@interface ARTThrowingLocalDeviceStorage : NSObject<ARTDeviceStorage>
@end

NS_ASSUME_NONNULL_END
