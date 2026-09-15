#import <Foundation/Foundation.h>
#import <AblyPubSubDevice/ARTTypes.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Contains version information for a message, including operation metadata.
 */
@interface ARTMessageVersion : NSObject

/// The serial of the message version.
@property (nullable, readwrite, nonatomic) NSString *serial;

/// The timestamp of the message version.
@property (nullable, readwrite, nonatomic) NSDate *timestamp;

/// The client ID associated with this version.
@property (nullable, readwrite, nonatomic) NSString *clientId;

/// A description of the operation performed.
@property (nullable, readwrite, nonatomic) NSString *descriptionText;

/// Metadata associated with the operation.
@property (nullable, readwrite, nonatomic) NSDictionary<NSString *, NSString *> *metadata;

@end

NS_ASSUME_NONNULL_END
