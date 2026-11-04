![Ably Pub/Sub Cocoa Header](https://raw.githubusercontent.com/ably/ably-pubsub-cocoa/main/images/CocoaSDK-github.png)

[![AblyPubSubDevice](https://img.shields.io/github/v/release/ably/ably-pubsub-cocoa?label=AblyPubSubDevice)](https://github.com/ably/ably-pubsub-cocoa/releases)
[![License](https://badgen.net/github/license/ably/ably-pubsub-cocoa)](https://github.com/ably/ably-pubsub-cocoa/blob/main/LICENSE)

# Ably Pub/Sub Cocoa SDK

The Swift and Objective-C SDK for [Ably Pub/Sub](https://ably.com/docs/basics): publish and
subscribe to channels, and use message history, presence, push notifications and LiveObjects, from
iOS, macOS and tvOS apps.

## Overview

This SDK provides the device package only, for end-user apps. There is no server package; for
backends, use a server SDK such as [JavaScript](https://github.com/ably/ably-pubsub-js),
[Java](https://github.com/ably/ably-pubsub-java), [Go](https://github.com/ably/ably-pubsub-go),
[.NET](https://github.com/ably/ably-pubsub-dotnet), [Python](https://github.com/ably/ably-pubsub-python),
[PHP](https://github.com/ably/ably-pubsub-php) or [Ruby](https://github.com/ably/ably-pubsub-ruby).

| Package | Use it for | Entry point |
|---------|------------|-------------|
| `AblyPubSubDevice` | Applications on end-user devices | `PubSubDevice.createClient` |

## Requirements

iOS 15 or later, macOS 12 or later, or tvOS 15 or later (building needs Xcode 26 or later, with
Swift 6.2).

## Installation

Install the SDK with Swift Package Manager. Version 2.0 is not published to CocoaPods or Carthage.

In Xcode:

1. Choose **File > Add Package Dependencies…** and enter `https://github.com/ably/ably-pubsub-cocoa`.
2. Add the `AblyPubSubDevice` product to your target.

In a `Package.swift` manifest, add the same package URL from version `2.0.0` and depend on its
`AblyPubSubDevice` product.

In Objective-C, import the SDK with `@import AblyPubSubDevice;`. Swift drops the `ART` prefix from
type names: `ARTClientOptions` is `ClientOptions`.

## Quick start

Authenticate a device with tokens issued by your own server, through `authUrl` or `authCallback`.
Never embed an API key in an app that runs on an end-user device.

```swift
import AblyPubSubDeviceSwift

let options = ClientOptions()
options.authUrl = URL(string: "https://your-server.example.com/ably-auth")
options.clientId = "me"
let client = PubSubDevice.createClient(options: options)

// The client connects automatically. Subscribing attaches the channel.
let channel = client.channels.get("test-channel")
channel.subscribe { message in
    print("Received: \(message.data ?? "")")
}

channel.publish("test-event", data: "hello world") { error in
    if let error {
        print("Publish failed: \(error.message)")
    }
}
```

To get tokens from your own code instead of a URL, set `authCallback`. Pass its callback a token
string, a `TokenDetails` or a `TokenRequest`.

In Swift, you can `await` channel, presence and connection operations instead of passing callbacks,
for example `try await channel.publish("test-event", data: "hello world")`. They throw an
`ErrorInfo`.

> [!IMPORTANT]
> The `async` functions in `AblyPubSubDeviceSwift` are experimental. Their names, signatures and
> the set of operations they cover may change in a minor release.

## Migrating from 1.x

Version 2.0 installs through Swift Package Manager only and creates clients with `PubSubDevice`.

| | 1.x | 2.0 |
|---|---|---|
| Package | `Ably` product of `ably-cocoa` | `AblyPubSubDevice` product of `ably-pubsub-cocoa` |
| Import | `import Ably` / `@import Ably;` | `import AblyPubSubDeviceSwift` / `@import AblyPubSubDevice;` |
| Realtime client | `ARTRealtime(options: options)` | `PubSubDevice.createClient(options: options)` |
| REST client | `ARTRest(options: options)` | Removed |

See the [migration guide](https://github.com/ably/ably-pubsub-cocoa/blob/main/Docs/migration-guides/v2.md) for all other changes.

## Common configuration

Set options on a `ClientOptions` object and pass it to `PubSubDevice.createClient(options:)`.

### Endpoint

`endpoint` selects the Ably host for HTTP requests and the realtime connection. It replaces the
1.x `environment`, `restHost` and `realtimeHost` options.

```swift
let options = ClientOptions()
options.authUrl = URL(string: "https://your-server.example.com/ably-auth")
options.clientId = "me"
options.endpoint = "nonprod:sandbox"
let client = PubSubDevice.createClient(options: options)
```

- Never put a port in `endpoint`: `localhost:8080` is not a hostname and does not resolve.
- Set the port with `tlsPort`, or with `port` when TLS is off.
- With TLS off (`tls = false`), use token authentication.

See the [migration guide](https://github.com/ably/ably-pubsub-cocoa/blob/main/Docs/migration-guides/v2.md#endpoint) for how the old options map to
`endpoint`.

### Logging

Set `logLevel` to a `LogLevel` value: `.verbose`, `.debug`, `.info`, `.warn` or `.error`. The
default is `.warn`. The SDK writes log lines with `NSLog`.

```swift
options.logLevel = .debug
```

To send log lines elsewhere, set `logHandler` to a subclass of `Log` that overrides `log(_:with:)`.

<a id="liveobjects"></a>

## Live Objects

[LiveObjects](https://ably.com/docs/liveobjects) adds realtime data structures, such as maps and
counters, that stay in sync across clients.

### Installation

The plugin ships as the `AblyLiveObjects` product of this package. It has no separate package or
version, and installs through Swift Package Manager only.

In Xcode, add the package as described in [Installation](#installation). Then select both the
`AblyPubSubDevice` and `AblyLiveObjects` products for your target.

In a `Package.swift` manifest, add the package and both products:

```swift
dependencies: [
    .package(url: "https://github.com/ably/ably-pubsub-cocoa", from: "2.0.0"),
],
targets: [
    .target(
        name: "MyTarget",
        dependencies: [
            .product(name: "AblyPubSubDevice", package: "ably-pubsub-cocoa"),
            .product(name: "AblyLiveObjects", package: "ably-pubsub-cocoa"),
        ]
    ),
]
```

### Usage

Register the plugin, then get a channel with the object channel modes:

```swift
import AblyPubSubDeviceSwift
import AblyLiveObjects

let options = ClientOptions()
options.authUrl = URL(string: "https://your-server.example.com/ably-auth")
options.clientId = "me"
options.plugins = [.liveObjects: AblyLiveObjects.Plugin.self]
let client = PubSubDevice.createClient(options: options)

let channelOptions = RealtimeChannelOptions()
channelOptions.modes = [.objectPublish, .objectSubscribe]
let channel = client.channels.get("test-channel", options: channelOptions)
let root = try await channel.object.get()
```

To learn more, follow the [Swift quickstart](https://ably.com/docs/liveobjects/quickstart/swift).
The [LiveObjects README](https://github.com/ably/ably-pubsub-cocoa/blob/main/LiveObjects/README.md)
has more examples and an example app.

## Platform notes

### Push notifications

On iOS, the SDK can activate a device for push notifications and subscribe it to channels. See
[Push notifications](https://ably.com/docs/push) for setup, and [Examples/AblyPush](https://github.com/ably/ably-pubsub-cocoa/tree/main/Examples/AblyPush)
for an example app.

### Privacy manifest

The SDK's privacy manifest declares the Device ID data type, which is not used for tracking. The
SDK sends the device ID to Ably only when your app uses push notifications. If your app doesn't, you
can leave Device ID off your App Store privacy label.

## Further reading

- [Getting started with Pub/Sub using Swift](https://ably.com/docs/getting-started/swift)
- [Ably Pub/Sub documentation](https://ably.com/docs/basics) and [examples](https://ably.com/examples?product=pubsub)
- [Token authentication](https://ably.com/docs/auth/token)
- [Migration guide](https://github.com/ably/ably-pubsub-cocoa/blob/main/Docs/migration-guides/v2.md): migrating from 1.x
- [CHANGELOG.md](https://github.com/ably/ably-pubsub-cocoa/blob/main/CHANGELOG.md): release notes; all Ably releases are listed on [changelog.ably.com](https://changelog.ably.com)

## Contributing

Read [CONTRIBUTING.md](https://github.com/ably/ably-pubsub-cocoa/blob/main/CONTRIBUTING.md) before contributing; it also describes the release
process.

## Support, feedback and troubleshooting

For help, visit Ably's [support page](https://ably.com/support). Report bugs and compatibility
problems on [GitHub Issues](https://github.com/ably/ably-pubsub-cocoa/issues).

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](https://github.com/ably/ably-pubsub-cocoa/blob/main/LICENSE).
