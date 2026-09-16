#import <Foundation/Foundation.h>

#import "ARTJsonLikeEncoder.h"
#import "ARTTimeProvider.h"
#import "ARTClientOptions+TestConfiguration.h"
#import "ARTTestClientOptions.h"

#import "ARTMessage.h"
#import "ARTMessage+Private.h"
#import "ARTPresence.h"
#import "ARTPresenceMessage.h"
#import "ARTAnnotation.h"
#import "ARTMessageVersion.h"
#import "ARTMessageAnnotations.h"
#import "ARTMessageVersion+Private.h"
#import "ARTMessageAnnotations+Private.h"
#import "ARTProtocolMessage.h"
#import "ARTProtocolMessage+Private.h"
#import "ARTPublishResult.h"
#import "ARTPublishResultSerial.h"
#import "ARTUpdateDeleteResult.h"
#import "ARTNSDictionary+ARTDictionaryUtil.h"
#import "ARTNSDate+ARTUtil.h"
#import "ARTInternalLog.h"
#import "ARTHTTPExecutor.h"
#import "ARTStatus.h"
#import "ARTTokenDetails.h"
#import "ARTTokenRequest.h"
#import "ARTAuthDetails.h"
#import "ARTPush.h"
#import "ARTDeviceDetails.h"
#import "ARTDeviceDetails+Private.h"
#import "ARTDeviceIdentityTokenDetails.h"
#import "ARTDevicePushDetails.h"
#import "ARTDevicePushDetails+Private.h"
#import "ARTConnectionDetails.h"
#import "ARTHttpClient+Private.h"
#import "ARTJsonEncoder.h"
#import "ARTPushChannelSubscription.h"
#import "ARTClientOptions+Private.h"

#ifdef ABLY_SUPPORTS_PLUGINS
#import "ARTPluginDecodingContext.h"
@import _AblyPluginSupportPrivate;
#endif

@implementation ARTJsonLikeEncoder {
    __weak ARTHttpClientInternal *_rest; // weak because rest owns self
    ARTInternalLog *_logger;
    id<ARTTimeProvider> _timeProvider;
}

- (instancetype)initWithDelegate:(id<ARTJsonLikeEncoderDelegate>)delegate timeProvider:(id<ARTTimeProvider>)timeProvider {
    if (self = [super init]) {
        _rest = nil;
        _logger = nil;
        _delegate = delegate;
        _timeProvider = timeProvider;
    }
    return self;
}

- (instancetype)initWithRest:(ARTHttpClientInternal *)rest delegate:(id<ARTJsonLikeEncoderDelegate>)delegate logger:(ARTInternalLog *)logger {
    if (self = [super init]) {
        _rest = rest;
        _logger = logger;
        _delegate = delegate;
        _timeProvider = rest.options.testOptions.timeProvider;
    }
    return self;
}

- (NSString *)mimeType {
    return [_delegate mimeType];
}

- (ARTEncoderFormat)format {
    return [_delegate format];
}

- (NSString *)formatAsString {
    return [_delegate formatAsString];
}

- (ARTMessage *)decodeMessage:(NSData *)data error:(NSError **)error {
    return [self messageFromDictionary:[self decodeDictionary:data error:error] protocolMessage:nil];
}

- (NSArray *)decodeMessages:(NSData *)data error:(NSError **)error {
    return [self messagesFromArray:[self decodeArray:data error:error] protocolMessage:nil];
}

- (NSArray<ARTAnnotation *> *)decodeAnnotations:(NSData *)data error:(NSError **)error {
    return [self annotationsFromArray:[self decodeArray:data error:error]];
}

- (NSData *)encodeMessage:(ARTMessage *)message error:(NSError **)error {
    return [self encode:[self messageToDictionary:message] error:error];
}

- (NSData *)encodeAnnotation:(ARTAnnotation *)annotation error:(NSError **)error {
    return [self encode:[self annotationToDictionary:annotation] error:error];
}

- (ARTAnnotation *)decodeAnnotation:(NSData *)data error:(NSError **)error {
    return [self annotationFromDictionary:[self decodeDictionary:data error:error]];
}

- (NSData *)encodeMessages:(NSArray *)messages error:(NSError **)error {
    return [self encode:[self messagesToArray:messages] error:error];
}

- (NSData *)encodeAnnotations:(NSArray<ARTAnnotation *> *)annotations error:(NSError **)error {
    return [self encode:[self annotationsToArray:annotations] error:error];
}

- (ARTPresenceMessage *)decodePresenceMessage:(NSData *)data error:(NSError **)error {
    return [self presenceMessageFromDictionary:[self decodeDictionary:data error:error]];
}

- (NSArray *)decodePresenceMessages:(NSData *)data error:(NSError **)error {
    return [self presenceMessagesFromArray:[self decodeArray:data error:error]];
}

- (NSData *)encodePresenceMessage:(ARTPresenceMessage *)message error:(NSError **)error {
    return [self encode:[self presenceMessageToDictionary:message] error:error];
}

- (NSData *)encodePresenceMessages:(NSArray *)messages error:(NSError **)error {
    return [self encode:[self presenceMessagesToArray:messages] error:error];
}

- (NSData *)encodeProtocolMessage:(ARTProtocolMessage *)message error:(NSError **)error {
    return [self encode:[self protocolMessageToDictionary:message] error:error];
}

- (ARTProtocolMessage *)decodeProtocolMessage:(NSData *)data error:(NSError **)error {
    return [self protocolMessageFromDictionary:[self decodeDictionary:data error:error]];
}

- (ARTTokenDetails *)decodeTokenDetails:(NSData *)data error:(NSError **)error {
    return [self tokenFromDictionary:[self decodeDictionary:data error:nil] error:error];
}

- (ARTTokenRequest *)decodeTokenRequest:(NSData *)data error:(NSError **)error {
    return [self tokenRequestFromDictionary:[self decodeDictionary:data error:nil] error:error];
}

- (NSData *)encodeTokenRequest:(ARTTokenRequest *)request error:(NSError **)error {
    return [self encode:[self tokenRequestToDictionary:request] error:error];
}

- (NSData *)encodeTokenDetails:(ARTTokenDetails *)tokenDetails error:(NSError **)error {
    return [self encode:[self tokenDetailsToDictionary:tokenDetails] error:error];
}

- (NSData *)encodeDeviceDetails:(ARTDeviceDetails *)deviceDetails error:(NSError **)error {
    return [self encode:[self deviceDetailsToDictionary:deviceDetails] error:error];
}

- (NSData *)encodeLocalDevice:(ARTLocalDevice *)device error:(NSError **)error {
    return [self encode:[self localDeviceToDictionary:device] error:error];
}

- (ARTDeviceDetails *)decodeDeviceDetails:(NSData *)data error:(NSError **)error {
    return [self deviceDetailsFromDictionary:[self decodeDictionary:data error:nil] error:error];
}

- (ARTChannelDetails *)decodeChannelDetails:(NSData *)data error:(NSError **)error {
    return [self channelDetailsFromDictionary:[self decodeDictionary:data error:error]];
}

- (NSArray<ARTDeviceDetails *> *)decodeDevicesDetails:(NSData *)data error:(NSError * __autoreleasing *)error {
    return [self devicesDetailsFromArray:[self decodeArray:data error:nil] error:error];
}

- (NSArray<ARTDeviceDetails *> *)devicesDetailsFromArray:(NSArray *)input error:(NSError * __autoreleasing *)error {
    NSMutableArray<ARTDeviceDetails *> *output = [NSMutableArray array];
    for (NSDictionary *item in input) {
        ARTDeviceDetails *deviceDetails = [self deviceDetailsFromDictionary:item error:error];
        if (!deviceDetails) {
            return nil;
        }
        [output addObject:deviceDetails];
    }
    return output;
}

- (ARTDeviceIdentityTokenDetails *)decodeDeviceIdentityTokenDetails:(NSData *)data error:(NSError * __autoreleasing *)error {
    return [self deviceIdentityTokenDetailsFromDictionary:[self decodeDictionary:data error:nil] error:error];
}

- (NSData *)encodeDevicePushDetails:(ARTDevicePushDetails *)devicePushDetails error:(NSError **)error {
    return [self encode:[self devicePushDetailsToDictionary:devicePushDetails] error:error];
}

- (ARTDevicePushDetails *)decodeDevicePushDetails:(NSData *)data error:(NSError * __autoreleasing *)error {
    return [self devicePushDetailsFromDictionary:[self decode:data error:nil] error:error];
}

- (NSData *)encodePushChannelSubscription:(ARTPushChannelSubscription *)channelSubscription error:(NSError * __autoreleasing *)error {
    return [self encode:[self pushChannelSubscriptionToDictionary:channelSubscription] error:error];
}

- (ARTPushChannelSubscription *)decodePushChannelSubscription:(NSData *)data error:(NSError * __autoreleasing *)error {
    return [self pushChannelSubscriptionFromDictionary:[self decodeDictionary:data error:nil] error:error];
}

- (NSArray<ARTPushChannelSubscription *> *)decodePushChannelSubscriptions:(NSData *)data error:(NSError * __autoreleasing *)error {
    return [self pushChannelSubscriptionsFromArray:[self decodeArray:data error:nil] error:error];
}

- (NSArray<ARTPushChannelSubscription *> *)pushChannelSubscriptionsFromArray:(NSArray *)input error:(NSError * __autoreleasing *)error {
    NSMutableArray<ARTPushChannelSubscription *> *output = [NSMutableArray array];
    for (NSDictionary *item in input) {
        ARTPushChannelSubscription *subscription = [self pushChannelSubscriptionFromDictionary:item error:error];
        if (!subscription) {
            return nil;
        }
        [output addObject:subscription];
    }
    return output;
}

- (NSDictionary *)pushChannelSubscriptionToDictionary:(ARTPushChannelSubscription *)channelSubscription {
    NSMutableDictionary *output = [NSMutableDictionary dictionary];

    if (channelSubscription.channel) {
        [output setObject:channelSubscription.channel forKey:@"channel"];
    }

    if (channelSubscription.clientId) {
        [output setObject:channelSubscription.clientId forKey:@"clientId"];
    }

    if (channelSubscription.deviceId) {
        [output setObject:channelSubscription.deviceId forKey:@"deviceId"];
    }

    ARTLogVerbose(_logger, @"RS:%p ARTJsonLikeEncoder<%@>: pushChannelSubscriptionToDictionary %@", _rest, [_delegate formatAsString], output);
    return output;
}

- (ARTPushChannelSubscription *)pushChannelSubscriptionFromDictionary:(NSDictionary *)input error:(NSError * __autoreleasing *)error {
    ARTLogVerbose(_logger, @"RS:%p ARTJsonLikeEncoder<%@>: pushChannelSubscriptionFromDictionary %@", _rest, [_delegate formatAsString], input);

    if (![input isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSString *clientId = [input artString:@"clientId"];
    NSString *deviceId = [input artString:@"deviceId"];

    if ((clientId && deviceId) || (!clientId && !deviceId)) {
        ARTLogError(_logger, @"ARTJsonLikeEncoder<%@>: clientId and deviceId are both present or both nil", [_delegate formatAsString]);
        if (error) {
            *error = [NSError errorWithDomain:ARTAblyErrorDomain
                                         code:ARTErrorIncompatibleCredentials
                                     userInfo:@{ NSLocalizedDescriptionKey: @"clientId and deviceId are both present or both nil"}];
        }
        return nil;
    }

    NSString *channelName = [input artString:@"channel"];

    ARTPushChannelSubscription *channelSubscription;
    if (clientId) {
        channelSubscription = [[ARTPushChannelSubscription alloc] initWithClientId:clientId channel:channelName];
    }
    else {
        channelSubscription = [[ARTPushChannelSubscription alloc] initWithDeviceId:deviceId channel:channelName];
    }

    return channelSubscription;
}

- (NSDate *)decodeTime:(NSData *)data error:(NSError **)error {
    NSArray *resp = [self decodeArray:data error:error];
    ARTLogVerbose(_logger, @"RS:%p ARTJsonLikeEncoder<%@>: decodeTime %@", _rest, [_delegate formatAsString], resp);
    if (resp && resp.count == 1) {
        NSNumber *num = resp[0];
        if ([num isKindOfClass:[NSNumber class]]) {
            return [NSDate dateWithTimeIntervalSince1970:millisecondsToTimeInterval(num.doubleValue)];
        }
    }
    return nil;
}

- (NSArray *)decodeStats:(NSData *)data error:(NSError **)error {
    return [self statsFromArray:[self decodeArray:data error:error]];
}

- (ARTMessage *)messageFromDictionary:(NSDictionary *)input protocolMessage:(ARTProtocolMessage *)protocolMessage {
    ARTLogVerbose(_logger, @"RS:%p ARTJsonLikeEncoder<%@>: messageFromDictionary %@", _rest, [_delegate formatAsString], input);
    if (![input isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    ARTMessage *message = [[ARTMessage alloc] init];
    message.id = [input artString:@"id"];
    message.name = [input artString:@"name"];
    message.action = ([input artNumber:@"action"] ?: [[NSNumber alloc] initWithInt:ARTMessageActionCreate]).integerValue;
    message.serial = [input artString:@"serial"];
    message.clientId = [input artString:@"clientId"];
    message.data = [input objectForKey:@"data"];
    message.encoding = [input artString:@"encoding"];
    message.timestamp = [input artTimestamp:@"timestamp"];
    message.connectionId = [input artString:@"connectionId"];
    message.extras = [input objectForKey:@"extras"];

    id version = input[@"version"];
    if ([version isKindOfClass:[NSDictionary class]]) {
        message.version = [ARTMessageVersion createFromDictionary:version];
    } else {
        // TM2s
        message.version = [[ARTMessageVersion alloc] init];
    }

    if (!message.version.serial) { // TM2s1
        message.version.serial = message.serial;
    }

    if (!message.version.timestamp) { // TM2s2
        message.version.timestamp = message.timestamp;
    }

    id annotations = input[@"annotations"];
    if (annotations && [annotations isKindOfClass:[NSDictionary class]]) {
        message.annotations = [ARTMessageAnnotations createFromDictionary:annotations];
    } else {
        // TM2u
        message.annotations = [[ARTMessageAnnotations alloc] init];
    }

    if (!message.annotations.summary) {
        // TM8a
        message.annotations.summary = @{};
    }

    return message;
}

- (NSArray *)messagesFromArray:(NSArray *)input protocolMessage:(ARTProtocolMessage *)protocolMessage {
    if (![input isKindOfClass:[NSArray class]]) {
        return nil;
    }

    NSMutableArray *output = [NSMutableArray array];
    for (NSDictionary *item in input) {
        ARTMessage *message = [self messageFromDictionary:item protocolMessage:protocolMessage];
        if (!message) {
            return nil;
        }
        [output addObject:message];
    }
    return output;
}

- (ARTPresenceAction)presenceActionFromInt:(int) action
{
    switch (action) {
        case 0:
            return ARTPresenceAbsent;
        case 1:
            return ARTPresencePresent;
        case 2:
            return ARTPresenceEnter;
        case 3:
            return ARTPresenceLeave;
        case 4:
            return ARTPresenceUpdate;
    }
    ARTLogError(_logger, @"RS:%p ARTJsonEncoder invalid ARTPresenceAction %d", _rest, action);
    return ARTPresenceAbsent;
}

- (ARTAnnotationAction)annotationActionFromInt:(int)action
{
    switch (action) {
        case 0:
            return ARTAnnotationCreate;
        case 1:
            return ARTAnnotationDelete;
    }
    ARTLogError(_logger, @"RS:%p ARTJsonEncoder invalid ARTAnnotationAction %d", _rest, action);
    return ARTAnnotationCreate;
}

- (int)intFromPresenceMessageAction:(ARTPresenceAction) action
{
    switch (action) {
        case ARTPresenceAbsent:
            return 0;
        case ARTPresencePresent:
            return 1;
        case ARTPresenceEnter:
            return 2;
        case ARTPresenceLeave:
            return 3;
        case ARTPresenceUpdate:
            return 4;
    }
}

- (int)intFromMessageAction:(ARTMessageAction)action
{
    // TM5
    switch (action) {
        case ARTMessageActionCreate:
            return 0;
        case ARTMessageActionUpdate:
            return 1;
        case ARTMessageActionDelete:
            return 2;
        case ARTMessageActionMeta:
            return 3;
        case ARTMessageActionMessageSummary:
            return 4;
        case ARTMessageActionAppend:
            return 5;
    }
}

- (ARTPresenceMessage *)presenceMessageFromDictionary:(NSDictionary *)input {
    ARTLogVerbose(_logger, @"RS:%p ARTJsonLikeEncoder<%@>: presenceMessageFromDictionary %@", _rest, [_delegate formatAsString], input);
    if (![input isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    ARTPresenceMessage *message = [[ARTPresenceMessage alloc] init];
    message.id = [input artString:@"id"];
    message.data = [input objectForKey:@"data"];
    message.encoding = [input artString:@"encoding"];
    message.clientId = [input artString:@"clientId"];
    message.timestamp = [input artTimestamp:@"timestamp"];

    int action = [[input artNumber:@"action"] intValue];

    message.action = [self presenceActionFromInt:action];

    message.connectionId = [input artString:@"connectionId"];
    message.extras = [input objectForKey:@"extras"]; // TP3i

    return message;
}

- (NSArray *)presenceMessagesFromArray:(NSArray *)input {
    if (![input isKindOfClass:[NSArray class]]) {
        return nil;
    }

    NSMutableArray *output = [NSMutableArray array];
    for (NSDictionary *item in input) {
        ARTPresenceMessage *message = [self presenceMessageFromDictionary:item];
        if (!message) {
            return nil;
        }
        [output addObject:message];
    }
    return output;
}

- (ARTAnnotation *)annotationFromDictionary:(NSDictionary *)input {
    ARTLogVerbose(_logger, @"RS:%p ARTJsonLikeEncoder<%@>: annotationFromDictionary %@", _rest, [_delegate formatAsString], input);
    if (![input isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    int action = [[input artNumber:@"action"] intValue];
    ARTAnnotation *annotation = [[ARTAnnotation alloc] initWithId:[input artString:@"id"]
                                                           action:[self annotationActionFromInt:action]
                                                         clientId:[input artString:@"clientId"]
                                                             name:[input artString:@"name"]
                                                            count:[input artNumber:@"count"]
                                                             data:[input objectForKey:@"data"]
                                                         encoding:[input artString:@"encoding"]
                                                        timestamp:[input artTimestamp:@"timestamp"]
                                                           serial:[input artString:@"serial"]
                                                    messageSerial:[input artString:@"messageSerial"]
                                                             type:[input artString:@"type"]
                                                           extras:[input objectForKey:@"extras"]];
    return annotation;
}

- (NSArray *)annotationsFromArray:(NSArray *)input {
    if (![input isKindOfClass:[NSArray class]]) {
        return nil;
    }

    NSMutableArray *output = [NSMutableArray array];
    for (NSDictionary *item in input) {
        ARTAnnotation *annotation = [self annotationFromDictionary:item];
        if (!annotation) {
            return nil;
        }
        [output addObject:annotation];
    }
    return output;
}

- (NSDictionary *)messageToDictionary:(ARTMessage *)message {
    NSMutableDictionary *output = [NSMutableDictionary dictionary];
    if (message.id) {
        [output setObject:message.id forKey:@"id"];
    }

    if (message.timestamp) {
        [output setObject:[message.timestamp artToNumberMs] forKey:@"timestamp"];
    }

    if (message.clientId) {
        [output setObject:message.clientId forKey:@"clientId"];
    }

    if (message.data) {
        [self writeData:message.data encoding:message.encoding toDictionary:output];
    }

    if (message.name) {
        [output setObject:message.name forKey:@"name"];
    }

    if (message.actionIsInternallySet) {
        int action = [self intFromMessageAction:message.action];
        [output setObject:[NSNumber numberWithInt:action] forKey:@"action"];
    }

    if (message.extras) {
        [output setObject:message.extras forKey:@"extras"];
    }

    if (message.connectionId) {
        [output setObject:message.connectionId forKey:@"connectionId"];
    }

    // Handle serial field
    if (message.serial) {
        [output setObject:message.serial forKey:@"serial"];
    }

    // Handle version field - encode as object
    if (message.version) {
        NSMutableDictionary *versionDict = [NSMutableDictionary dictionary];
        [message.version writeToDictionary:versionDict];
        if (versionDict.count > 0) {
            [output setObject:versionDict forKey:@"version"];
        }
    }

    // Handle annotations field
    if (message.annotations) {
        NSMutableDictionary *annotationsDict = [NSMutableDictionary dictionary];
        [message.annotations writeToDictionary:annotationsDict];
        if (annotationsDict.count > 0) {
            [output setObject:annotationsDict forKey:@"annotations"];
        }
    }

    ARTLogVerbose(_logger, @"RS:%p ARTJsonLikeEncoder<%@>: messageToDictionary %@", _rest, [_delegate formatAsString], output);
    return output;
}

- (NSDictionary *)annotationToDictionary:(ARTAnnotation *)annotation {
    NSMutableDictionary *output = [NSMutableDictionary dictionary];

    // Only encode fields that exist in ARTOutboundAnnotation (RSAN1a2)
    if (annotation.id) {
        [output setObject:annotation.id forKey:@"id"];
    }

    [output setObject:@(annotation.action) forKey:@"action"];

    if (annotation.messageSerial) {
        [output setObject:annotation.messageSerial forKey:@"messageSerial"];
    }

    if (annotation.type) {
        [output setObject:annotation.type forKey:@"type"];
    }

    if (annotation.count != nil) {
        [output setObject:annotation.count forKey:@"count"];
    }

    if (annotation.clientId) {
        [output setObject:annotation.clientId forKey:@"clientId"];
    }

    if (annotation.data) {
        [self writeData:annotation.data encoding:annotation.encoding toDictionary:output];
    }

    if (annotation.name) {
        [output setObject:annotation.name forKey:@"name"];
    }

    if (annotation.extras) {
        [output setObject:annotation.extras forKey:@"extras"];
    }

    ARTLogVerbose(_logger, @"RS:%p ARTJsonLikeEncoder<%@>: annotationToDictionary %@", _rest, [_delegate formatAsString], output);
    return output;
}

- (NSDictionary *)authDetailsToDictionary:(ARTAuthDetails *)authDetails {
    NSMutableDictionary *output = [NSMutableDictionary dictionary];

    [output setObject:authDetails.accessToken forKey:@"accessToken"];

    ARTLogVerbose(_logger, @"RS:%p ARTJsonLikeEncoder<%@>: authDetailsToDictionary %@", _rest, [_delegate formatAsString], output);
    return output;
}

- (ARTAuthDetails *)authDetailsFromDictionary:(NSDictionary *)input {
    if (!input) {
        return nil;
    }
    return [[ARTAuthDetails alloc] initWithToken:[input artString:@"accessToken"]];
}

- (nullable ARTPublishResultSerial *)publishResultSerialFromValue:(id)input {
    // input can be NSString or NSNull for nullable strings
    if ([input isKindOfClass:[NSString class]]) {
        return [[ARTPublishResultSerial alloc] initWithValue:(NSString *)input];
    } else if ([input isKindOfClass:[NSNull class]]) {
        return [[ARTPublishResultSerial alloc] initWithValue:nil];
    }
    return nil;
}

- (nullable NSArray<ARTPublishResultSerial *> *)publishResultSerialsFromArray:(NSArray *)input {
    if (![input isKindOfClass:[NSArray class]]) {
        return nil;
    }

    NSMutableArray *output = [NSMutableArray array];
    for (id item in input) {
        ARTPublishResultSerial *serial = [self publishResultSerialFromValue:item];
        if (!serial) {
            return nil;
        }
        [output addObject:serial];
    }
    return output;
}

- (nullable ARTPublishResult *)publishResultFromDictionary:(NSDictionary *)input {
    if (![input isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSArray *serialsArray = [input objectForKey:@"serials"];
    NSArray<ARTPublishResultSerial *> *serials = [self publishResultSerialsFromArray:serialsArray];
    if (!serials) {
        return nil;
    }

    return [[ARTPublishResult alloc] initWithSerials:serials];
}

- (nullable NSArray<ARTPublishResult *> *)publishResultsFromArray:(NSArray *)input {
    if (![input isKindOfClass:[NSArray class]]) {
        return nil;
    }

    NSMutableArray *output = [NSMutableArray array];
    for (NSDictionary *item in input) {
        ARTPublishResult *publishResult = [self publishResultFromDictionary:item];
        if (!publishResult) {
            return nil;
        }
        [output addObject:publishResult];
    }
    return output;
}

- (id)publishResultSerialToValue:(ARTPublishResultSerial *)serial {
    // Convert ARTPublishResultSerial to either NSString or NSNull for nullable strings
    if (serial.value) {
        return serial.value;
    } else {
        return [NSNull null];
    }
}

- (NSArray *)publishResultSerialsToArray:(NSArray<ARTPublishResultSerial *> *)serials {
    NSMutableArray *output = [NSMutableArray array];
    for (ARTPublishResultSerial *serial in serials) {
        id value = [self publishResultSerialToValue:serial];
        [output addObject:value];
    }
    return output;
}

- (NSDictionary *)publishResultToDictionary:(ARTPublishResult *)publishResult {
    NSMutableDictionary *output = [NSMutableDictionary dictionary];
    if (publishResult.serials) {
        output[@"serials"] = [self publishResultSerialsToArray:publishResult.serials];
    }
    return output;
}

- (NSArray *)publishResultsToArray:(NSArray<ARTPublishResult *> *)publishResults {
    NSMutableArray *output = [NSMutableArray array];
    for (ARTPublishResult *publishResult in publishResults) {
        NSDictionary *item = [self publishResultToDictionary:publishResult];
        [output addObject:item];
    }
    return output;
}

- (NSArray *)messagesToArray:(NSArray *)messages {
    NSMutableArray *output = [NSMutableArray array];

    for (ARTMessage *message in messages) {
        NSDictionary *item = [self messageToDictionary:message];
        [output addObject:item];
    }

    return output;
}

- (NSArray *)annotationsToArray:(NSArray *)annotations {
    NSMutableArray *output = [NSMutableArray array];

    for (ARTAnnotation *annotation in annotations) {
        NSDictionary *item = [self annotationToDictionary:annotation];
        [output addObject:item];
    }

    return output;
}

- (NSDictionary *)presenceMessageToDictionary:(ARTPresenceMessage *)message {
    NSMutableDictionary *output = [NSMutableDictionary dictionary];

    if (message.timestamp) {
        [output setObject:[message.timestamp artToNumberMs] forKey:@"timestamp"];
    }

    if (message.clientId) {
        [output setObject:message.clientId forKey:@"clientId"];
    }

    if (message.data) {
        [self writeData:message.data encoding:message.encoding toDictionary:output];
    }
    if(message.connectionId) {
        [output setObject:message.connectionId forKey:@"connectionId"];
    }

    if (message.extras) {
        [output setObject:message.extras forKey:@"extras"]; // TP3i
    }

    int action = [self intFromPresenceMessageAction:message.action];

    [output setObject:[NSNumber numberWithInt:action] forKey:@"action"];
    ARTLogVerbose(_logger, @"RS:%p ARTJsonLikeEncoder<%@>: presenceMessageToDictionary %@", _rest, [_delegate formatAsString], output);
    return output;
}

- (NSArray *)presenceMessagesToArray:(NSArray *)messages {
    NSMutableArray *output = [NSMutableArray array];

    for (ARTPresenceMessage *message in messages) {
        NSDictionary *item = [self presenceMessageToDictionary:message];
        [output addObject:item];
    }
    return output;
}

- (NSDictionary *)protocolMessageToDictionary:(ARTProtocolMessage *)message {
    NSMutableDictionary *output = [NSMutableDictionary dictionary];
    output[@"action"] = [NSNumber numberWithLongLong:message.action];

    if (message.channel) {
        output[@"channel"] = message.channel;
    }

    if (message.channelSerial) {
        output[@"channelSerial"] = message.channelSerial;
    }

    if (message.msgSerial != nil) {
        output[@"msgSerial"] = message.msgSerial;
    }

    if (message.messages) {
        output[@"messages"] = [self messagesToArray:message.messages];
    }

    if (message.presence) {
        output[@"presence"] = [self presenceMessagesToArray:message.presence];
    }

    if (message.annotations) {
        output[@"annotations"] = [self annotationsToArray:message.annotations];
    }

    if (message.auth) {
        output[@"auth"] = [self authDetailsToDictionary:message.auth];
    }

    if (message.flags) {
        output[@"flags"] = [NSNumber numberWithLongLong:message.flags];
    }

    if (message.params) {
        output[@"params"] = message.params;
    }

    if (message.res) {
        output[@"res"] = [self publishResultsToArray:message.res];
    }

#ifdef ABLY_SUPPORTS_PLUGINS
    if (message.state) {
        output[@"state"] = [self objectMessagesToArray:message.state];
    }
#endif

    ARTLogVerbose(_logger, @"RS:%p ARTJsonLikeEncoder<%@>: protocolMessageToDictionary %@", _rest, [_delegate formatAsString], output);
    return output;
}

- (ARTTokenDetails *)tokenFromDictionary:(NSDictionary *)input error:(NSError * __autoreleasing *)error {
    ARTLogVerbose(_logger, @"RS:%p ARTJsonLikeEncoder<%@>: tokenFromDictionary %@", _rest, [_delegate formatAsString], input);

    if (![input isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSDictionary *jsonError = [input artDictionary:@"error"];
    if (jsonError) {
        ARTLogError(_logger, @"RS:%p ARTJsonLikeEncoder<%@>: tokenFromDictionary error %@", _rest, [_delegate formatAsString], jsonError);
        if (error) {
            NSMutableDictionary* details = [NSMutableDictionary dictionary];
            [details setValue:[jsonError artString:@"message"] forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:ARTAblyErrorDomain
                                         code:[jsonError artNumber:@"code"].integerValue
                                     userInfo:details];
        }
        return nil;
    }
    error = nil;

    NSString *token = [input artString:@"token"];
    NSNumber *expiresTimeInterval = [input objectForKey:@"expires"];
    NSDate *expires = expiresTimeInterval != nil ? [NSDate dateWithTimeIntervalSince1970:millisecondsToTimeInterval(expiresTimeInterval.doubleValue)] : nil;
    NSNumber *issuedInterval = [input objectForKey:@"issued"];
    NSDate *issued = issuedInterval != nil ? [NSDate dateWithTimeIntervalSince1970:millisecondsToTimeInterval(issuedInterval.doubleValue)] : nil;

    return [[ARTTokenDetails alloc] initWithToken:token
                                              expires:expires
                                               issued:issued
                                           capability:[input artString:@"capability"]
                                             clientId:[input artString:@"clientId"]];

}

- (NSDictionary *)tokenRequestToDictionary:(ARTTokenRequest *)tokenRequest {
    ARTLogVerbose(_logger, @"RS:%p ARTJsonLikeEncoder<%@>: tokenRequestToDictionary %@", _rest, [_delegate formatAsString], tokenRequest);

    NSNumber *timestamp;
    if (tokenRequest.timestamp)
        timestamp = [NSNumber numberWithUnsignedLongLong:dateToMilliseconds(tokenRequest.timestamp)];
    else
        timestamp = [NSNumber numberWithUnsignedLongLong:dateToMilliseconds([_timeProvider wallClockNow])];

    NSMutableDictionary *dictionary = [@{
             @"keyName":tokenRequest.keyName ? tokenRequest.keyName : @"",
             @"timestamp":timestamp,
             @"nonce":tokenRequest.nonce ? tokenRequest.nonce : @"",
             @"mac":tokenRequest.mac ? tokenRequest.mac : @""
        } mutableCopy];

    if (tokenRequest.capability) {
        dictionary[@"capability"] = tokenRequest.capability;
    }
    if (tokenRequest.clientId) {
        dictionary[@"clientId"] = tokenRequest.clientId;
    }
    if (tokenRequest.ttl != nil) {
        dictionary[@"ttl"] = [NSNumber numberWithUnsignedLongLong:timeIntervalToMilliseconds(tokenRequest.ttl.doubleValue)];
    }

    return dictionary;
}

- (ARTTokenRequest *)tokenRequestFromDictionary:(NSDictionary *)input error:(NSError * __autoreleasing *)error {
    ARTLogVerbose(_logger, @"RS:%p ARTJsonLikeEncoder<%@>: tokenRequestFromDictionary %@", _rest, [_delegate formatAsString], input);

    if (![input isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSDictionary *jsonError = [input artDictionary:@"error"];
    if (jsonError) {
        ARTLogError(_logger, @"RS:%p ARTJsonLikeEncoder<%@>: tokenRequestFromDictionary error %@", _rest, [_delegate formatAsString], jsonError);
        if (error) {
            NSMutableDictionary* details = [NSMutableDictionary dictionary];
            [details setValue:[jsonError artString:@"message"] forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:ARTAblyErrorDomain
                                         code:[jsonError artNumber:@"code"].integerValue
                                     userInfo:details];
        }
        return nil;
    }
    error = nil;

    ARTTokenParams *params = [[ARTTokenParams alloc] initWithClientId:[input artString:@"clientId"]
                                                                nonce:[input artString:@"nonce"]];
    NSInteger millisecondsTtl = [input artInteger:@"ttl"];
    if (millisecondsTtl) {
        params.ttl = [NSNumber numberWithDouble:millisecondsToTimeInterval(millisecondsTtl)];
    }
    params.capability = [input artString:@"capability"];
    params.timestamp = [input artTimestamp:@"timestamp"];

    return [[ARTTokenRequest alloc] initWithTokenParams:params
                                                keyName:[input artString:@"keyName"]
                                                  nonce:[input artString:@"nonce"]
                                                    mac:[input artString:@"mac"]];
}

- (NSDictionary *)tokenDetailsToDictionary:(ARTTokenDetails *)tokenDetails {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];

    dictionary[@"token"] = tokenDetails.token;

    if (tokenDetails.issued) {
        dictionary[@"issued"] = [NSString stringWithFormat:@"%llu", dateToMilliseconds(tokenDetails.issued)];
    }

    if (tokenDetails.expires) {
        dictionary[@"expires"] = [NSString stringWithFormat:@"%llu", dateToMilliseconds(tokenDetails.expires)];
    }

    if (tokenDetails.capability) {
        dictionary[@"capability"] = tokenDetails.capability;
    }

    if (tokenDetails.clientId) {
        dictionary[@"clientId"] = tokenDetails.clientId;
    }

    return dictionary;
}

- (NSMutableDictionary *)deviceDetailsToDictionary:(ARTDeviceDetails *)deviceDetails {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];

    dictionary[@"id"] = deviceDetails.id;
    dictionary[@"platform"] = deviceDetails.platform;
    dictionary[@"formFactor"] = deviceDetails.formFactor;

    if (deviceDetails.clientId) {
        dictionary[@"clientId"] = deviceDetails.clientId;
    }

    dictionary[@"push"] = [self devicePushDetailsToDictionary:deviceDetails.push];

    return dictionary;
}

- (NSDictionary *)localDeviceToDictionary:(ARTLocalDevice *)device {
    NSMutableDictionary *dictionary = [self deviceDetailsToDictionary:device];
    dictionary[@"deviceSecret"] = device.secret;
    return dictionary;
}

- (ARTDeviceDetails *)deviceDetailsFromDictionary:(NSDictionary *)input error:(NSError * __autoreleasing *)error {
    ARTLogVerbose(_logger, @"RS:%p ARTJsonLikeEncoder<%@>: deviceDetailsFromDictionary %@", _rest, [_delegate formatAsString], input);

    if (![input isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    ARTDeviceDetails *deviceDetails = [[ARTDeviceDetails alloc] initWithId:[input artString:@"id"]];
    deviceDetails.clientId = [input artString:@"clientId"];
    deviceDetails.platform = [input artString:@"platform"];
    deviceDetails.formFactor = [input artString:@"formFactor"];
    deviceDetails.metadata = [input valueForKey:@"metadata"];
    deviceDetails.push = [self devicePushDetailsFromDictionary:input[@"push"] error:error];

    return deviceDetails;
}

- (ARTDeviceIdentityTokenDetails *)deviceIdentityTokenDetailsFromDictionary:(NSDictionary *)input error:(NSError * __autoreleasing *)error {
    ARTLogVerbose(_logger, @"RS:%p ARTJsonLikeEncoder<%@>: deviceIdentityTokenDetailsFromDictionary %@", _rest, [_delegate formatAsString], input);

    if (![input isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSDictionary *deviceIdentityTokenInput = input[@"deviceIdentityToken"];
    NSString *token = [deviceIdentityTokenInput artString:@"token"];
    NSNumber *issuedMsecs = [deviceIdentityTokenInput artNumber:@"issued"];
    NSDate *issued = [NSDate art_dateWithMillisecondsSince1970:issuedMsecs.doubleValue];
    NSNumber *expiresMsecs = [deviceIdentityTokenInput artNumber:@"expires"];
    NSDate *expires = [NSDate art_dateWithMillisecondsSince1970:expiresMsecs.doubleValue];
    NSString *capability = [deviceIdentityTokenInput artString:@"capability"];
    NSString *clientId = [deviceIdentityTokenInput artString:@"clientId"];

    ARTDeviceIdentityTokenDetails *deviceIdentityTokenDetails = [[ARTDeviceIdentityTokenDetails alloc] initWithToken:token issued:issued expires:expires capability:capability clientId:clientId];

    return deviceIdentityTokenDetails;
}

- (NSDictionary *)devicePushDetailsToDictionary:(ARTDevicePushDetails *)devicePushDetails {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];

    dictionary[@"recipient"] = devicePushDetails.recipient;

    return dictionary;
}

- (ARTDevicePushDetails *)devicePushDetailsFromDictionary:(NSDictionary *)input error:(NSError * __autoreleasing *)error {
    ARTLogVerbose(_logger, @"RS:%p ARTJsonLikeEncoder<%@>: devicePushDetailsFromDictionary %@", _rest, [_delegate formatAsString], input);

    if (![input isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    ARTDevicePushDetails *devicePushDetails = [[ARTDevicePushDetails alloc] init];
    devicePushDetails.state = [input artString:@"state"];
    NSDictionary *errorReason = [input valueForKey:@"errorReason"];
    if (errorReason) {
        devicePushDetails.errorReason = [ARTErrorInfo createWithCode:[[errorReason artNumber:@"code"] intValue] status:[[errorReason artNumber:@"statusCode"] intValue] message:[errorReason artString:@"message"]];
    }
    devicePushDetails.recipient = [input valueForKey:@"recipient"];

    return devicePushDetails;
}

- (ARTProtocolMessage *)protocolMessageFromDictionary:(NSDictionary *)input {
    ARTLogVerbose(_logger, @"RS:%p ARTJsonLikeEncoder<%@>: protocolMessageFromDictionary %@", _rest, [_delegate formatAsString], input);
    if (![input isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    ARTProtocolMessage *message = [[ARTProtocolMessage alloc] init];
    message.action = (ARTProtocolMessageAction)[[input artNumber:@"action"] intValue];
    message.count = [[input artNumber:@"count"] intValue];
    message.channel = [input artString:@"channel"];
    message.channelSerial = [input artString:@"channelSerial"];
    message.connectionId = [input artString:@"connectionId"];
    message.id = [input artString:@"id"];
    message.msgSerial = [input artNumber:@"msgSerial"];
    message.timestamp = [input artTimestamp:@"timestamp"];
    message.connectionKey = [input artString:@"connectionKey"];
    message.flags = [[input artNumber:@"flags"] longLongValue];
    message.connectionDetails = [self connectionDetailsFromDictionary:[input valueForKey:@"connectionDetails"]];
    message.auth = [self authDetailsFromDictionary:[input valueForKey:@"auth"]];
    message.params = [input valueForKey:@"params"];

    NSDictionary *error = [input valueForKey:@"error"];
    if (error) {
        message.error = [ARTErrorInfo createWithCode:[[error artNumber:@"code"] intValue] status:[[error artNumber:@"statusCode"] intValue] message:[error artString:@"message"]];
    }

    NSMutableArray *messages = [[input objectForKey:@"messages"] mutableCopy];
    message.messages = [self messagesFromArray:messages protocolMessage:message];
    message.presence = [self presenceMessagesFromArray:[input objectForKey:@"presence"]];
    message.annotations = [self annotationsFromArray:[input objectForKey:@"annotations"]];
    message.res = [self publishResultsFromArray:[input objectForKey:@"res"]];
#ifdef ABLY_SUPPORTS_PLUGINS
    message.state = [self objectMessagesFromArray:[input objectForKey:@"state"] protocolMessage:message];
#endif

    return message;
}

- (ARTConnectionDetails *)connectionDetailsFromDictionary:(NSDictionary *)input {
    if (!input) {
        return nil;
    }

    NSNumber *objectsGCGracePeriod = nil;
    // RTO10b3 implies this may be absent
    if ([input valueForKey:@"objectsGCGracePeriod"]) {
        objectsGCGracePeriod = @(millisecondsToTimeInterval([input artInteger:@"objectsGCGracePeriod"]));
    }

    return [[ARTConnectionDetails alloc] initWithClientId:[input artString:@"clientId"]
                                            connectionKey:[input artString:@"connectionKey"]
                                           maxMessageSize:[input artInteger:@"maxMessageSize"]
                                             maxFrameSize:[input artInteger:@"maxFrameSize"]
                                           maxInboundRate:[input artInteger:@"maxInboundRate"]
                                       connectionStateTtl:millisecondsToTimeInterval([input artInteger:@"connectionStateTtl"])
                                                 serverId:[input artString:@"serverId"]
                                          maxIdleInterval:millisecondsToTimeInterval([input artInteger:@"maxIdleInterval"])
                                     objectsGCGracePeriod:objectsGCGracePeriod
                                                 siteCode:[input artString:@"siteCode"]];
}

- (ARTChannelMetrics *)channelMetricsFromDictionary:(NSDictionary *)input {
    return [[ARTChannelMetrics alloc] initWithConnections:[input artInteger:@"connections"]
                                               publishers:[input artInteger:@"publishers"]
                                              subscribers:[input artInteger:@"subscribers"]
                                      presenceConnections:[input artInteger:@"presenceConnections"]
                                          presenceMembers:[input artInteger:@"presenceMembers"]
                                      presenceSubscribers:[input artInteger:@"presenceSubscribers"]
                                         objectPublishers:[input artInteger:@"objectPublishers"]
                                        objectSubscribers:[input artInteger:@"objectSubscribers"]];
}

- (ARTChannelOccupancy *)channelOccupancyFromDictionary:(NSDictionary *)input {
    NSDictionary *metricsDict = [input valueForKey:@"metrics"];
    ARTChannelMetrics *metrics = [self channelMetricsFromDictionary:metricsDict];
    ARTChannelOccupancy *occupancy = [[ARTChannelOccupancy alloc] initWithMetrics:metrics];
    return occupancy;
}

- (ARTChannelStatus *)channelStatusFromDictionary:(NSDictionary *)input {
    NSDictionary *occupancyDict = [input valueForKey:@"occupancy"];
    ARTChannelOccupancy *occupancy = [self channelOccupancyFromDictionary:occupancyDict];
    ARTChannelStatus *status = [[ARTChannelStatus alloc] initWithOccupancy:occupancy active:[input artBoolean:@"isActive"]];
    return status;
}

- (ARTChannelDetails *)channelDetailsFromDictionary:(NSDictionary *)input {
    NSDictionary *statusDict = [input valueForKey:@"status"];
    ARTChannelStatus *status = [self channelStatusFromDictionary:statusDict];
    ARTChannelDetails *details = [[ARTChannelDetails alloc] initWithChannelId:[input artString:@"channelId"] status:status];
    return details;
}

- (ARTUpdateDeleteResult *)decodeUpdateDeleteResult:(NSData *)data error:(NSError **)error {
    return [self updateDeleteResultFromDictionary:[self decodeDictionary:data error:error]];
}

- (ARTPublishResult *)decodePublishResult:(NSData *)data error:(NSError **)error {
    return [self publishResultFromDictionary:[self decodeDictionary:data error:error]];
}

- (ARTUpdateDeleteResult *)updateDeleteResultFromDictionary:(NSDictionary *)input {
    ARTLogVerbose(_logger, @"RS:%p ARTJsonLikeEncoder<%@>: updateDeleteResultFromDictionary %@", _rest, [_delegate formatAsString], input);
    if (![input isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *versionSerial = [input artString:@"versionSerial"];
    return [[ARTUpdateDeleteResult alloc] initWithVersionSerial:versionSerial];
}

- (NSArray *)statsFromArray:(NSArray *)input {
    if (![input isKindOfClass:[NSArray class]]) {
        return nil;
    }

    NSMutableArray *output = [NSMutableArray array];

    for (NSDictionary *item in input) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            return nil;
        }
        ARTStats *statsItem = [self statsFromDictionary:item];
        if (!statsItem) {
            return nil;
        }
        [output addObject:statsItem];
    }

    return output;
}

- (ARTStats *)statsFromDictionary:(NSDictionary *)input {
    ARTLogVerbose(_logger, @"RS:%p ARTJsonLikeEncoder<%@>: statsFromDictionary %@", _rest, [_delegate formatAsString], input);
    if (![input isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    return [[ARTStats alloc] initWithAll:[self statsMessageTypesFromDictionary:[input objectForKey:@"all"]]
                                 inbound:[self statsMessageTrafficFromDictionary:[input objectForKey:@"inbound"]]
                                outbound:[self statsMessageTrafficFromDictionary:[input objectForKey:@"outbound"]]
                               persisted:[self statsMessageTypesFromDictionary:[input objectForKey:@"persisted"]]
                             connections:[self statsConnectionTypesFromDictionary:[input objectForKey:@"connections"]]
                                channels:[self statsResourceCountFromDictionary:[input objectForKey:@"channels"]]
                             apiRequests:[self statsRequestCountFromDictionary:[input objectForKey:@"apiRequests"]]
                           tokenRequests:[self statsRequestCountFromDictionary:[input objectForKey:@"tokenRequests"]]
                                  pushes:[self statsPushCountFromDictionary:[input objectForKey:@"push"]]
                              inProgress:[input artString:@"inProgress"]
                                   count:[[input artNumber:@"count"] unsignedIntegerValue]
                              intervalId:[input artString:@"intervalId"]];
}

- (ARTStatsMessageTypes *)statsMessageTypesFromDictionary:(NSDictionary *)input {
    if (![input isKindOfClass:[NSDictionary class]]) {
        return [ARTStatsMessageTypes empty];
    }

    ARTStatsMessageCount *all = [self statsMessageCountFromDictionary:[input objectForKey:@"all"]];
    ARTStatsMessageCount *messages = [self statsMessageCountFromDictionary:[input objectForKey:@"messages"]];
    ARTStatsMessageCount *presence = [self statsMessageCountFromDictionary:[input objectForKey:@"presence"]];

    if (all || messages || presence) {
        return [[ARTStatsMessageTypes alloc] initWithAll:all messages:messages presence:presence];
    }

    return [ARTStatsMessageTypes empty];
}

- (ARTStatsMessageCount *)statsMessageCountFromDictionary:(NSDictionary *)input {
    if (![input isKindOfClass:[NSDictionary class]]) {
        return [ARTStatsMessageCount empty];
    }

    NSNumber *count = [input artTyped:[NSNumber class] key:@"count"];
    NSNumber *data = [input artTyped:[NSNumber class] key:@"data"];

    return [[ARTStatsMessageCount alloc] initWithCount:count.doubleValue data:data.doubleValue];
}

- (ARTStatsMessageTraffic *)statsMessageTrafficFromDictionary:(NSDictionary *)input {
    if (![input isKindOfClass:[NSDictionary class]]) {
        return [ARTStatsMessageTraffic empty];
    }

    ARTStatsMessageTypes *all = [self statsMessageTypesFromDictionary:[input objectForKey:@"all"]];
    ARTStatsMessageTypes *realtime = [self statsMessageTypesFromDictionary:[input objectForKey:@"realtime"]];
    ARTStatsMessageTypes *rest = [self statsMessageTypesFromDictionary:[input objectForKey:@"rest"]];
    ARTStatsMessageTypes *webhook = [self statsMessageTypesFromDictionary:[input objectForKey:@"webhook"]];

    if (all || realtime || rest || webhook) {
        return [[ARTStatsMessageTraffic alloc] initWithAll:all
                                                  realtime:realtime
                                                      rest:rest
                                                   webhook:webhook];
    }

    return [ARTStatsMessageTraffic empty];
}

- (ARTStatsConnectionTypes *)statsConnectionTypesFromDictionary:(NSDictionary *)input {
    if (![input isKindOfClass:[NSDictionary class]]) {
        return [ARTStatsConnectionTypes empty];
    }

    ARTStatsResourceCount *all = [self statsResourceCountFromDictionary:[input objectForKey:@"all"]];
    ARTStatsResourceCount *plain = [self statsResourceCountFromDictionary:[input objectForKey:@"plain"]];
    ARTStatsResourceCount *tls = [self statsResourceCountFromDictionary:[input objectForKey:@"tls"]];

    if (all || plain || tls) {
        return [[ARTStatsConnectionTypes alloc] initWithAll:all plain:plain tls:tls];
    }

    return [ARTStatsConnectionTypes empty];
}

- (ARTStatsResourceCount *)statsResourceCountFromDictionary:(NSDictionary *)input {
    if (![input isKindOfClass:[NSDictionary class]]) {
        return [ARTStatsResourceCount empty];
    }

    NSNumber *opened = [input artTyped:[NSNumber class] key:@"opened"];
    NSNumber *peak = [input artTyped:[NSNumber class] key:@"peak"];
    NSNumber *mean = [input artTyped:[NSNumber class] key:@"mean"];
    NSNumber *min = [input artTyped:[NSNumber class] key:@"min"];
    NSNumber *refused = [input artTyped:[NSNumber class] key:@"refused"];

    return [[ARTStatsResourceCount alloc] initWithOpened:opened.doubleValue
                                                    peak:peak.doubleValue
                                                    mean:mean.doubleValue
                                                     min:min.doubleValue
                                                 refused:refused.doubleValue];
}

- (ARTErrorInfo *)decodeErrorInfo:(NSData *)artError statusCode:(NSInteger)statusCode error:(NSError **)error {
    NSDictionary *dict = [self decodeDictionary:artError error:error];
    id decodedError = [dict valueForKey:@"error"];

    if ([decodedError isKindOfClass:NSDictionary.class]) {
        NSDictionary *errorDict = decodedError;
        NSNumber *codeNumber = [errorDict artNumber:@"code"];
        NSNumber *statusNumber = [errorDict artNumber:@"statusCode"];
        NSString *message = [errorDict artString:@"message"];
        return [ARTErrorInfo createWithCode:[(codeNumber ?: @(statusCode * 100)) intValue]
                                     status:[(statusNumber ?: @(statusCode)) intValue]
                                    message:message ?: [NSString stringWithFormat:@"HTTP request failed with status code %ld", statusCode]];
    } else {
        // We expect `decodedError` as a dictionary from Ably REST API, but in case user sets custom authUrl in the auth options, it can be anything
        // We'll address this in an upcoming proper fix for https://github.com/ably/ably-cocoa/issues/2135
        return [ARTErrorInfo createWithCode:statusCode * 100
                                     status:statusCode
                                    message:[NSString stringWithFormat:@"HTTP request failed with status code %ld", statusCode]];
    }
}

- (ARTStatsRequestCount *)statsRequestCountFromDictionary:(NSDictionary *)input {
    ARTLogVerbose(_logger, @"RS:%p ARTJsonLikeEncoder<%@>: statsRequestCountFromDictionary %@", _rest, [_delegate formatAsString], input);
    if (![input isKindOfClass:[NSDictionary class]]) {
        return [ARTStatsRequestCount empty];
    }

    NSNumber *succeeded = [input artTyped:[NSNumber class] key:@"succeeded"];
    NSNumber *failed = [input artTyped:[NSNumber class] key:@"failed"];
    NSNumber *refused = [input artTyped:[NSNumber class] key:@"refused"];

    return [[ARTStatsRequestCount alloc] initWithSucceeded:succeeded.doubleValue
                                                    failed:failed.doubleValue
                                                   refused:refused.doubleValue];
}

- (ARTStatsPushCount *)statsPushCountFromDictionary:(NSDictionary *)input {
    ARTLogVerbose(_logger, @"RS:%p ARTJsonLikeEncoder<%@>: statsPushCountFromDictionary %@", _rest, [_delegate formatAsString], input);
    if (![input isKindOfClass:[NSDictionary class]]) {
        return [ARTStatsPushCount empty];
    }

    NSNumber *messages = [input artNumber:@"messages"];
    NSNumber *direct = [input artNumber:@"directPublishes"];

    NSDictionary *notifications = input[@"notifications"];
    NSNumber *succeeded = [notifications artNumber:@"successful"];
    NSNumber *invalid = [notifications artNumber:@"invalid"];
    NSNumber *attempted = [notifications artNumber:@"attempted"];
    NSNumber *failed = [notifications artNumber:@"failed"];

    return [[ARTStatsPushCount alloc] initWithSucceeded:succeeded.integerValue
                                                invalid:invalid.integerValue
                                              attempted:attempted.integerValue
                                                 failed:failed.integerValue
                                               messages:messages.integerValue
                                                 direct:direct.integerValue];
}

- (void)writeData:(id)data encoding:(NSString *)encoding toDictionary:(NSMutableDictionary *)output {
    if (encoding.length) {
        output[@"encoding"] = encoding;
    }
    output[@"data"] = data;
}

- (NSDictionary *)decodeDictionary:(NSData *)data error:(NSError **)error {
    id obj = [self decode:data error:error];
    if (![obj isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    return obj;
}

- (NSArray *)decodeArray:(NSData *)data error:(NSError **)error {
    id obj = [self decode:data error:error];
    if (![obj isKindOfClass:[NSArray class]]) {
        return nil;
    }
    return obj;
}

- (NSArray<NSDictionary *> *)decodeToArray:(NSData *)data error:(NSError **)error {
    id obj = [self decode:data error:error];
    if ([obj isKindOfClass:[NSDictionary class]]) {
        return @[obj];
    }
    if (![obj isKindOfClass:[NSArray class]]) {
        return nil;
    }
    return obj;
}

- (id)decode:(NSData *)data error:(NSError **)error {
    NSError *e = nil;
    id decoded = [_delegate decode:data error:&e];
    if (e) {
        ARTLogError(_logger, @"failed decoding data %@ with,  %@ (%@)", data, e.localizedDescription, e.localizedFailureReason);
    }
    if (error) {
        *error = e;
    }
    ARTLogDebug(_logger, @"RS:%p ARTJsonLikeEncoder<%@> decoding '%@'; got: %@", _rest, [_delegate formatAsString], data, decoded);
    return decoded;
}

- (NSData *)encode:(id)obj error:(NSError **)error {
    NSError *e = nil;
    NSData *encoded = [_delegate encode:obj error:&e];
    if (e) {
        ARTLogError(_logger, @"failed encoding object %@ with,  %@ (%@)", obj, e.localizedDescription, e.localizedFailureReason);
    }
    if (error) {
        *error = e;
    }
    ARTLogDebug(_logger, @"RS:%p ARTJsonLikeEncoder<%@> encoding '%@'; got: %@", _rest, [_delegate formatAsString], obj, encoded);
    return encoded;
}

#ifdef ABLY_SUPPORTS_PLUGINS
/// Converts an `ARTEncoderFormat` to an `APEncodingFormat`.
- (APEncodingFormat)apEncodingFormatFromARTEncoderFormat:(ARTEncoderFormat)format {
    switch (format) {
        case ARTEncoderFormatJson:
            return APEncodingFormatJSON;
        case ARTEncoderFormatMsgPack:
            return APEncodingFormatMessagePack;
    }
}
#endif

#ifdef ABLY_SUPPORTS_PLUGINS
/// Uses the LiveObjects plugin to decode an array of `ObjectMessage`s.
///
/// Returns `nil` if the LiveObjects plugin has not been supplied, or if we fail to decode any of the `ObjectMessage`s.
- (nullable NSArray<id<APObjectMessageProtocol>> *)objectMessagesFromArray:(nullable id)input
                                                           protocolMessage:(ARTProtocolMessage *)protocolMessage {
    if (![input isKindOfClass:[NSArray class]]) {
        return nil;
    }

    NSArray *inputArray = input;

    id<APLiveObjectsInternalPluginProtocol> liveObjectsPlugin = _rest.options.liveObjectsPlugin;

    if (!liveObjectsPlugin) {
        return nil;
    }

    NSMutableArray<id<APObjectMessageProtocol>> *output = [NSMutableArray array];

    for (NSInteger i = 0; i < inputArray.count; i++) {
        id item = inputArray[i];

        if (![item isKindOfClass:[NSDictionary class]]) {
            return nil;
        }

        ARTPluginDecodingContext *decodingContext = [[ARTPluginDecodingContext alloc] initWithParentID:protocolMessage.id
                                                                                    parentConnectionID:protocolMessage.connectionId
                                                                                       parentTimestamp:protocolMessage.timestamp
                                                                                         indexInParent:i];

        id<APPublicErrorInfo> error;
        APEncodingFormat format = [self apEncodingFormatFromARTEncoderFormat:[self format]];

        id<APObjectMessageProtocol> objectMessage = [liveObjectsPlugin decodeObjectMessage:item
                                                                                   context:decodingContext
                                                                                    format:format
                                                                                     error:&error];

        if (!objectMessage) {
            ARTLogWarn(_logger, @"RS:%p ARTJsonLikeEncoder<%@>: LiveObjects plugin failed to decode ObjectMessage %@, error %@", _rest, [_delegate formatAsString], item, error);
            return nil;
        }

        [output addObject:objectMessage];
    }

    return output;
}

/// Uses the LiveObjects plugin to encode an array of `ObjectMessage`s.
///
/// Returns `nil` if the input is `nil`.
- (NSArray<NSDictionary *> *)objectMessagesToArray:(nullable NSArray<id<APObjectMessageProtocol>> *)objectMessages {
    if (!objectMessages) {
        return nil;
    }

    id<APLiveObjectsInternalPluginProtocol> liveObjectsPlugin = _rest.options.liveObjectsPlugin;

    if (!liveObjectsPlugin) {
        // The only thing that sends ObjectMessage is the LiveObjects plugin, so if we have some to encode then the plugin must be present
        [NSException raise:NSInternalInconsistencyException format:@"Attempted to encode ObjectMessages without a LiveObjects plugin; this should not be possible."];
        return nil;
    }

    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    APEncodingFormat format = [self apEncodingFormatFromARTEncoderFormat:[self format]];

    for (id objectMessage in objectMessages) {
        [result addObject:[liveObjectsPlugin encodeObjectMessage:objectMessage format:format]];
    }

    return result;
}
#endif

@end

