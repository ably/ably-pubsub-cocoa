@import Foundation;
#import <AblyPubSubDevice/ARTErrorInfo.h>

#ifdef ABLY_SUPPORTS_PLUGINS
@import _AblyPluginSupportPrivate;
#endif

/**
 The list of all client error codes returned under the error domain ARTAblyErrorDomain
 */
typedef CF_ENUM(NSUInteger, ARTClientCodeError) {
    ARTClientCodeErrorInvalidType,
    ARTClientCodeErrorTransport,
};

NS_ASSUME_NONNULL_BEGIN

#ifdef ABLY_SUPPORTS_PLUGINS
@interface ARTErrorInfo () <APPublicErrorInfo>
@end
#endif

NS_ASSUME_NONNULL_END
