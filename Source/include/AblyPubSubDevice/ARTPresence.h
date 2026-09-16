#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTTypes.h>
#import <AblyPubSubDevice/ARTPresenceMessage.h>
#import <AblyPubSubDevice/ARTPaginatedResult.h>
#import <AblyPubSubDevice/ARTDataQuery.h>

NS_ASSUME_NONNULL_BEGIN

/**
 This object is used for providing parameters into the presence methods with paginated results.
 */
@interface ARTPresenceQuery : NSObject

/**
 * An upper limit on the number of messages returned. The default is 100, and the maximum is 1000.
 */
@property (nonatomic, readwrite) NSUInteger limit;

/**
 * Filters the array of returned presence members by a specific client using its ID.
 */
@property (nullable, nonatomic, readwrite) NSString *clientId;

/**
 * Filters the array of returned presence members by a specific connection using its ID.
 */
@property (nullable, nonatomic, readwrite) NSString *connectionId;

/// :nodoc:
- (instancetype)init;

/// :nodoc:
- (instancetype)initWithClientId:(NSString *_Nullable)clientId connectionId:(NSString *_Nullable)connectionId;

/// :nodoc:
- (instancetype)initWithLimit:(NSUInteger)limit clientId:(NSString *_Nullable)clientId connectionId:(NSString *_Nullable)connectionId;

@end

/// :nodoc:
@interface ARTPresence : NSObject

- (void)history:(ARTPaginatedPresenceCallback)callback;

@end

NS_ASSUME_NONNULL_END
