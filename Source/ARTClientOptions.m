#import "ARTClientOptions+Private.h"
#import "ARTClientOptions+TestConfiguration.h"
#import "ARTAuthOptions+Private.h"

#import "ARTDefault+Private.h"
#import "ARTErrorInfo.h"
#import "ARTTokenParams.h"
#import "ARTStringifiable.h"
#import "ARTNSString+ARTUtil.h"
#import "ARTTestClientOptions.h"

#ifdef ABLY_SUPPORTS_PLUGINS
@import _AblyPluginSupportPrivate;
#import "ARTPluginAPI.h"
#endif

const ARTPluginName ARTPluginNameLiveObjects = @"LiveObjects";

static NSString *const ARTNonprodEndpointPrefix = @"nonprod:";

static NSString *ARTDefaultEndpointOverride = nil;

// REC1b2
static BOOL ARTEndpointIsHostname(NSString *endpoint) {
    return [endpoint containsString:@"."] || [endpoint containsString:@"::"] || [endpoint isEqualToString:@"localhost"];
}

@interface ARTClientOptions ()

@property (nonatomic) NSMutableDictionary<NSString *, id> *pluginData;

- (instancetype)initDefaults;

@end

@implementation ARTClientOptions

- (instancetype)initDefaults {
    self = [super initDefaults];

#ifdef ABLY_SUPPORTS_PLUGINS
    // The LiveObjects repository provides an extension to `ARTClientOptions` so we need to ensure that we register the pluginAPI before that extension is used.
    [ARTPluginAPI registerSelf];
#endif

    _endpoint = ARTDefaultEndpointOverride;
    _port = [ARTDefault port];
    _tlsPort = [ARTDefault tlsPort];
    _queueMessages = YES;
    _echoMessages = YES;
    _useBinaryProtocol = true;
    _autoConnect = true;
    _tls = YES;
    _logLevel = ARTLogLevelNone;
    _logHandler = [[ARTLog alloc] init];
    _disconnectedRetryTimeout = 15.0; //Seconds
    _suspendedRetryTimeout = 30.0; //Seconds
    _channelRetryTimeout = 15.0; //Seconds
    _httpOpenTimeout = 4.0; //Seconds
    _httpRequestTimeout = 10.0; //Seconds
    _fallbackRetryTimeout = 600.0; // Seconds, TO3l10
    _httpMaxRetryDuration = 15.0; //Seconds
    _httpMaxRetryCount = 3;
    _fallbackHosts = nil;
    _dispatchQueue = dispatch_get_main_queue();
    _internalDispatchQueue = dispatch_queue_create("io.ably.main", DISPATCH_QUEUE_SERIAL);
    _pushFullWait = false;
    _idempotentRestPublishing = [ARTClientOptions getDefaultIdempotentRestPublishingForVersion:[ARTDefault apiVersion]];
    _addRequestIds = false;
    _pushRegistererDelegate = nil;
    _testOptions = [[ARTTestClientOptions alloc] init];
    _pluginData = [[NSMutableDictionary alloc] init];
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@\n\t clientId: %@;", [super description], self.clientId];
}

// REC1a. An empty endpoint means the default, as in ably-js.
- (NSString *)resolvedEndpoint {
    return self.endpoint.length > 0 ? self.endpoint : [ARTDefault endpoint];
}

// The `[id]` of an endpoint of the form `nonprod:[id]`, or nil for any other endpoint.
- (nullable NSString *)nonprodRoutingPolicyId {
    NSString *const endpoint = [self resolvedEndpoint];
    if (ARTEndpointIsHostname(endpoint) || ![endpoint hasPrefix:ARTNonprodEndpointPrefix]) {
        return nil;
    }
    return [endpoint substringFromIndex:ARTNonprodEndpointPrefix.length];
}

- (BOOL)hasNonprodEndpoint {
    return [self nonprodRoutingPolicyId] != nil;
}

- (NSString *)primaryDomain {
    NSString *const endpoint = [self resolvedEndpoint];
    if (ARTEndpointIsHostname(endpoint)) { // REC1b2
        return endpoint;
    }
    NSString *const nonprodId = [self nonprodRoutingPolicyId];
    if (nonprodId) { // REC1b3
        return [NSString stringWithFormat:@"%@.realtime.ably-nonprod.net", nonprodId];
    }
    return [NSString stringWithFormat:@"%@.realtime.ably.net", endpoint]; // REC1b4
}

- (NSArray<NSString *> *)endpointFallbackHosts {
    NSString *const endpoint = [self resolvedEndpoint];
    if (ARTEndpointIsHostname(endpoint)) { // REC2c2
        return @[];
    }
    NSString *const nonprodId = [self nonprodRoutingPolicyId];
    if (nonprodId) { // REC2c3
        return [ARTDefault fallbackHostsForRoutingPolicyId:nonprodId domain:@"ably-realtime-nonprod.com"];
    }
    return [ARTDefault fallbackHostsForRoutingPolicyId:endpoint domain:@"ably-realtime.com"]; // REC2c1, REC2c4
}

- (NSURLComponents *)restUrlComponents {
    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = self.tls ? @"https" : @"http";
    components.host = self.primaryDomain;
    components.port = [NSNumber numberWithInteger:(self.tls ? self.tlsPort : self.port)];
    return components;
}

- (NSURL*)restUrl {
    return [self restUrlComponents].URL;
}

- (NSURLComponents *)realtimeUrlComponents {
    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = self.tls ? @"wss" : @"ws";
    components.host = self.primaryDomain;
    components.port = [NSNumber numberWithInteger:(self.tls ? self.tlsPort : self.port)];
    return components;
}

- (NSURL*)realtimeUrl {
    return [self realtimeUrlComponents].URL;
}

- (id)copyWithZone:(NSZone *)zone {
    ARTClientOptions *options = [super copyWithZone:zone];

    options.clientId = self.clientId;
    options.port = self.port;
    options.tlsPort = self.tlsPort;
    options.endpoint = self.endpoint;
    options.connectivityCheckUrl = self.connectivityCheckUrl;
    options.queueMessages = self.queueMessages;
    options.echoMessages = self.echoMessages;
    options.recover = self.recover;
    options.useBinaryProtocol = self.useBinaryProtocol;
    options.autoConnect = self.autoConnect;
    options.tls = self.tls;
    options.logLevel = self.logLevel;
    options.logHandler = self.logHandler;
    options.suspendedRetryTimeout = self.suspendedRetryTimeout;
    options.disconnectedRetryTimeout = self.disconnectedRetryTimeout;
    options.channelRetryTimeout = self.channelRetryTimeout;
    options.httpMaxRetryCount = self.httpMaxRetryCount;
    options.httpMaxRetryDuration = self.httpMaxRetryDuration;
    options.httpOpenTimeout = self.httpOpenTimeout;
    options.fallbackRetryTimeout = self.fallbackRetryTimeout;
    options->_fallbackHosts = self.fallbackHosts; //ignore setter

    options.httpRequestTimeout = self.httpRequestTimeout;
    options.dispatchQueue = self.dispatchQueue;
    options.internalDispatchQueue = self.internalDispatchQueue;
    options.pushFullWait = self.pushFullWait;
    options.idempotentRestPublishing = self.idempotentRestPublishing;
    options.addRequestIds = self.addRequestIds;
    options.pushRegistererDelegate = self.pushRegistererDelegate;
    options.transportParams = self.transportParams;
    options.agents = self.agents;
    options.testOptions = self.testOptions;
    options.plugins = self.plugins;
    options.pluginData = [self.pluginData mutableCopy];

    return options;
}

- (BOOL)hasCustomPort {
    return self.port && self.port != [ARTDefault port];
}

- (BOOL)hasCustomTlsPort {
    return self.tlsPort && self.tlsPort != [ARTDefault tlsPort];
}

- (BOOL)isBasicAuth {
    return self.useTokenAuth == false &&
        self.key != nil &&
        self.token == nil &&
        self.tokenDetails == nil &&
        self.authUrl == nil &&
        self.authCallback == nil;
}

+ (void)setDefaultEndpoint:(NSString *)endpoint {
    ARTDefaultEndpointOverride = endpoint;
}

- (void)setDefaultTokenParams:(ARTTokenParams *)value {
    _defaultTokenParams = [[ARTTokenParams alloc] initWithTokenParams:value];
}

+ (BOOL)getDefaultIdempotentRestPublishingForVersion:(NSString *)version {
    if ([@"1.2" compare:version options:NSNumericSearch] == NSOrderedDescending) {
        return false;
    }
    else {
        return true;
    }
}

// MARK: - Plugins

#ifdef ABLY_SUPPORTS_PLUGINS
- (nullable id<APLiveObjectsInternalPluginProtocol>)liveObjectsPlugin {
    Class<APLiveObjectsPluginProtocol> publicPlugin = self.plugins[ARTPluginNameLiveObjects];

    if (!publicPlugin) {
        return nil;
    }

    id<APLiveObjectsInternalPluginProtocol> plugin = [publicPlugin internalPlugin];
    if (!plugin.compatibleWithProtocolV6) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"This version of ably-cocoa requires a LiveObjects plugin compatible with protocol v6."];
    }
    return plugin;
}
#endif

// MARK: - Options for plugins

- (void)setPluginOptionsValue:(id)value forKey:(NSString *)key {
    self.pluginData[key] = value;
}

- (id)pluginOptionsValueForKey:(NSString *)key {
    return self.pluginData[key];
}

@end
