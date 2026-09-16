#import "ARTPresenceMessage+Private.h"
#import "ARTStatus.h"

NSString *const ARTPresenceMessageException = @"ARTPresenceMessageException";
NSString *const ARTAblyMessageInvalidPresenceId = @"Received presence message id is invalid %@";

@implementation ARTPresenceMessage

- (instancetype)init {
    self = [super init];
    if (self) {
        // Default
        _action = ARTPresenceEnter;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    ARTPresenceMessage *message = [super copyWithZone:zone];
    message->_action = self.action;
    return message;
}

- (NSString *)description {
    NSMutableString *description = [[super description] mutableCopy];
    [description deleteCharactersInRange:NSMakeRange(description.length - (description.length>2 ? 2:0), 2)];
    [description appendFormat:@",\n"];
    [description appendFormat:@" action: %lu,\n", (unsigned long)self.action];
    [description appendFormat:@"}"];
    return description;
}

- (NSString *)memberKey {
    return [NSString stringWithFormat:@"%@:%@", self.connectionId, self.clientId];
}

- (BOOL)isEqualToPresenceMessage:(ARTPresenceMessage *)presence {
    if (!presence) {
        return NO;
    }

    BOOL haveEqualConnectionId = (!self.connectionId && !presence.connectionId) || [self.connectionId isEqualToString:presence.connectionId];
    BOOL haveEqualCliendId = (!self.clientId && !presence.clientId) || [self.clientId isEqualToString:presence.clientId];

    return haveEqualConnectionId && haveEqualCliendId;
}

- (NSArray<NSString *> *)parseId {
    if (self.id == nil) {
        return nil;
    }
    NSArray<NSString *> *idParts = [self.id componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@":"]];
    if (idParts.count != 3) {
        [ARTException raise:ARTPresenceMessageException format:ARTAblyMessageInvalidPresenceId, self.id];
    }
    return idParts;
}

- (BOOL)isSynthesized {
    return ![self.id hasPrefix:self.connectionId];
}

- (NSInteger)msgSerialFromId {
    NSInteger msgSerial = [[[self parseId] objectAtIndex:1] integerValue];
    return msgSerial;
}

- (NSInteger)indexFromId {
    NSInteger index = [[[self parseId] objectAtIndex:2] integerValue];
    return index;
}

#pragma mark - NSObject

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }

    if (![object isKindOfClass:[ARTPresenceMessage class]]) {
        return NO;
    }

    return [self isEqualToPresenceMessage:(ARTPresenceMessage *)object];
}

- (NSUInteger)hash {
    return [self.connectionId hash] ^ [self.clientId hash];
}

@end

NSString *ARTPresenceActionToStr(ARTPresenceAction action) {
    switch (action) {
        case ARTPresenceAbsent:
            return @"Absent"; //0
        case ARTPresencePresent:
            return @"Present"; //1
        case ARTPresenceEnter:
            return @"Enter"; //2
        case ARTPresenceLeave:
            return @"Leave"; //3
        case ARTPresenceUpdate:
            return @"Update"; //4
        default:
            return @"All";
    }
}

#pragma mark - ARTEvent

@implementation ARTEvent (PresenceAction)

- (instancetype)initWithPresenceAction:(ARTPresenceAction)value {
    return [self initWithString:[NSString stringWithFormat:@"ARTPresenceAction%@", ARTPresenceActionToStr(value)]];
}

+ (instancetype)newWithPresenceAction:(ARTPresenceAction)value {
    return [[self alloc] initWithPresenceAction:value];
}

@end
