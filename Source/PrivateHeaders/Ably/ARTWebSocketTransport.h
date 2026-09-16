#import <Foundation/Foundation.h>

#import "ARTRealtimeTransport.h"

@class ARTClientOptions;
@class ARTHttpClient;
@protocol ARTWebSocketFactory;

NS_ASSUME_NONNULL_BEGIN

@interface ARTWebSocketTransport : NSObject <ARTRealtimeTransport>

- (instancetype)init UNAVAILABLE_ATTRIBUTE;

- (instancetype)initWithRest:(ARTHttpClientInternal *)rest options:(ARTClientOptions *)options resumeKey:(nullable NSString *)resumeKey logger:(ARTInternalLog *)logger webSocketFactory:(id<ARTWebSocketFactory>)webSocketFactory NS_DESIGNATED_INITIALIZER;

@property (readonly, nonatomic) NSString *resumeKey;

@end

NS_ASSUME_NONNULL_END
