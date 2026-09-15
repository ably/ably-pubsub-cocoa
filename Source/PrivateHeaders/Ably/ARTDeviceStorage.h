#import <Foundation/Foundation.h>
#import <AblyPubSubDevice/ARTTypes.h>

NS_ASSUME_NONNULL_BEGIN

// Instances of ARTDeviceStorage should expect to have their methods called
// from any thread.
@protocol ARTDeviceStorage <NSObject>
- (nullable id)objectForKey:(NSString *)key;
- (void)setObject:(nullable id)value forKey:(NSString *)key;

/// Removes all persisted data in a single atomic operation.
- (void)removeAll;

/// Apply a group of mutations as a single atomic unit. Implementations must
/// ensure that changes performed inside `block` either all become visible to
/// subsequent loads, or none of them do — this is what guarantees that, for
/// example, a `deviceIdentityToken` is never paired with a `deviceId` it does
/// not belong to. Nested invocations are supported; the outermost call commits.
- (void)performBatchUpdate:(NS_NOESCAPE void (^)(id<ARTDeviceStorage> writer))block;
@end

NS_ASSUME_NONNULL_END
