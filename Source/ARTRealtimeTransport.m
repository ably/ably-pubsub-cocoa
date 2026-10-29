#import <Foundation/Foundation.h>
#import "ARTRealtimeTransport.h"

@implementation ARTRealtimeTransportError

- (instancetype)initWithError:(NSError *)error type:(ARTRealtimeTransportErrorType)type url:(NSURL *)url {
    self = [super init];
    if (self) {
        self.error = error;
        self.type = type;
        self.url = url;
    }
    return self;
}

- (instancetype)initWithError:(NSError *)error badResponseCode:(NSInteger)badResponseCode badResponseServerHeader:(NSString *)badResponseServerHeader url:(NSURL *)url {
    self = [self initWithError:error type:ARTRealtimeTransportErrorTypeBadResponse url:url];
    if (self) {
        self.badResponseCode = badResponseCode;
        self.badResponseServerHeader = badResponseServerHeader;
    }
    return self;
}

- (NSString *)description {
    NSMutableString *description = [NSMutableString stringWithFormat:@"<ARTRealtimeTransportError: %p {\n", self];
    [description appendFormat:@"  type: %@\n", [ARTRealtimeTransportError typeDescription:self.type]];
    [description appendFormat:@"  badResponseCode: %ld\n", (long)self.badResponseCode];
    [description appendFormat:@"  url: %@\n", self.url];
    [description appendFormat:@"  error: %@\n", self.error];
    [description appendFormat:@"}>"];
    return description;
}

+ (NSString *)typeDescription:(ARTRealtimeTransportErrorType)type {
    switch (type) {
    case ARTRealtimeTransportErrorTypeOther:
        return @"Other";
    case ARTRealtimeTransportErrorTypeHostUnreachable:
        return @"Unreachable";
    case ARTRealtimeTransportErrorTypeNoInternet:
        return @"NoInternet";
    case ARTRealtimeTransportErrorTypeTimeout:
        return @"Timeout";
    case ARTRealtimeTransportErrorTypeBadResponse:
        return @"BadResponse";
    case ARTRealtimeTransportErrorTypeRefused:
        return @"Refused";
    }
}

@end
