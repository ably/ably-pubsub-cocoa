#import "ARTErrorChecker.h"
#import "ARTTypes.h"
#import "ARTErrorInfo.h"

@implementation ARTDefaultErrorChecker

- (BOOL)isTokenError:(ARTErrorInfo *)errorInfo {
    // RTH15h1
    return errorInfo.statusCode == 401 && errorInfo.code >= ARTErrorTokenErrorUnspecified && errorInfo.code < ARTErrorConnectionLimitsExceeded;
}

@end
