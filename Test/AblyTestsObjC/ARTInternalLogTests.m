#import <XCTest/XCTest.h>
@import AblyPubSubDevice;
@import AblyPubSubDevice.Private;
@import AblyTesting;

/**
 This file is written in Objective-C because it tests the `ARTLog*` macros defined in `ARTInternalLog.h`, which are not accessible from Swift.
 */
@interface ARTInternalLogTests : XCTestCase

@end

@implementation ARTInternalLogTests

- (void)test_classMethodLogger {
    ARTInternalLog *const logger = ARTInternalLog.sharedClassMethodLogger_readDocumentationBeforeUsing;

    XCTAssertTrue([logger.core isKindOfClass:[ARTDefaultInternalLogCore class]]);
    ARTDefaultInternalLogCore *const core = (ARTDefaultInternalLogCore *)logger.core;
    XCTAssertTrue([core.logger isKindOfClass:[ARTLogAdapter class]]);
    ARTLogAdapter *const logAdapter = (ARTLogAdapter *)core.logger;
    XCTAssertEqual(logAdapter.logger.logLevel, ARTLogLevelNone);
}

- (void)test_ARTLogVerbose {
    ARTMockInternalLogCore *const mock = [[ARTMockInternalLogCore alloc] init];
    mock.logLevel = ARTLogLevelVerbose;
    ARTInternalLog *const internalLog = [[ARTInternalLog alloc] initWithCore:mock];

    const int statementLine = __LINE__ + 1;
    ARTLogVerbose(internalLog, @"Hello %@", @"there");

    XCTAssertEqualObjects(mock.lastReceivedLogMessageArgumentMessage, @"Hello there");
    XCTAssertEqual(mock.lastReceivedLogMessageArgumentLevel, ARTLogLevelVerbose);
    XCTAssertEqual(strcmp(mock.lastReceivedLogMessageArgumentFileName, __FILE__), 0);
    XCTAssertEqual(mock.lastReceivedLogMessageArgumentFileName[0], '/'); // Confirming my assumption that __FILE__ gives an absolute path
    XCTAssertEqual(mock.lastReceivedLogMessageArgumentLine, statementLine);
}

- (void)test_ARTLogDebug {
    ARTMockInternalLogCore *const mock = [[ARTMockInternalLogCore alloc] init];
    mock.logLevel = ARTLogLevelDebug;
    ARTInternalLog *const internalLog = [[ARTInternalLog alloc] initWithCore:mock];

    const int statementLine = __LINE__ + 1;
    ARTLogDebug(internalLog, @"Hello %@", @"there");

    XCTAssertEqualObjects(mock.lastReceivedLogMessageArgumentMessage, @"Hello there");
    XCTAssertEqual(mock.lastReceivedLogMessageArgumentLevel, ARTLogLevelDebug);
    XCTAssertEqual(strcmp(mock.lastReceivedLogMessageArgumentFileName, __FILE__), 0);
    XCTAssertEqual(mock.lastReceivedLogMessageArgumentFileName[0], '/'); // Confirming my assumption that __FILE__ gives an absolute path
    XCTAssertEqual(mock.lastReceivedLogMessageArgumentLine, statementLine);
}

- (void)test_ARTLogInfo {
    ARTMockInternalLogCore *const mock = [[ARTMockInternalLogCore alloc] init];
    mock.logLevel = ARTLogLevelInfo;
    ARTInternalLog *const internalLog = [[ARTInternalLog alloc] initWithCore:mock];

    const int statementLine = __LINE__ + 1;
    ARTLogInfo(internalLog, @"Hello %@", @"there");

    XCTAssertEqualObjects(mock.lastReceivedLogMessageArgumentMessage, @"Hello there");
    XCTAssertEqual(mock.lastReceivedLogMessageArgumentLevel, ARTLogLevelInfo);
    XCTAssertEqual(strcmp(mock.lastReceivedLogMessageArgumentFileName, __FILE__), 0);
    XCTAssertEqual(mock.lastReceivedLogMessageArgumentFileName[0], '/'); // Confirming my assumption that __FILE__ gives an absolute path
    XCTAssertEqual(mock.lastReceivedLogMessageArgumentLine, statementLine);
}

- (void)test_ARTLogWarn {
    ARTMockInternalLogCore *const mock = [[ARTMockInternalLogCore alloc] init];
    mock.logLevel = ARTLogLevelWarn;
    ARTInternalLog *const internalLog = [[ARTInternalLog alloc] initWithCore:mock];

    const int statementLine = __LINE__ + 1;
    ARTLogWarn(internalLog, @"Hello %@", @"there");

    XCTAssertEqualObjects(mock.lastReceivedLogMessageArgumentMessage, @"Hello there");
    XCTAssertEqual(mock.lastReceivedLogMessageArgumentLevel, ARTLogLevelWarn);
    XCTAssertEqual(strcmp(mock.lastReceivedLogMessageArgumentFileName, __FILE__), 0);
    XCTAssertEqual(mock.lastReceivedLogMessageArgumentFileName[0], '/'); // Confirming my assumption that __FILE__ gives an absolute path
    XCTAssertEqual(mock.lastReceivedLogMessageArgumentLine, statementLine);
}

- (void)test_ARTLogError {
    ARTMockInternalLogCore *const mock = [[ARTMockInternalLogCore alloc] init];
    mock.logLevel = ARTLogLevelError;
    ARTInternalLog *const internalLog = [[ARTInternalLog alloc] initWithCore:mock];

    const int statementLine = __LINE__ + 1;
    ARTLogError(internalLog, @"Hello %@", @"there");

    XCTAssertEqualObjects(mock.lastReceivedLogMessageArgumentMessage, @"Hello there");
    XCTAssertEqual(mock.lastReceivedLogMessageArgumentLevel, ARTLogLevelError);
    XCTAssertEqual(strcmp(mock.lastReceivedLogMessageArgumentFileName, __FILE__), 0);
    XCTAssertEqual(mock.lastReceivedLogMessageArgumentFileName[0], '/'); // Confirming my assumption that __FILE__ gives an absolute path
    XCTAssertEqual(mock.lastReceivedLogMessageArgumentLine, statementLine);
}

@end
