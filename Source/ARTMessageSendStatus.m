#import "ARTMessageSendStatus.h"
#import "ARTPublishResult.h"
#import "ARTStatus.h"

@implementation ARTMessageSendStatus

- (instancetype)initWithStatus:(ARTStatus *)status publishResult:(nullable ARTPublishResult *)publishResult {
    self = [super init];
    if (self) {
        _status = status;
        _publishResult = publishResult;
    }
    return self;
}

+ (instancetype)okWithPublishResult:(nullable ARTPublishResult *)publishResult {
    ARTStatus *okStatus = [ARTStatus state:ARTStateOk];
    return [[ARTMessageSendStatus alloc] initWithStatus:okStatus publishResult:publishResult];
}

+ (instancetype)errorWithInfo:(nullable ARTErrorInfo *)errorInfo {
    ARTStatus *errorStatus = [ARTStatus state:ARTStateError info:errorInfo];
    return [[ARTMessageSendStatus alloc] initWithStatus:errorStatus publishResult:nil];
}

@end
