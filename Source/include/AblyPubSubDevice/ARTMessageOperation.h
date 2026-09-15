#import <Foundation/Foundation.h>
#import <AblyPubSubDevice/ARTTypes.h>
#import "ARTStringifiable.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Contains metadata about a message update or delete operation.
 */
NS_SWIFT_SENDABLE
@interface ARTMessageOperation : NSObject

/// Optional identifier of the client performing the operation.
@property (nullable, readonly, nonatomic) NSString *clientId;

/// Optional human-readable description of the operation.
@property (nullable, readonly, nonatomic) NSString *descriptionText;

/// Optional dictionary of key-value pairs containing additional metadata about the operation.
@property (nullable, readonly, nonatomic) NSDictionary<NSString *, NSString *> *metadata;

- (instancetype)initWithClientId:(nullable NSString *)clientId descriptionText:(nullable NSString *)descriptionText metadata:(nullable NSDictionary<NSString *, NSString *> *)metadata;

@end

NS_ASSUME_NONNULL_END
