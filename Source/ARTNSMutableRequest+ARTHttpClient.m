#import "ARTNSMutableRequest+ARTHttpClient.h"

#import "ARTEncoder.h"

@implementation NSMutableURLRequest (ARTHttpClient)

- (void)setAcceptHeader:(id<ARTEncoder>)defaultEncoder encoders:(NSDictionary<NSString *, id<ARTEncoder>> *)encoders {
    NSMutableArray *allEncoders = [NSMutableArray arrayWithArray:[encoders.allValues valueForKeyPath:@"mimeType"]];
    NSString *defaultMimetype = [defaultEncoder mimeType];
    // Make the mime type of the default encoder the first element of the Accept header field
    [allEncoders removeObject:defaultMimetype];
    [allEncoders insertObject:defaultMimetype atIndex:0];
    NSString *accept = [allEncoders componentsJoinedByString:@","];
    [self setValue:accept forHTTPHeaderField:@"Accept"];
}

@end
