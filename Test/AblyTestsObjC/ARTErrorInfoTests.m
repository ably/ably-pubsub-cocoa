@import XCTest;
@import AblyPubSubDevice;

@interface ARTErrorInfoTests : XCTestCase
@end

@implementation ARTErrorInfoTests

// A transport that disconnects without an error passes nil, which Swift can't.
- (void)test_createFromNSError_with_nil_does_not_crash {
    NSError *const error = nil;

    ARTErrorInfo *const errorInfo = [ARTErrorInfo createFromNSError:error];

    XCTAssertEqualObjects(errorInfo.domain, ARTAblyErrorDomain);
    XCTAssertEqual(errorInfo.code, 0);
}

@end
