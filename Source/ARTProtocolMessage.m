#import "ARTDefault.h"
#import "ARTProtocolMessage.h"
#import "ARTProtocolMessage+Private.h"
#import "ARTErrorInfo.h"
#import "ARTConnectionDetails.h"
#import "ARTNSString+ARTUtil.h"
#import "ARTNSArray+ARTFunctional.h"

@implementation ARTProtocolMessage

- (id)init {
    self = [super init];
    if (self) {
        _count = 0;
        _id = nil;
        _channel = nil;
        _channelSerial = nil;
        _connectionId = nil;
        _connectionKey = nil;
        _msgSerial = nil;
        _timestamp = nil;
        _messages = nil;
        _presence = nil;
        _annotations = nil;
        _flags = 0;
        _error = nil;
        _connectionDetails = nil;
        _res = nil;
    }
    return self;
}

- (NSString *)getConnectionKey {
    if (_connectionDetails && _connectionDetails.connectionKey) {
        return _connectionDetails.connectionKey;
    }
    return _connectionKey;
}

- (NSString *)description {
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: %p> {\n", self.class, self];
    [description appendFormat:@" count: %d,\n", self.count];
    [description appendFormat:@" id: %@,\n", self.id];
    [description appendFormat:@" action: %lu (%@),\n", (unsigned long)self.action, ARTProtocolMessageActionToStr(self.action)];
    [description appendFormat:@" channel: %@,\n", self.channel];
    [description appendFormat:@" channelSerial: %@,\n", self.channelSerial];
    [description appendFormat:@" connectionId: %@,\n", self.connectionId];
    [description appendFormat:@" connectionKey: %@,\n", self.connectionKey];
    [description appendFormat:@" msgSerial: %@,\n", self.msgSerial];
    [description appendFormat:@" timestamp: %@,\n", self.timestamp];
    [description appendFormat:@" flags: %lld,\n", self.flags];
    [description appendFormat:@" flags.hasPresence: %@,\n", NSStringFromBOOL(self.hasPresence)];
    [description appendFormat:@" flags.hasObjects: %@,\n", NSStringFromBOOL(self.hasObjects)];
    [description appendFormat:@" flags.hasBacklog: %@,\n", NSStringFromBOOL(self.hasBacklog)];
    [description appendFormat:@" flags.resumed: %@,\n", NSStringFromBOOL(self.resumed)];
    [description appendFormat:@" messages: %@\n", self.messages];
    [description appendFormat:@" presence: %@\n", self.presence];
    [description appendFormat:@" annotations: %@\n", self.annotations];
    [description appendFormat:@" params: %@\n", self.params];
    [description appendFormat:@" res: %@\n", self.res];
    [description appendFormat:@"}"];
    return description;
}

- (id)copyWithZone:(NSZone *)zone {
    ARTProtocolMessage *pm = [[[self class] allocWithZone:zone] init];
    pm.action = self.action;
    pm.count = self.count;
    pm.id = self.id;
    pm.channel = self.channel;
    pm.channelSerial = self.channelSerial;
    pm.connectionId = self.connectionId;
    pm.connectionKey = self.connectionKey;
    pm.msgSerial = self.msgSerial;
    pm.timestamp = self.timestamp;
    pm.messages = self.messages;
    pm.presence = self.presence;
    pm.annotations = self.annotations;
    pm.flags = self.flags;
    pm.error = self.error;
    pm.connectionDetails = self.connectionDetails;
    pm.params = self.params;
    pm.res = self.res;
    return pm;
}

- (BOOL)ackRequired {
    // RTN7a
    return self.action == ARTProtocolMessageMessage
    || self.action == ARTProtocolMessagePresence
    || self.action == ARTProtocolMessageAnnotation
    || self.action == ARTProtocolMessageObject;
}

- (BOOL)hasPresence {
    return self.flags & ARTProtocolMessageFlagHasPresence;
}

- (BOOL)hasObjects {
    return self.flags & ARTProtocolMessageFlagHasObjects;
}

- (BOOL)hasBacklog {
    return self.flags & ARTProtocolMessageFlagHasBacklog;
}

- (BOOL)resumed {
    return self.flags & ARTProtocolMessageFlagResumed;
}

- (ARTConnectionDetails *)getConnectionDetails {
    return _connectionDetails;
}

- (ARTChannelMode)channelModes {
    return self.flags & 0xFFFF0000; // remove flags that are not modes (less then 1UL << 16) per TB2d
}

@end

NSString* ARTProtocolMessageActionToStr(ARTProtocolMessageAction action) {
    switch(action) {
        case ARTProtocolMessageHeartbeat:
            return @"Heartbeat"; //0
        case ARTProtocolMessageAck:
            return @"Ack"; //1
        case ARTProtocolMessageNack:
            return @"Nack"; //2
        case ARTProtocolMessageConnect:
            return @"Connect"; //3
        case ARTProtocolMessageConnected:
            return @"Connected"; //4
        case ARTProtocolMessageDisconnect:
            return @"Disconnect"; //5
        case ARTProtocolMessageDisconnected:
            return @"Disconnected"; //6
        case ARTProtocolMessageClose:
            return @"Close"; //7
        case ARTProtocolMessageClosed:
            return @"Closed"; //8
        case ARTProtocolMessageError:
            return @"Error"; //9
        case ARTProtocolMessageAttach:
            return @"Attach"; //10
        case ARTProtocolMessageAttached:
            return @"Attached"; //11
        case ARTProtocolMessageDetach:
            return @"Detach"; //12
        case ARTProtocolMessageDetached:
            return @"Detached"; //13
        case ARTProtocolMessagePresence:
            return @"Presence"; //14
        case ARTProtocolMessageMessage:
            return @"Message"; //15
        case ARTProtocolMessageSync:
            return @"Sync"; //16
        case ARTProtocolMessageAuth:
            return @"Auth"; //17
        case ARTProtocolMessageObject:
            return @"Object"; //19
        case ARTProtocolMessageObjectSync:
            return @"ObjectSync"; //20
        case ARTProtocolMessageAnnotation:
            return @"Annotation"; //21
    }

    // Because we blindly assign the action field of a ProtocolMessage received over the wire to a variable of type ARTProtocolMessageAction, we can't rely on the compiler's exhaustive checking of switch statements for ARTProtocolMessageAction.
    //
    // TODO: we have https://github.com/ably/specification/issues/304 for making sure we properly implement the RSF1 robustness principle for enums.
    return @"Unknown";
}
