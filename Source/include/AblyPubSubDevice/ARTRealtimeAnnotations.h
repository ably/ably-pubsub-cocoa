#import <Foundation/Foundation.h>
#import <AblyPubSubDevice/ARTAnnotation.h>
#import <AblyPubSubDevice/ARTOutboundAnnotation.h>
#import <AblyPubSubDevice/ARTHttpAnnotations.h>
#import <AblyPubSubDevice/ARTDataQuery.h>
#import <AblyPubSubDevice/ARTEventEmitter.h>
#import <AblyPubSubDevice/ARTRealtimeChannel.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The protocol upon which the `ARTRealtimeAnnotations` is implemented.
 */
@protocol ARTRealtimeAnnotationsProtocol

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
  * Get all annotations for a given message (as a paginated result) (alternative form where you only have the serial of the message, not a complete Message object).
  *
  * @param messageSerial The `serial` of the message to get annotations for.
  * @param query Restrictions on which annotations to get (such as a `limit` on the size of the result page).
  * @param callback A callback for retriving an `ARTPaginatedResult` containing annotations.
  */
- (void)getForMessageSerial:(NSString *)messageSerial query:(ARTAnnotationsQuery *)query callback:(ARTPaginatedAnnotationsCallback)callback;

/**
 * Registers a listener that is called each time an `ARTAnnotation` is received on the channel.
 *
 * Note that if you want to receive individual realtime annotations (instead of just the rolled-up summaries), you will need to request the `ARTChannelModeAnnotationSubscribe`  in `ARTChannelOptions`, since they are not delivered by default. In general, most clients will not bother with subscribing to individual annotations, and will instead just look at the summary updates.
 *
 * @param callback A callback containing received annotation.
 *
 * @return An event listener object.
 */
- (ARTEventListener *_Nullable)subscribe:(ARTAnnotationCallback)callback;

/**
 * Registers a listener that is called each time an `ARTAnnotation` is received on the channel. An attach callback may optionally be passed in to this call to be notified of success or failure of the channel `-[ARTRealtimeChannelProtocol attach]` operation. It will not be called if the `ARTRealtimeChannelOptions.attachOnSubscribe` channel option is set to `false`.
 *
 * Note that if you want to receive individual realtime annotations (instead of just the rolled-up summaries), you will need to request the `ARTChannelModeAnnotationSubscribe` in `ARTChannelOptions`, since they are not delivered by default. In general, most clients will not bother with subscribing to individual annotations, and will instead just look at the summary updates.
 *
 * @param onAttach An attach callback function.
 * @param callback A callback containing received annotation.
 *
 * @return An event listener object.
 */
- (ARTEventListener *_Nullable)subscribeWithAttachCallback:(nullable ARTCallback)onAttach callback:(ARTAnnotationCallback)callback;

/**
 * Registers a listener that is called each time an `ARTAnnotation` matching a given `type` is received on the channel.
 *
 * Note that if you want to receive individual realtime annotations (instead of just the rolled-up summaries), you will need to request the `ARTChannelModeAnnotationSubscribe` in `ARTChannelOptions`, since they are not delivered by default. In general, most clients will not bother with subscribing to individual annotations, and will instead just look at the summary updates.
 *
 * @param type A type of the `ARTAnnotation` to register the listener for.
 * @param callback A callback containing received annotation.
 *
 * @return An event listener object.
 */
- (ARTEventListener *_Nullable)subscribe:(NSString *)type callback:(ARTAnnotationCallback)callback;

/**
 * Registers a listener that is called each time an `ARTAnnotation` matching a given `type` is received on the channel. An attach callback may optionally be passed in to this call to be notified of success or failure of the channel `-[ARTRealtimeChannelProtocol attach]` operation. It will not be called if the `ARTRealtimeChannelOptions.attachOnSubscribe` channel option is set to `false`.
 *
 * Note that if you want to receive individual realtime annotations (instead of just the rolled-up summaries), you will need to request the `ARTChannelModeAnnotationSubscribe` in `ARTChannelOptions`, since they are not delivered by default. In general, most clients will not bother with subscribing to individual annotations, and will instead just look at the summary updates.
 *
 * @param type A type of the `ARTAnnotation` to register the listener for.
 * @param onAttach An attach callback function.
 * @param callback A callback containing received annotation.
 *
 * @return An event listener object.
 */
- (ARTEventListener *_Nullable)subscribe:(NSString *)type onAttach:(nullable ARTCallback)onAttach callback:(ARTAnnotationCallback)callback;

/**
 * Deregisters all listeners currently receiving `ARTAnnotation` for the channel.
 */
- (void)unsubscribe;

/**
 * Deregisters a specific listener that is registered to receive `ARTAnnotation` on the channel.
 *
 * @param listener An event listener to unsubscribe.
 */
- (void)unsubscribe:(ARTEventListener *)listener;

/**
 * Deregisters a specific listener that is registered to receive `ARTAnnotation` on the channel for a given type.
 *
 * @param type A specific annotation type to deregister the listeners for.
 * @param listener An event listener to unsubscribe.
 */
- (void)unsubscribe:(NSString *)type listener:(ARTEventListener *)listener;

@end

/**
 * @see See `ARTRealtimeAnnotationsProtocol` for details.
 */
NS_SWIFT_SENDABLE
@interface ARTRealtimeAnnotations : NSObject <ARTRealtimeAnnotationsProtocol>
@end

NS_ASSUME_NONNULL_END
