# Plugin mechanism

ably-cocoa allows users to pass in Ably-authored plugins via the `ARTClientOptions.plugins` property. These plugins extend the functionality of the SDK.

ably-cocoa and its plugins depend on a library called `_AblyPluginSupportPrivate`, which is a target of this package (found in `_AblyPluginSupportPrivate`; it was previously in the separate [ably-cocoa-plugin-support repository](https://github.com/ably/ably-cocoa-plugin-support)). This provides an API that plugins can use to access ably-cocoa's internals, and which ably-cocoa can use to communicate with its plugins.

I will expand on this documentation once this mechanism is more mature. [ADR-128: Plugins for ably-cocoa SDK](https://ably.atlassian.net/wiki/spaces/ENG/pages/3838574593/ADR-128+Plugins+for+ably-cocoa+SDK) describes the original design, but is now outdated in some important ways: it is centred on the plugin living in a separate repository so as not to be bound by ably-cocoa's OS version requirements, a constraint that turned out not to exist (per-declaration `@available` annotations let a single package host components with different OS requirements, and the plugin now lives in this repository), and `_AblyPluginSupportPrivate` (called `AblyPlugin` in the ADR) is a standalone library rather than part of the Ably product.

Currently, our only plugin is for adding LiveObjects functionality. This plugin can be found in this repository's `LiveObjects/` directory, and is vended as this package's `AblyLiveObjects` product.

## Notes on `_AblyPluginSupportPrivate`

- Everything in ably-cocoa that depends on `_AblyPluginSupportPrivate` is gated behind `#ifdef ABLY_SUPPORTS_PLUGINS`. `Package.swift` defines that macro for the `Ably` target, so plugin support is compiled into every build of this package. The gate is what lets `Source` compile at all without `_AblyPluginSupportPrivate`, which is a target of this package rather than a library a build can pick up from anywhere else.
- ably-cocoa provides an implementation of `_AblyPluginSupportPrivate`'s `APPluginAPI` protocol, which is the interface that plugins use to access ably-cocoa's internals. On library initialization, it registers this implementation with `APDependencyStore`, from where plugins can subsequetly fetch it.
- There are some tests for the `APPluginAPI` implementation in `PluginAPITests.swift` (with only partial coverage at the moment).
- Currently, the plan is to test all the LiveObjects functionality within the plugin's own test suite (`LiveObjects/Tests`), so the ably-cocoa tests do not import the LiveObjects plugin.
- The underscore and `Private` are to reduce the chances of the user accidentally importing it into their project.
- `_AblyPluginSupportPrivate` can not refer to any of ably-cocoa's types (since SPM forbids circular dependencies) and so it contains various types that duplicate ably-cocoa's public types. These fall into two categories:
  - enums e.g. `APRealtimeChannelState`, which are an exact copy of the corresponding ably-cocoa enum (in this example, `ARTRealtimeChannelState`)
  - marker protocols e.g. `APPublicRealtimeChannel` which are empty protocols whose instances can always be safely casted to and from their corresponding ably-cocoa type (in this example, `ARTRealtimeChannel`)
- Do not add instance methods to types such as `APLogger` and `APRealtimeChannel` (instead, favour adding methods to `APPluginAPI`), so that ably-cocoa can make its internal `ARTInternalLog` and `ARTRealtimeChannelInternal` types conform to these protocols without having to worry about return or parameter type clashes due to the enum divergence described in the previous point.

## Development guidelines

- Make good use of `NS_SWIFT_NAME` to make `_AblyPluginSupportPrivate` nicer to use from Swift (e.g. to remove the `AP` prefix from class names).
