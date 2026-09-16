#import "ARTRealtimeTransportFactory.h"
#import "ARTWebSocketTransport+Private.h"
#import "ARTWebSocketFactory.h"

@implementation ARTDefaultRealtimeTransportFactory

- (id<ARTRealtimeTransport>)transportWithRest:(ARTHttpClientInternal *)rest options:(ARTClientOptions *)options resumeKey:(NSString *)resumeKey logger:(ARTInternalLog *)logger {
    const id<ARTWebSocketFactory> webSocketFactory = [[ARTDefaultWebSocketFactory alloc] init];
    return [[ARTWebSocketTransport alloc] initWithRest:rest
                                               options:options
                                             resumeKey:resumeKey
                                                logger:logger
                                      webSocketFactory:webSocketFactory];
}

@end
