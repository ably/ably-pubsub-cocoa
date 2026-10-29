# Ably Cocoa SDK Plugin Support Library

This is an Ably-internal library that defines the private APIs that the [Ably Pub/Sub Cocoa SDK](https://github.com/ably/ably-pubsub-cocoa) uses to communicate with its plugins.

> [!note]
> This library is an implementation detail of the Ably SDK and should not be used directly by end users of the SDK.

Further documentation will be added in the future.

## Conventions

- Methods whose names begin with `nosync_` must always be called on the client's internal queue.

## Dependency setup

The intention is that:

- ably-cocoa's `Package.swift` declares a dependency on ably-cocoa-plugin-support
- each plugin's `Package.swift` declares a dependency on ably-cocoa-plugin-support
- each plugin's `Package.swift` also declares a direct dependency on ably-cocoa

This means that:

- a given version of the plugin is able to specify a _minimum_ version of ably-cocoa
- a given version of ably-cocoa is expected to work with all plugin versions whose minimum it satisfies — i.e. ably-cocoa is _not_ able to specify a minimum version of a plugin

The only way that ably-cocoa can exclude certain plugin versions is by creating a clash in the major version of the ably-cocoa-plugin-support dependency; we avoid using this mechanism where possible — as it can cause confusing dependency resolution error messages for users and complicates the release process — but reserve it, for example, when [introducing breaking Realtime protocol changes](#breaking-realtime-protocol-version-changes).

## Playbook for making changes

This section describes how to make some common changes that require changes to all three repositories (ably-cocoa, the plugin, and this repo).

### Adding new capabilities

In this section we describe how to make _non-breaking plugin-support changes_ (i.e. a minor plugin-support version bump) that either introduce functionality only available in a new version of ably-cocoa, or introduce functionality only available in a new version of the plugin.

The key point is that both of the following are breaking plugin-support changes and thus must be avoided:

- adding a new required method to an Objective-C protocol (breaks implementers of that protocol)
- removing a required method from an Objective-C protocol (breaks consumers of that protocol)

#### Introducing new functionality only available in a new version of ably-cocoa

1. Add a new `@optional` method or property.
2. Increase the plugin's minimum ably-cocoa version so that this method is guaranteed to be implemented, and perform a runtime precondition failure if it is not.

> [!NOTE]
> Avoid introducing new `@optional` properties with a nullable type, since in this case Swift does not provide a mechanism for differentiating between "property not implemented" and "property implemented and its value is `nil`". Use a getter method in this situation instead.

#### Introducing new functionality only available in a new version of the plugin

1. Add a new `@optional` method or property.
2. Perform a `-respondsToSelector:` check in ably-cocoa to decide whether this new API can be called. ably-cocoa **must** still behave correctly in the case where it cannot (i.e. where an old version of the plugin is being used).

### Removing capabilities

In this section we describe how to make _non-breaking plugin-support changes_ (i.e. a minor plugin-support version bump) that either remove functionality from ably-cocoa, or remove functionality from the plugin.

This also covers the case where, in combination with [adding a new capability](#adding-new-capabilities), we are replacing a method with a new variant.

The key point is that it is a breaking plugin-support change to remove a method from an Objective-C protocol (breaks consumers of that protocol) and this must thus be avoided.

#### Removing functionality from the plugin

Since the plugin can exclude older versions of ably-cocoa, the plugin is able to choose to throw a runtime exception in methods that it no longer wishes to implement. This should be combined with increasing the plugin's minimum ably-cocoa version to one that no longer calls the method, so that the exception is never triggered in practice.

#### Removing functionality from ably-cocoa

Since new versions of ably-cocoa can be used with old versions of the plugin, ably-cocoa must continue to provide functioning implementations of all methods.

### Breaking Realtime protocol version changes

In this section we describe how to make changes that require incrementing the [CSV2](https://sdk.ably.com/builds/ably/specification/main/features/#CSV2) protocol version number.

The key outcome that we wish to achieve is the following:

- a given version of ably-cocoa only needs to support a single protocol version
- a given version of the plugin only needs to support a single protocol version

— that is, we do not wish to try and implement negotiation of protocol version between ably-cocoa and the plugin.

In order to do this, whenever we increment the CSV2 protocol number in such a way as could cause incompatibility with a plugin, this repo (plugin-support) will make a **breaking API change**, and thus **bump its major version**.

#### Properties to replace

The aforementioned breaking plugin-support change is implemented by replacing the two required protocol properties shown below with equivalents that refer to the new protocol version (e.g. when moving from v6 to v7, rename `usesLiveObjectsProtocolV6` to `usesLiveObjectsProtocolV7`, and similarly rename `compatibleWithProtocolV6` to `compatibleWithProtocolV7`). Note that only one property is needed in order to create a breaking API change, but we provide both so that both parties can check the other's conformance even if package dependencies are not configured correctly.

The current properties are:

In `APPluginAPIProtocol`:

```objc
/// Whether the SDK uses a protocol version which, as far as a LiveObjects
/// plugin is concerned, is equivalent to protocol v6.
///
/// If the SDK uses a protocol version which is higher than 6 but whose
/// breaking changes compared to v6 do not affect LiveObjects plugins, this
/// property may still return `YES`.
///
/// This property **must** return `YES`. If you wish to introduce a protocol
/// version change, see the "Breaking Realtime protocol version changes"
/// section in the Readme.
@property (nonatomic, readonly) BOOL usesLiveObjectsProtocolV6;
```

> [!NOTE]
> The plugin should perform a runtime assertion that this property returns `YES`, to catch any scenario where package dependencies are incorrectly configured.

In `APLiveObjectsInternalPluginProtocol`:

```objc
/// Whether this plugin is compatible with protocol v6.
///
/// If this property returns `YES`, it indicates that this plugin can be used
/// with a version of ably-cocoa which uses protocol v6, or which uses a
/// protocol version higher than v6 whose breaking changes compared to v6 do
/// not affect LiveObjects plugins.
///
/// This property **must** return `YES`. If you wish to introduce a protocol
/// version change, see the "Breaking Realtime protocol version changes"
/// section in the Readme.
@property (nonatomic, readonly) BOOL compatibleWithProtocolV6;
```

> [!NOTE]
> ably-cocoa should perform a runtime assertion that this property returns `YES`, to catch any scenario where package dependencies are incorrectly configured.

## Release process for breaking plugin-support changes

The release process in such a scenario is not very smooth; there will be a brief period in which there exists a version of ably-cocoa without a plugin version that is compatible with it. During this window, a user who explicitly updates their `Package.swift` to require the new ably-cocoa version while also depending on the plugin will get a dependency resolution error. To minimise this window, have the plugin release PR reviewed and ready to merge before releasing ably-cocoa, so that the only remaining step is updating the ably-cocoa dependency from a commit pin to the released version tag.

1. Prepare a release PR of plugin version `v_p`, with dependency on the new major version of plugin-support, but still pinned to an ably-cocoa commit. Do not release it.
2. Prepare a release PR of ably-cocoa version `v_c`, with dependency on the new major version of plugin-support. Mention in the release message that it is compatible with version `v_p` of the plugin, which will be released shortly.
3. Release ably-cocoa version `v_c`.
4. Update the release PR of plugin version `v_p` to now point to ably-cocoa version `v_c`.
5. Release plugin version `v_p`.
