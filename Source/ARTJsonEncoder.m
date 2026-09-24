#import "ARTJsonEncoder.h"
#import "ARTErrorInfo+Private.h"
#import "ARTStatus.h"

@implementation ARTJsonEncoder

- (NSString *)mimeType {
    return @"application/json";
}

- (ARTEncoderFormat)format {
    return ARTEncoderFormatJson;
}

- (NSString *)formatAsString {
    return @"json";
}

- (id)decode:(NSData *)data error:(NSError **)error {
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
}

- (NSData *)encode:(id)obj error:(NSError **)error {
    @try {
        return [NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingSortedKeys error:error];
    }
    @catch (NSException *exception) {
        if (error) {
            *error = [[NSError alloc] initWithDomain:ARTAblyErrorDomain code:ARTClientCodeErrorInvalidType userInfo:@{NSLocalizedDescriptionKey: exception.reason}];
        }
        return nil;
    }
}

@end
