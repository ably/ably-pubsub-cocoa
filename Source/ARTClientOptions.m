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

NSString *ARTDefaultEnvironment = nil;

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

    _port = [ARTDefault port];
    _tlsPort = [ARTDefault tlsPort];
    _environment = ARTDefaultEnvironment;
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

- (NSString*)restHost {
    if (_restHost != nil) {
        return _restHost;
    }
    if ([_environment isEqualToString:ARTDefaultProduction]) {
        return [ARTDefault restHost];
    }
    return self.hasEnvironment ? [self host:[ARTDefault restHost] forEnvironment:_environment] : [ARTDefault restHost];
}

- (NSString*)realtimeHost {
    if (_realtimeHost != nil) {
        return _realtimeHost;
    }
    if ([_environment isEqualToString:ARTDefaultProduction]) {
        return [ARTDefault realtimeHost];
    }

    return self.hasEnvironment ? [self host:[ARTDefault realtimeHost] forEnvironment:_environment] : [ARTDefault realtimeHost];
}

- (NSURLComponents *)restUrlComponents {
    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = self.tls ? @"https" : @"http";
    components.host = self.restHost;
    components.port = [NSNumber numberWithInteger:(self.tls ? self.tlsPort : self.port)];
    return components;
}

- (NSURL*)restUrl {
    return [self restUrlComponents].URL;
}

- (NSURL*)realtimeUrl {
    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = self.tls ? @"wss" : @"ws";
    components.host = self.realtimeHost;
    components.port = [NSNumber numberWithInteger:(self.tls ? self.tlsPort : self.port)];
    return components.URL;
}

- (id)copyWithZone:(NSZone *)zone {
    ARTClientOptions *options = [super copyWithZone:zone];

    options.clientId = self.clientId;
    options.port = self.port;
    options.tlsPort = self.tlsPort;
    if (self->_restHost) options.restHost = self.restHost;
    if (self->_realtimeHost) options.realtimeHost = self.realtimeHost;
    options.queueMessages = self.queueMessages;
    options.echoMessages = self.echoMessages;
    options.recover = self.recover;
    options.useBinaryProtocol = self.useBinaryProtocol;
    options.autoConnect = self.autoConnect;
    options.environment = self.environment;
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

- (BOOL)isBasicAuth {
    return self.useTokenAuth == false &&
        self.key != nil &&
        self.token == nil &&
        self.tokenDetails == nil &&
        self.authUrl == nil &&
        self.authCallback == nil;
}

- (BOOL)hasCustomRestHost {
    return (_restHost && ![_restHost isEqualToString:[ARTDefault restHost]]) || (self.hasEnvironment && !self.isProductionEnvironment);
}

- (BOOL)hasDefaultRestHost {
    return ![self hasCustomRestHost];
}

- (BOOL)hasCustomRealtimeHost {
    return (_realtimeHost && ![_realtimeHost isEqualToString:[ARTDefault realtimeHost]]) || (self.hasEnvironment && !self.isProductionEnvironment);
}

- (BOOL)hasDefaultRealtimeHost {
    return ![self hasCustomRealtimeHost];
}

- (BOOL)hasCustomPort {
    return self.port && self.port != [ARTDefault port];
}

- (BOOL)hasCustomTlsPort {
    return self.tlsPort && self.tlsPort != [ARTDefault tlsPort];
}

+ (void)setDefaultEnvironment:(NSString *)environment {
    ARTDefaultEnvironment = environment;
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

- (BOOL)isProductionEnvironment {
    return [[self.environment lowercaseString] isEqualToString:[ARTDefaultProduction lowercaseString]];
}

- (BOOL)hasEnvironment {
    return self.environment != nil && [self.environment isNotEmptyString];
}

- (BOOL)hasEnvironmentDifferentThanProduction {
    return self.hasEnvironment && !self.isProductionEnvironment;
}

- (NSString *)host:(NSString *)host forEnvironment:(NSString *)environment {
    return [NSString stringWithFormat:@"%@-%@", environment, host];
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
