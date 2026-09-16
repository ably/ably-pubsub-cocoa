#import <Foundation/Foundation.h>
#import "ARTStatus.h"

@class ARTPublishResult;

NS_ASSUME_NONNULL_BEGIN

/**
 * Describes the result of a ProtocolMessage send operation (i.e. whether successful or error), and provides the `PublishResult` contained in the `ACK` for the message (if any).
 */
@interface ARTMessageSendStatus : NSObject

/**
 * The underlying status of the operation (state + errorInfo).
 */
@property (readonly, nonatomic) ARTStatus *status;

/**
 * The publish result corresponding to the ProtocolMessage that was sent, as extracted from the ACK.
 * This will be nil for NACK responses, error conditions, or messages that did not request acknowledgment.
 */
@property (nullable, readonly, nonatomic) ARTPublishResult *publishResult;

- (instancetype)init NS_UNAVAILABLE;

/**
 * Creates a new ARTMessageSendStatus with the given status and optional publish result.
 */
- (instancetype)initWithStatus:(ARTStatus *)status publishResult:(nullable ARTPublishResult *)publishResult;

/**
 * Convenience constructor for ACK responses with publish results.
 */
+ (instancetype)okWithPublishResult:(nullable ARTPublishResult *)publishResult;

/**
 * Convenience constructor for error responses (NACK or validation errors).
 */
+ (instancetype)errorWithInfo:(nullable ARTErrorInfo *)errorInfo;

@end

typedef void (^ARTMessageSendCallback)(ARTMessageSendStatus *status);

NS_ASSUME_NONNULL_END
