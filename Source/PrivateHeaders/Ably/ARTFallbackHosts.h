#import <Foundation/Foundation.h>

@class ARTClientOptions;

NS_ASSUME_NONNULL_BEGIN

@interface ARTFallbackHosts : NSObject

+ (nullable NSArray<NSString *> *)hostsFromOptions:(ARTClientOptions *)options;

@end

/**
 Whether a response is an error from CloudFront: an HTTP status code `>= 400` and a `Server` header equal to `CloudFront`, ignoring case. Such a response calls for an alternative host (RSC15l4).
 */
BOOL ARTIsCloudFrontError(NSInteger statusCode, NSString *_Nullable serverHeader);

NS_ASSUME_NONNULL_END
