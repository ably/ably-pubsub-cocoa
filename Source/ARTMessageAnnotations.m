#import "ARTDefault.h"
#import "ARTMessageAnnotations.h"

/// Returns an immutable copy of a JSON value. Dictionaries and arrays nested inside it are copied too.
static id ARTImmutableJSONCopy(id value) {
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *copy = [NSMutableDictionary dictionaryWithCapacity:[(NSDictionary *)value count]];
        [(NSDictionary *)value enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            copy[key] = ARTImmutableJSONCopy(obj);
        }];
        return [copy copy];
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *copy = [NSMutableArray arrayWithCapacity:[(NSArray *)value count]];
        for (id element in (NSArray *)value) {
            [copy addObject:ARTImmutableJSONCopy(element)];
        }
        return [copy copy];
    }
    return [value conformsToProtocol:@protocol(NSCopying)] ? [value copy] : value;
}

@implementation ARTMessageAnnotations

- (instancetype)initWithSummary:(nullable ARTJsonObject *)summary {
    self = [super init];
    if (self) {
        _summary = summary ? ARTImmutableJSONCopy(summary) : nil;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    // Immutable, so a copy can share this instance.
    return self;
}

- (void)writeToDictionary:(NSMutableDictionary<NSString *, id> *)dictionary {
    if (self.summary) {
        dictionary[@"summary"] = self.summary;
    }
}

+ (instancetype)createFromDictionary:(nullable NSDictionary<NSString *, id> *)jsonObject {
    id summary = jsonObject[@"summary"];
    return [[ARTMessageAnnotations alloc] initWithSummary:[summary isKindOfClass:[NSDictionary class]] ? summary : @{}];
}

- (NSString *)description {
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: %p> {\n", self.class, self];
    [description appendFormat:@" summary: %@\n", self.summary];
    [description appendFormat:@"}"];
    return description;
}

@end
