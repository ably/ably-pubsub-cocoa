#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTPaginatedResult.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * A superset of `ARTPaginatedResult` which represents a page of results plus metadata indicating the relative queries available to it. `ARTHttpPaginatedResponse` additionally carries information about the response to an HTTP request.
 */
NS_SWIFT_SENDABLE
@interface ARTHTTPPaginatedResponse : ARTPaginatedResult<NSDictionary *>

/**
 * The HTTP status code of the response.
 */
@property (nonatomic, readonly) NSInteger statusCode;

/**
 * Whether `statusCode` indicates success. This is equivalent to `200 <= statusCode < 300`.
 */
@property (nonatomic, readonly) BOOL success;

/**
 * The error code if the `x-ably-errorcode` HTTP header is sent in the response.
 */
@property (nonatomic, readonly) NSInteger errorCode;

/**
 * The error message if the `x-ably-errormessage` HTTP header is sent in the response.
 */
@property (nullable, nonatomic, readonly) NSString *errorMessage;

/**
 * The headers of the response.
 */
@property (nonatomic, readonly) NSStringDictionary *headers;

/**
 * Returns a new `ARTHTTPPaginatedResponse` for the first page of results.
 *
 * @param callback A callback for retriving an `ARTHTTPPaginatedResponse` object with an array of `NSDictionary` objects.
 */
- (void)first:(ARTHTTPPaginatedCallback)callback;

/**
 * Returns a new `ARTHTTPPaginatedResponse` loaded with the next page of results. If there are no further pages, then `nil` is returned.
 *
 * @param callback A callback for retriving an `ARTHTTPPaginatedResponse` object with an array of `NSDictionary` objects.
 */
- (void)next:(ARTHTTPPaginatedCallback)callback;

@end

NS_ASSUME_NONNULL_END
