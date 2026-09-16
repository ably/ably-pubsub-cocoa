#import <Foundation/Foundation.h>

#import "ARTErrorInfo.h"
#import "ARTNSError+ARTUtils.h"
#import "ARTErrorInfo+Private.h"

// Reverse-DNS style domain
NSString *const ARTAblyErrorDomain = @"io.ably.cocoa";

NSString *const ARTErrorInfoStatusCodeKey = @"ARTErrorInfoStatusCode";
NSString *const ARTErrorInfoOriginalDomainKey = @"ARTErrorInfoOriginalDomain";
NSString *const ARTErrorInfoRequestIdKey = @"ARTErrorInfoRequestId";


NSString *const ARTAblyMessageNoMeansToRenewToken = @"no means to renew the token is provided (either an API key, authCallback or authUrl)";

NSInteger getStatusFromCode(NSInteger code) {
    return code / 100;
}

@implementation ARTErrorInfo

+ (ARTErrorInfo *)createWithCode:(NSInteger)code message:(NSString *)message requestId:(nullable NSString *)requestId {
    return [ARTErrorInfo createWithCode:code status:getStatusFromCode(code) message:message requestId:requestId];
}

+ (ARTErrorInfo *)createWithCode:(NSInteger)code message:(NSString *)message requestId:(nullable NSString *)requestId additionalUserInfo:(nullable NSDictionary<NSString *, id> *)additionalUserInfo {
    return [ARTErrorInfo createWithCode:code status:getStatusFromCode(code) message:message requestId:requestId additionalUserInfo:additionalUserInfo];
}

+ (ARTErrorInfo *)createWithCode:(NSInteger)code message:(NSString *)message {
    return [ARTErrorInfo createWithCode:code status:getStatusFromCode(code) message:message requestId:nil];
}

+ (ARTErrorInfo *)createWithCode:(NSInteger)code message:(NSString *)message additionalUserInfo:(nullable NSDictionary<NSString *, id> *)additionalUserInfo {
    return [ARTErrorInfo createWithCode:code status:getStatusFromCode(code) message:message requestId:nil additionalUserInfo:additionalUserInfo];
}

+ (ARTErrorInfo *)createWithCode:(NSInteger)code status:(NSInteger)status message:(NSString *)message additionalUserInfo:(nullable NSDictionary<NSString *, id> *)additionalUserInfo {
    return [ARTErrorInfo createWithCode:code status:status message:message requestId:nil additionalUserInfo:additionalUserInfo];
}

+ (ARTErrorInfo *)createWithCode:(NSInteger)code status:(NSInteger)status message:(NSString *)message requestId:(nullable NSString *)requestId {
    return [ARTErrorInfo createWithCode:code status:status message:message requestId:requestId additionalUserInfo:nil];
}

+ (ARTErrorInfo *)createWithCode:(NSInteger)code status:(NSInteger)status message:(NSString *)message requestId:(nullable NSString *)requestId additionalUserInfo:(nullable NSDictionary<NSString *, id> *)additionalUserInfo {
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    userInfo[ARTErrorInfoStatusCodeKey] = [NSNumber numberWithInteger:status];
    userInfo[NSLocalizedDescriptionKey] = message;
    userInfo[ARTErrorInfoRequestIdKey] = requestId;

    // Add any additional userInfo values
    if (additionalUserInfo) {
        [userInfo addEntriesFromDictionary:additionalUserInfo];
    }

    return [[ARTErrorInfo alloc] initWithDomain:ARTAblyErrorDomain code:code userInfo:userInfo];
}

+ (ARTErrorInfo *)createWithCode:(NSInteger)code status:(NSInteger)status message:(NSString *)message {
    return [ARTErrorInfo createWithCode:code status:status message:message requestId:nil];
}

+ (ARTErrorInfo *)createFromNSError:(NSError *)error {
    if ([error isKindOfClass:[ARTErrorInfo class]]) {
        return (ARTErrorInfo *)error;
    }

    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:error.userInfo];
    userInfo[ARTErrorInfoOriginalDomainKey] = error.domain;
    userInfo[ARTErrorInfoRequestIdKey] = error.requestId;

    return [[ARTErrorInfo alloc] initWithDomain:ARTAblyErrorDomain code:error.code userInfo:userInfo];
}

+ (ARTErrorInfo *)createFromNSException:(NSException *)error requestId:(nullable NSString *)requestId {
    ARTErrorInfo *e = [self createWithCode:0 message:[NSString stringWithFormat:@"%@: %@", error.name, error.reason] requestId:requestId];
    for (NSString *k in error.userInfo) {
        [e.userInfo setValue:error.userInfo[k] forKey:k];
    }
    return e;
}

+ (ARTErrorInfo *)createFromNSException:(NSException *)error {
    return [ARTErrorInfo createFromNSException:error requestId:nil];
}

+ (ARTErrorInfo *)createUnknownError {
    return [ARTErrorInfo createWithCode:0 message:@"Unknown error" requestId:nil];
}

+ (ARTErrorInfo *)wrap:(ARTErrorInfo *)error prepend:(NSString *)prepend {
    return [ARTErrorInfo
            createWithCode:error.code
            status:error.statusCode
            message:[NSString stringWithFormat:@"%@%@", prepend, error.message]
            requestId:error.requestId];
}

- (NSString *)message {
    NSString *description = (NSString *)self.userInfo[NSLocalizedDescriptionKey];
    if (!description || [description isEqualToString:@""]) {
        description = [self reason];
    }
    return description;
}

- (NSString *)reason {
    NSString *reason = (NSString *)self.userInfo[NSLocalizedFailureReasonErrorKey];
    if (!reason || [reason isEqualToString:@""]) {
        reason = (NSString *)self.userInfo[@"NSDebugDescription"];
    }
    if (!reason || [reason isEqualToString:@""]) {
        reason = (NSString *)self.userInfo[ARTErrorInfoOriginalDomainKey];
    }
    return reason;
}

- (ARTErrorInfo *)cause {
    NSError *underlyingError = self.userInfo[NSUnderlyingErrorKey];
    if (underlyingError == nil) {
        return nil;
    }
    return [ARTErrorInfo createFromNSError:underlyingError];
}

- (NSInteger)statusCode {
    return [self artStatusCode];
}

- (NSString *)description {
    if (self.reason != nil) {
        return [NSString stringWithFormat:@"Error %ld - %@ (reason: %@)", (long)self.code, self.message ?: @"<Empty Message>", self.reason];
    } else {
        return [NSString stringWithFormat:@"Error %ld - %@", (long)self.code, self.message ?: @"<Empty Message>"];
    }
}

- (NSString *)href {
    if (self.statusCode == 0 ) {
        return nil;
    }

    return [@"https://help.ably.io/error/" stringByAppendingFormat:@"%lld", (long long)self.statusCode];
}

- (NSString *)requestId {
    return self.userInfo[ARTErrorInfoRequestIdKey];
}

@end


@implementation NSError (ARTErrorInfo)

- (NSInteger)artStatusCode {
    return [(NSNumber *)self.userInfo[ARTErrorInfoStatusCodeKey] integerValue];
}

@end
