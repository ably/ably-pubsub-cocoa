#import <Foundation/Foundation.h>
#import <AblyPubSubDevice/ARTTypes.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Represents an outbound annotation to be published or deleted.
 *
 * This type is based on ``ARTAnnotation`` but omits the properties that are populated by the Realtime service.
 */
NS_SWIFT_SENDABLE
NS_SWIFT_NAME(OutboundAnnotation)
@interface ARTOutboundAnnotation : NSObject<NSCopying>

// (RSAN1a2) The form of the second argument may accept any language-idiomatic representation (e.g. plain objects in untyped languages), but must allow the user to supply at least the type, clientId, name, count, data, and extras fields

/// An ID assigned (by the publisher or Ably) to this annotation, which is used as the idempotency key.
@property (nullable, readonly, nonatomic) NSString *id;

/// The type of annotation it is, typically some identifier together with an aggregation method; for example: "emoji:distinct.v1". Handled opaquely by the SDK and validated serverside.
@property (readonly, nonatomic) NSString *type;

/// The client ID of the publisher of this annotation.
@property (nullable, readonly, nonatomic) NSString *clientId;

/// The name of this annotation. This is the field that most annotation aggregations will operate on. For example, using "distinct.v1" aggregation (specified in the type), the message summary will show a list of clients who have published an annotation with each distinct annotation.name.
@property (nullable, readonly, nonatomic) NSString *name;

/// An optional count, only relevant to certain aggregation methods, see aggregation methods documentation for more info.
@property (nullable, readonly, nonatomic) NSNumber *count;

/// The annotation payload, if provided.
@property (nullable, readonly, nonatomic) id data;

/// A JSON object of arbitrary key-value pairs that may contain metadata, and/or ancillary payloads.
@property (nullable, readonly, nonatomic) id<ARTJsonCompatible> extras;

- (instancetype)initWithId:(nullable NSString *)annotationId
                      type:(NSString *)type
                  clientId:(nullable NSString *)clientId
                      name:(nullable NSString *)name
                     count:(nullable NSNumber *)count
                      data:(nullable id)data
                    extras:(nullable id<ARTJsonCompatible>)extras;

@end

NS_ASSUME_NONNULL_END

