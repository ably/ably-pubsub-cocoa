#import <AblyPubSubDevice/ARTOutboundAnnotation.h>

@implementation ARTOutboundAnnotation

- (instancetype)initWithId:(nullable NSString *)annotationId
                      type:(NSString *)type
                  clientId:(nullable NSString *)clientId
                      name:(nullable NSString *)name
                     count:(nullable NSNumber *)count
                      data:(nullable id)data
                    extras:(nullable id<ARTJsonCompatible>)extras {
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
                                              extras:self.extras];
}

@end

