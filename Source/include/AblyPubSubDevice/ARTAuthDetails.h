#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Contains the token string used to authenticate a client with Ably.
 */
NS_SWIFT_NAME(AuthDetails)
@interface ARTAuthDetails : NSObject<NSCopying>

/**
 * The authentication token string.
 */
@property (nonatomic, copy) NSString *accessToken;

/// :nodoc:
- (instancetype)initWithToken:(NSString *)token;

@end

NS_ASSUME_NONNULL_END
