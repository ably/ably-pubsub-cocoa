#import <Foundation/Foundation.h>
#import <AblyPubSubDevice/ARTDataQuery.h>
#import <AblyPubSubDevice/ARTPaginatedResult.h>

@class ARTHttpChannel, ARTAnnotation, ARTOutboundAnnotation, ARTMessage, ARTErrorInfo;

NS_ASSUME_NONNULL_BEGIN

/**
 This object is used for providing parameters into `ARTHttpAnnotations`'s methods with paginated results.
 */
NS_SWIFT_SENDABLE
@interface ARTAnnotationsQuery : NSObject

/**
 * An upper limit on the number of annotations returned.
 */
@property (nonatomic, readonly) NSUInteger limit;

/// :nodoc:
- (instancetype)initWithLimit:(NSUInteger)limit;

@end

/**
 The protocol upon which the `ARTHttpAnnotations` is implemented.
 */
@protocol ARTHttpAnnotationsProtocol

/**
 * Publish a new annotation for a message.
 *
 * @param message The message to annotate.
 * @param annotation The annotation to publish. (Must include at least the `type`. Assumed to be an annotation.create if no action is specified)
 * @param callback A success or failure callback function.
 */
- (void)publishForMessage:(ARTMessage *)message annotation:(ARTOutboundAnnotation *)annotation callback:(nullable ARTCallback)callback;

/**
 * Publish a new annotation for a message using its serial.
 *
 * @param messageSerial The serial field of the message to annotate.
 * @param annotation The annotation to publish. (Must include at least the `type`. Assumed to be an annotation.create if no action is specified)
 * @param callback A success or failure callback function.
 */
- (void)publishForMessageSerial:(NSString *)messageSerial annotation:(ARTOutboundAnnotation *)annotation callback:(nullable ARTCallback)callback;

/**
 * Delete an annotation for a message.
 *
 * @param message The message to remove the annotation from.
 * @param annotation The annotation to delete. (Must include at least the `type`.)
 * @param callback A success or failure callback function.
 */
- (void)deleteForMessage:(ARTMessage *)message annotation:(ARTOutboundAnnotation *)annotation callback:(nullable ARTCallback)callback;

/**
 * Delete an annotation for a message using its serial.
 *
 * @param messageSerial The serial field of the message to remove the annotation from.
 * @param annotation The annotation to delete. (Must include at least the `type`.)
 * @param callback A success or failure callback function.
 */
- (void)deleteForMessageSerial:(NSString *)messageSerial annotation:(ARTOutboundAnnotation *)annotation callback:(nullable ARTCallback)callback;

/**
 * Get all annotations for a given message (as a paginated result).
 *
 * @param message The message to get annotations for.
 * @param query Restrictions on which annotations to get (such as a `limit` on the size of the result page).
 * @param callback A callback for retriving an `ARTPaginatedResult` containing annotations.
 */
- (void)getForMessage:(ARTMessage *)message query:(ARTAnnotationsQuery *)query callback:(ARTPaginatedAnnotationsCallback)callback;

 /**
  * Get all annotations for a given message (as a paginated result).
  *
  * @param messageSerial The `serial` of the message to get annotations for.
  * @param query Restrictions on which annotations to get (such as a `limit` on the size of the result page).
  * @param callback A callback for retriving an `ARTPaginatedResult` containing annotations.
  */
- (void)getForMessageSerial:(NSString *)messageSerial query:(ARTAnnotationsQuery *)query callback:(ARTPaginatedAnnotationsCallback)callback;

@end

/**
 * Functionality for annotating messages with small pieces of data, such as emoji reactions, that the server will roll up into the message as a summary.
 *
 * @see See `ARTHttpAnnotationsProtocol` for details.
 */
NS_SWIFT_SENDABLE
@interface ARTHttpAnnotations : NSObject <ARTHttpAnnotationsProtocol>
@end

NS_ASSUME_NONNULL_END
