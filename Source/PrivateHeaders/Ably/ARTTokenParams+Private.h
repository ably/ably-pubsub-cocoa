#import <AblyPubSubDevice/ARTTokenParams.h>

@interface ARTTokenParams (Private)

- (ARTTokenRequest *)sign:(NSString *)key;
- (ARTTokenRequest *)sign:(NSString *)key withNonce:(NSString *)nonce;

@end
