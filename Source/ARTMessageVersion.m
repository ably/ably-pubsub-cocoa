#import "ARTDefault.h"
#import "ARTMessageVersion.h"
#import "ARTMessageOperation.h"
#import "ARTNSDate+ARTUtil.h"
#import "ARTNSDictionary+ARTDictionaryUtil.h"

@implementation ARTMessageVersion

- (instancetype)initWithSerial:(nullable NSString *)serial
                     timestamp:(nullable NSDate *)timestamp
                      clientId:(nullable NSString *)clientId
               descriptionText:(nullable NSString *)descriptionText
                      metadata:(nullable NSDictionary<NSString *, NSString *> *)metadata {
    self = [super init];
    if (self) {
        _serial = [serial copy];
        _timestamp = [timestamp copy];
        _clientId = [clientId copy];
        _descriptionText = [descriptionText copy];
        _metadata = metadata ? [[NSDictionary alloc] initWithDictionary:metadata copyItems:YES] : nil;
    }
    return self;
}

- (instancetype)initWithOperation:(ARTMessageOperation *)operation {
    return [self initWithSerial:nil
                      timestamp:nil
                       clientId:operation.clientId
                descriptionText:operation.descriptionText
                       metadata:operation.metadata];
}

- (id)copyWithZone:(NSZone *)zone {
    // Immutable, so a copy can share this instance.
    return self;
}

- (void)writeToDictionary:(NSMutableDictionary<NSString *, id> *)dictionary {
    if (self.serial) {
        dictionary[@"serial"] = self.serial;
    }
    if (self.timestamp) {
        dictionary[@"timestamp"] = [self.timestamp artToNumberMs];
    }
    if (self.clientId) {
        dictionary[@"clientId"] = self.clientId;
    }
    if (self.descriptionText) {
        dictionary[@"description"] = self.descriptionText;
    }
    if (self.metadata) {
        dictionary[@"metadata"] = self.metadata;
    }
}

+ (instancetype)createFromDictionary:(nullable NSDictionary<NSString *, id> *)jsonObject
                       defaultSerial:(nullable NSString *)defaultSerial
                    defaultTimestamp:(nullable NSDate *)defaultTimestamp {
    return [[ARTMessageVersion alloc] initWithSerial:[jsonObject artString:@"serial"] ?: defaultSerial
                                           timestamp:[jsonObject artTimestamp:@"timestamp"] ?: defaultTimestamp
                                            clientId:[jsonObject artString:@"clientId"]
                                     descriptionText:[jsonObject artString:@"description"]
                                            metadata:[self metadataFromJSONValue:jsonObject[@"metadata"]]];
}

/// Keeps only the string-to-string entries of a decoded `metadata` value, which is all that the property's type allows.
+ (nullable NSDictionary<NSString *, NSString *> *)metadataFromJSONValue:(nullable id)value {
    if (![value isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSMutableDictionary<NSString *, NSString *> *metadata = [NSMutableDictionary dictionary];
    [(NSDictionary *)value enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if ([key isKindOfClass:[NSString class]] && [obj isKindOfClass:[NSString class]]) {
            metadata[key] = obj;
        }
    }];
    return metadata;
}

- (NSString *)description {
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: %p> {\n", self.class, self];
    [description appendFormat:@" serial: %@,\n", self.serial];
    [description appendFormat:@" timestamp: %@,\n", self.timestamp];
    [description appendFormat:@" clientId: %@,\n", self.clientId];
    [description appendFormat:@" descriptionText: %@,\n", self.descriptionText];
    [description appendFormat:@" metadata: %@\n", self.metadata];
    [description appendFormat:@"}"];
    return description;
}

@end
