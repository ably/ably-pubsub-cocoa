@import XCTest;
@import AblyPubSubDevice;

@interface ARTMessageVersionAndAnnotationsTests : XCTestCase
@end

@implementation ARTMessageVersionAndAnnotationsTests

// The classes are Sendable, so changing an argument after initialization must not reach the instance.
- (void)test_version_does_not_change_when_its_arguments_are_mutated {
    NSMutableString *const serial = [NSMutableString stringWithString:@"124"];
    NSMutableString *const metadataValue = [NSMutableString stringWithString:@"typo"];
    NSMutableDictionary<NSString *, NSString *> *const metadata = [NSMutableDictionary dictionaryWithObject:metadataValue forKey:@"reason"];

    ARTMessageVersion *const version = [[ARTMessageVersion alloc] initWithSerial:serial
                                                                       timestamp:nil
                                                                        clientId:nil
                                                                 descriptionText:nil
                                                                        metadata:metadata];
    [serial appendString:@"-changed"];
    [metadataValue appendString:@"-changed"];
    metadata[@"added"] = @"value";

    XCTAssertEqualObjects(version.serial, @"124");
    XCTAssertEqualObjects(version.metadata, @{@"reason": @"typo"});
}

- (void)test_annotations_do_not_change_when_a_nested_summary_value_is_mutated {
    NSMutableArray *const clientIds = [NSMutableArray arrayWithObject:@"a"];
    NSMutableDictionary *const reaction = [NSMutableDictionary dictionaryWithObject:clientIds forKey:@"clientIds"];
    NSMutableDictionary *const summary = [NSMutableDictionary dictionaryWithObject:reaction forKey:@"reaction:distinct.v1"];

    ARTMessageAnnotations *const annotations = [[ARTMessageAnnotations alloc] initWithSummary:summary];
    [clientIds addObject:@"b"];
    reaction[@"total"] = @2;
    summary[@"added"] = @{};

    XCTAssertEqualObjects(annotations.summary, @{@"reaction:distinct.v1": @{@"clientIds": @[@"a"]}});
}

- (void)test_copy_returns_the_same_instance {
    ARTMessageVersion *const version = [[ARTMessageVersion alloc] initWithSerial:@"124" timestamp:nil clientId:nil descriptionText:nil metadata:nil];
    ARTMessageAnnotations *const annotations = [[ARTMessageAnnotations alloc] initWithSummary:@{}];

    XCTAssertEqual([version copy], version);
    XCTAssertEqual([annotations copy], annotations);
}

@end
