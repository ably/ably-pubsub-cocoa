#import "ARTChannelStateChangeParams.h"
#import "ARTStatus.h"

@implementation ARTChannelStateChangeParams

- (instancetype)initWithState:(ARTState)state {
    return [self initWithState:state errorInfo:nil storeErrorInfo:NO];
}

- (instancetype)initWithState:(ARTState)state errorInfo:(ARTErrorInfo *)errorInfo {
    return [self initWithState:state errorInfo:errorInfo storeErrorInfo:YES];
}

- (instancetype)initWithState:(ARTState)state errorInfo:(ARTErrorInfo *)errorInfo storeErrorInfo:(BOOL)storeErrorInfo {
    return [self initWithState:state errorInfo:errorInfo storeErrorInfo:storeErrorInfo retryAttempt:nil];
}

- (instancetype)initWithState:(ARTState)state errorInfo:(ARTErrorInfo *)errorInfo storeErrorInfo:(BOOL)storeErrorInfo retryAttempt:(ARTRetryAttempt *)retryAttempt {
    if (self = [super init]) {
        _state = state;
        _errorInfo = errorInfo;
        _storeErrorInfo = storeErrorInfo;
        _retryAttempt = retryAttempt;
    }

    return self;
}

@end
