#import "ARTBaseMessage+Private.h"
#import "ARTErrorInfo.h"

@implementation ARTBaseMessage

- (void)setClientId:(NSString *)clientId {
    if(clientId) {
        const char* c = [clientId UTF8String];
        _clientId = [NSString stringWithUTF8String:c];
    }
    else {
        _clientId = nil;
    }
}

- (id)copyWithZone:(NSZone *)zone {
    ARTBaseMessage *message = [[self.class allocWithZone:zone] init];
    message->_id = self.id;
    message->_clientId = self.clientId;
    message->_timestamp = self.timestamp;
    message->_data = [self.data copy];
    message->_connectionId = self.connectionId;
    message->_encoding = self.encoding;
    message->_extras = self.extras;
    return message;
}

- (id)decodeWithEncoder:(ARTDataEncoder*)encoder error:(NSError **)error {
    ARTDataEncoderOutput *decoded = [encoder decode:self.data encoding:self.encoding];
    if (decoded.errorInfo && error) {
        *error = [NSError errorWithDomain:ARTAblyErrorDomain code:decoded.errorInfo.code userInfo:@{NSLocalizedDescriptionKey: @"decoding failed",
                                                                               NSLocalizedFailureReasonErrorKey: decoded.errorInfo.message}];
    }
    id ret = [self copy];
    ((ARTBaseMessage *)ret).data = decoded.data;
    ((ARTBaseMessage *)ret).encoding = decoded.encoding;
    return ret;
}

- (id)encodeWithEncoder:(ARTDataEncoder*)encoder error:(NSError **)error {
    ARTDataEncoderOutput *encoded = [encoder encode:self.data];
    if (encoded.errorInfo && error) {
        *error = [NSError errorWithDomain:ARTAblyErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: @"encoding failed",
                                                                               NSLocalizedFailureReasonErrorKey: encoded.errorInfo.message}];
    }
    id ret = [self copy];
    ((ARTBaseMessage *)ret).data = encoded.data;
    ((ARTBaseMessage *)ret).encoding = [NSString artAddEncoding:encoded.encoding toString:self.encoding];
    return ret;
}

- (NSString *)description {
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: %p> {\n", self.class, self];
    [description appendFormat:@" id: %@,\n", self.id];
    [description appendFormat:@" clientId: %@,\n", self.clientId];
    [description appendFormat:@" connectionId: %@,\n", self.connectionId];
    [description appendFormat:@" timestamp: %@,\n", self.timestamp];
    [description appendFormat:@" encoding: %@,\n", self.encoding];
    [description appendFormat:@" data: %@\n", self.data];
    [description appendFormat:@" extras: %@\n", self.extras];
    [description appendFormat:@"}"];
    return description;
}

- (NSInteger)messageSize {
    // TO3l8*, TM6
    NSInteger finalResult = 0;
    // TM6d: extras is "the string length of its JSON representation" (per Ably's published
    // message-size accounting), i.e. the number of UTF-16 code units (`NSString.length`),
    // not its UTF-8 byte length.
    finalResult += [[self.extras toJSONString] length];
    // TO3l8f: clientId is measured as its UTF-8 byte length.
    finalResult += [self.clientId lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    if (self.data) {
        if ([self.data isKindOfClass:[NSString class]]) {
            // TM6f: string data is measured as its UTF-8 byte length.
            finalResult += [self.data lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        }
        else if ([self.data isKindOfClass:[NSData class]]) {
            // TM6c: binary data is measured as its size in bytes.
            finalResult += [self.data length];
        }
        else {
            NSError *error = nil;
            NSJSONWritingOptions options;
            if (@available(macOS 10.15, iOS 13.0, tvOS 13.0, *)) {
                options = NSJSONWritingWithoutEscapingSlashes;
            }
            else {
                options = 0; //no specific format
            }
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:self.data
                                                               options:options
                                                                 error:&error];
            if (!error) {
                // TM6b: object/array data is measured as its string length (the number of UTF-16
                // code units) after being JSON-stringified, not its UTF-8 byte length.
                NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                finalResult += [jsonString length];
            }
        }
    }
    return finalResult;
}

- (BOOL)isIdEmpty {
    return self.id == nil || [self.id isEqualToString:@""];
}

@end
