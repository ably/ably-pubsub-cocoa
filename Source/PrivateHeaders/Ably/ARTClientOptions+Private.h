#import <AblyPubSubDevice/ARTClientOptions.h>

#ifdef ABLY_SUPPORTS_PLUGINS
@import _AblyPluginSupportPrivate;
#endif

NS_ASSUME_NONNULL_BEGIN

#ifdef ABLY_SUPPORTS_PLUGINS
@interface ARTClientOptions () <APPublicClientOptions>
@end
#endif

@interface ARTClientOptions ()

/// The host that requests and connections go to first (REC1). It follows from `endpoint`.
@property (readonly) NSString *primaryDomain;

/// The fallback hosts that follow from `endpoint` (REC2c). They apply when `fallbackHosts` is nil. The array is empty when `endpoint` is a hostname.
@property (readonly) NSArray<NSString *> *endpointFallbackHosts;

/// Whether `endpoint` has the form `nonprod:[id]`.
@property (readonly) BOOL hasNonprodEndpoint;

@property (readonly) BOOL hasCustomPort;
@property (readonly) BOOL hasCustomTlsPort;

/// Sets the `endpoint` that new options start with. For tests that create a client through an initializer that takes only a key or a token.
+ (void)setDefaultEndpoint:(nullable NSString *)endpoint;
+ (BOOL)getDefaultIdempotentRestPublishingForVersion:(NSString *)version;
- (NSURLComponents *)restUrlComponents;

// MARK: - Plugins

#ifdef ABLY_SUPPORTS_PLUGINS
/// The plugin that channels should use to access LiveObjects functionality.
@property (nullable, readonly) id<APLiveObjectsInternalPluginProtocol> liveObjectsPlugin;
#endif

// MARK: - Options for plugins

/// Provides the implementation for `-[ARTPluginAPI setPluginOptionsValue:forKey:options:]`. See documentation for that method in `APPluginAPIProtocol`.
- (void)setPluginOptionsValue:(id)value forKey:(NSString *)key;
/// Provides the implementation for `-[ARTPluginAPI pluginOptionsValueForKey:options:]`. See documentation for that method in `APPluginAPIProtocol`.
- (nullable id)pluginOptionsValueForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
