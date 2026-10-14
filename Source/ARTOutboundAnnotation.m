#import <AblyPubSubDevice/ARTOutboundAnnotation.h>
#import "ARTOutboundAnnotation+Private.h"
#import "ARTJsonEncoder.h"
#import "ARTJsonLikeEncoder.h"

@implementation ARTOutboundAnnotation

- (instancetype)initWithId:(nullable NSString *)annotationId
                      type:(NSString *)type
                  clientId:(nullable NSString *)clientId
                      name:(nullable NSString *)name
                     count:(nullable NSNumber *)count
                      data:(nullable id)data
                    extras:(nullable id<ARTJsonCompatible>)extras {
    return [self initWithId:annotationId
                       type:type
                   clientId:clientId
                       name:name
                      count:count
                       data:data
                     extras:extras
                     action:ARTAnnotationCreate
              messageSerial:nil
                   encoding:nil];
}

- (instancetype)initWithId:(nullable NSString *)annotationId
                      type:(NSString *)type
                  clientId:(nullable NSString *)clientId
                      name:(nullable NSString *)name
                     count:(nullable NSNumber *)count
                      data:(nullable id)data
                    extras:(nullable id<ARTJsonCompatible>)extras
                    action:(ARTAnnotationAction)action
             messageSerial:(nullable NSString *)messageSerial
                  encoding:(nullable NSString *)encoding {
    // (RSAN1a3) - The SDK must validate that the user supplied `type` (All other fields are optional)
    // (TAN2k) type string: a string indicating the type of the annotation, handled opaquely by the SDK
    NSAssert(type, @"ARTOutboundAnnotation: No annotation `type` provided");

    if (self = [super init]) {
        _id = annotationId;
        _type = type;
        _clientId = clientId;
        _name = name;
        _count = count;
        _data = data;
        _extras = extras;
        _action = action;
        _messageSerial = messageSerial;
        _encoding = encoding;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    return [[ARTOutboundAnnotation alloc] initWithId:self.id
                                                type:self.type
                                            clientId:self.clientId
                                                name:self.name
                                               count:self.count
                                                data:self.data
                                              extras:self.extras
                                              action:self.action
                                       messageSerial:self.messageSerial
                                            encoding:self.encoding];
}

- (instancetype)annotationForPublishingWithId:(nullable NSString *)annotationId
                                       action:(ARTAnnotationAction)action
                                messageSerial:(NSString *)messageSerial {
    return [[ARTOutboundAnnotation alloc] initWithId:annotationId
                                                type:self.type
                                            clientId:self.clientId
                                                name:self.name
                                               count:self.count
                                                data:self.data
                                              extras:self.extras
                                              action:action
                                       messageSerial:messageSerial
                                            encoding:self.encoding];
}

- (id)encodeDataWithEncoder:(ARTDataEncoder *)encoder error:(NSError **)error {
    ARTDataEncoderOutput *encoded = [encoder encode:self.data];
    if (encoded.errorInfo && error) {
        *error = [NSError errorWithDomain:ARTAblyErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: @"encoding failed",
                                                                               NSLocalizedFailureReasonErrorKey: encoded.errorInfo.message}];
    }
    return [[ARTOutboundAnnotation alloc] initWithId:self.id
                                                type:self.type
                                            clientId:self.clientId
                                                name:self.name
                                               count:self.count
                                                data:encoded.data
                                              extras:self.extras
                                              action:self.action
                                       messageSerial:self.messageSerial
                                            encoding:[NSString artAddEncoding:encoded.encoding toString:self.encoding]];
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

@end
