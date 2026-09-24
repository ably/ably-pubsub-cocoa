#import "ARTAnnotation.h"
#import "ARTJsonEncoder.h"
#import "ARTJsonLikeEncoder.h"
#import "ARTAnnotation+Private.h"
#import "ARTNSArray+ARTFunctional.h"
#import "ARTInternalLog.h"

@implementation ARTAnnotation

- (instancetype)initWithId:(NSString *)annotationId
                    action:(ARTAnnotationAction)action
                  clientId:(NSString *)clientId
                      name:(NSString *)name
                     count:(NSNumber *)count
                      data:(id)data
                  encoding:(NSString *)encoding
                 timestamp:(NSDate *)timestamp
                    serial:(NSString *)serial
             messageSerial:(NSString *)messageSerial
                      type:(NSString *)type
                    extras:(id<ARTJsonCompatible>)extras {
    if (self = [self init]) {
        _id = annotationId;
        _action = action;
        _clientId = clientId;
        _name = name;
        _count = count;
        _data = data;
        _encoding = encoding;
        _timestamp = timestamp;
        _serial = serial;
        _messageSerial = messageSerial;
        _type = type;
        _extras = extras;
    }
    return self;
}

- (NSString *)description {
    NSMutableString *description = [[super description] mutableCopy];
    [description deleteCharactersInRange:NSMakeRange(description.length - (description.length>2 ? 2:0), 2)];
    [description appendFormat:@",\n"];
    [description appendFormat:@" id: %@,\n", self.id];
    [description appendFormat:@" action: %@\n", ARTAnnotationActionToStr(self.action)];
    [description appendFormat:@" clientId: %@,\n", self.clientId];
    [description appendFormat:@" name: %@\n", self.name];
    [description appendFormat:@" count: %@\n", self.count];
    [description appendFormat:@" data: %@\n", self.data];
    [description appendFormat:@" encoding: %@,\n", self.encoding];
    [description appendFormat:@" timestamp: %@,\n", self.timestamp];
    [description appendFormat:@" serial: %@\n", self.serial];
    [description appendFormat:@" messageSerial: %@\n", self.messageSerial];
    [description appendFormat:@" type: %@\n", self.type];
    [description appendFormat:@" extras: %@\n", self.extras];
    [description appendFormat:@"}"];
    return description;
}

- (id)copyWithZone:(NSZone *)zone {
    ARTAnnotation *annotation = [[self.class allocWithZone:zone] init];
    annotation->_id = self.id;
    annotation->_clientId = self.clientId;
    annotation->_timestamp = self.timestamp;
    annotation->_data = [self.data copy];
    annotation->_extras = self.extras;
    annotation->_encoding = self.encoding;
    annotation->_action = self.action;
    annotation->_serial = self.serial;
    annotation->_messageSerial = self.messageSerial;
    annotation->_type = self.type;
    annotation->_name = self.name;
    annotation->_count = self.count;
    return annotation;
}

- (id)decodeDataWithEncoder:(ARTDataEncoder*)encoder error:(NSError **)error {
    ARTDataEncoderOutput *decoded = [encoder decode:self.data encoding:self.encoding];
    if (decoded.errorInfo && error) {
        *error = [NSError errorWithDomain:ARTAblyErrorDomain code:decoded.errorInfo.code userInfo:@{NSLocalizedDescriptionKey: @"decoding failed",
                                                                               NSLocalizedFailureReasonErrorKey: decoded.errorInfo.message}];
    }
    id ret = [self copy];
    ((ARTAnnotation *)ret)->_data = decoded.data;
    ((ARTAnnotation *)ret)->_encoding = decoded.encoding;
    return ret;
}

- (id)encodeDataWithEncoder:(ARTDataEncoder*)encoder error:(NSError **)error {
    ARTDataEncoderOutput *encoded = [encoder encode:self.data];
    if (encoded.errorInfo && error) {
        *error = [NSError errorWithDomain:ARTAblyErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: @"encoding failed",
                                                                               NSLocalizedFailureReasonErrorKey: encoded.errorInfo.message}];
    }
    id ret = [self copy];
    ((ARTAnnotation *)ret)->_data = encoded.data;
    ((ARTAnnotation *)ret)->_encoding = [NSString artAddEncoding:encoded.encoding toString:self.encoding];
    return ret;
}

- (NSInteger)annotationSize {
    // TO3l8*
    NSInteger finalResult = 0;
    finalResult += [self.name lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    finalResult += [[self.extras toJSONString] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    finalResult += [self.clientId lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    if (self.data) {
        if ([self.data isKindOfClass:[NSString class]]) {
            finalResult += [self.data lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        }
        else if ([self.data isKindOfClass:[NSData class]]) {
            finalResult += [self.data length];
        }
        else {
            NSError *error = nil;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:self.data
                                                               options:NSJSONWritingWithoutEscapingSlashes // Copied from `ARTBaseMessage.messageSize`
                                                                 error:&error];
            if (!error) {
                finalResult += [jsonData length];
            }
        }
    }
    return finalResult;
}

- (BOOL)isIdEmpty {
    return self.id == nil || [self.id isEqualToString:@""];
}

@end

NSString *ARTAnnotationActionToStr(ARTAnnotationAction action) {
    switch (action) {
        case ARTAnnotationCreate:
            return @"Create"; //0
        case ARTAnnotationDelete:
            return @"Delete"; //1
    }
    return @"Unknown";
}

#pragma mark - ARTEvent

@implementation ARTEvent (AnnotationType)

- (instancetype)initWithAnnotationType:(NSString *)type {
    return [self initWithString:[NSString stringWithFormat:@"ARTAnnotation:%@", type]];
}

+ (instancetype)newWithAnnotationType:(NSString *)type {
    return [[self alloc] initWithAnnotationType:type];
}

@end
