#import <Foundation/Foundation.h>

@class ARTPublishResultSerial;

NS_ASSUME_NONNULL_BEGIN

/**
 * Contains the result of a publish operation.
 */
NS_SWIFT_SENDABLE
@interface ARTPublishResult : NSObject

/**
 * An array of message serials corresponding 1:1 to the messages that were published.
 *
 * A serial's `value` property may be `nil` if the message was discarded due to a configured conflation rule.
 */
@property (readonly, nonatomic) NSArray<ARTPublishResultSerial *> *serials;

- (instancetype)init NS_UNAVAILABLE;

/**
 * Initializes a new `ARTPublishResult` with the given serials.
 *
 * @param serials An array of `ARTPublishResultSerial` objects.
 */
- (instancetype)initWithSerials:(NSArray<ARTPublishResultSerial *> *)serials;

@end

NS_ASSUME_NONNULL_END
