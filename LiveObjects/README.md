![Ably LiveObjects Swift Header](images/SwiftSDK-LiveObjects-github.png)
[![SPM Swift Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fably%2Fably-cocoa%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ably/ably-cocoa)
[![License](https://badgen.net/github/license/ably/ably-cocoa)](https://github.com/ably/ably-cocoa/blob/main/LICENSE)

---

# Ably LiveObjects Swift plugin

The Ably LiveObjects plugin enables real-time collaborative data synchronization for the [ably-cocoa](https://github.com/ably/ably-cocoa/) SDK. LiveObjects provides a simple way to build collaborative applications with synchronized state across multiple clients in real-time. Built on [Ably's](https://ably.com/) core service, it abstracts complex details to enable efficient collaborative architectures.

> [!NOTE]
> The plugin lives in the [ably-cocoa](https://github.com/ably/ably-cocoa/) repository and is versioned and released as part of ably-cocoa: add the ably-cocoa package to your project and select its `AblyLiveObjects` product. It was previously developed in the [ably-liveobjects-swift-plugin](https://github.com/ably/ably-liveobjects-swift-plugin) repository; if you are coming from that package, see the [migration guide](#migrating-from-the-standalone-plugin-package).

---

## Getting started

Everything you need to get started with Ably LiveObjects:

- [Learn about Ably LiveObjects.](https://ably.com/docs/liveobjects)
- [Getting started with LiveObjects in Swift.](https://ably.com/docs/liveobjects/quickstart/swift)
- Explore the [example app](Example) to see LiveObjects in action.

---

## Supported platforms

Ably aims to support a wide range of platforms. If you experience any compatibility issues, open an issue in the repository or contact [Ably support](https://ably.com/support).

This plugin supports the following platforms:

| Platform | Support |
| -------- | ------- |
| iOS      | >= 14.0 |
| macOS    | >= 11.0 |
| tvOS     | >= 14.0 |

> [!NOTE]
> Xcode 16.3 or later is required.

---

## Usage

The examples below are a quick tour of the API. Check the [LiveObjects documentation](https://ably.com/docs/liveobjects) for a comprehensive guide — starting with the [Swift quickstart](https://ably.com/docs/liveobjects/quickstart/swift), it covers maps, counters, path objects, subscriptions, lifecycle events and more.

After [installing the plugin](../README.md#liveobjects), pass it to the client via
`ARTClientOptions`, and fetch channels with the LiveObjects channel modes:

```swift
import AblyPubSubDevice
import AblyLiveObjects

let clientOptions = ARTClientOptions(key: "your-ably-api-key")
clientOptions.plugins = [.liveObjects: AblyLiveObjects.Plugin.self]
let realtime = PubSubDevice.createClient(options: clientOptions)

// Fetch a channel, specifying the LiveObjects channel modes
let channelOptions = ARTRealtimeChannelOptions()
channelOptions.modes = [.objectPublish, .objectSubscribe]
let channel = realtime.channels.get("my-channel", options: channelOptions)
```

`channel.object` is the entry point into the LiveObjects API. Fetch the channel's root map — this implicitly attaches the channel and waits for the channel's objects to be synchronized:

```swift
let rootObject = try await channel.object.get()
```

### Create and update objects

LiveObjects provides two synchronized data structures — `LiveMap`, a key/value map, and `LiveCounter`, a numeric counter — which you create and assign to keys on the root object:

```swift
// Create a counter and a map, and assign them to keys on the root object
try await rootObject.set(key: "visits", value: .liveCounter(LiveCounter.create(initialCount: 0)))
try await rootObject.set(key: "reactions", value: .liveMap(LiveMap.create(entries: [
    "likes": 0,
    "hearts": 0,
])))
```

Navigate the object graph with [path objects](https://ably.com/docs/liveobjects/concepts/path-object) — stable references to locations within the channel's objects that resolve to values at the time each method is called — and send operations to update the objects. Updates are synchronized to all clients subscribed to the channel:

```swift
let visits = rootObject.get(key: "visits").asLiveCounter()
try await visits.increment(amount: 5)

let reactions = rootObject.get(key: "reactions").asLiveMap()
try await reactions.set(key: "likes", value: 10)
try await reactions.remove(key: "hearts")
```

### Read values

```swift
// Read individual values
let visitCount = try visits.value() // 5.0
let likes = try reactions.get(key: "likes").asPrimitive().numberValue() // 10.0

// Or take a JSON-serializable snapshot of an entire object
let snapshot = try rootObject.compactJson() // {"reactions":{"likes":10},"visits":5}
```

### Subscribe to updates

Subscribe to a path object to be notified whenever the object at that path is updated, by any client:

```swift
let subscription = try visits.subscribe { event in
    guard let value = try? event.object.asLiveCounter().value() else { return }
    print("Visits updated: \(value)")
}

// Later, stop receiving updates
subscription.unsubscribe()
```

---

## Migrating from the standalone plugin package

As of ably-cocoa 1.3.0, the plugin is developed, versioned and released from the ably-cocoa repository as the `AblyLiveObjects` product of the ably-cocoa package. The standalone [ably-liveobjects-swift-plugin](https://github.com/ably/ably-liveobjects-swift-plugin) package is deprecated: no further releases will be published from it, and its final release is 0.4.1. Migrating takes two steps.

### Step 1: Swap the package dependency

1. Remove the `ably-liveobjects-swift-plugin` package dependency from your project.
2. Add (or update) the `ably-cocoa` package at version 1.3.0 or later, and select its `AblyLiveObjects` product for your target — see the [installation instructions](../README.md#liveobjects).

Your imports and plugin registration are unchanged:

```swift
import AblyPubSubDevice
import AblyLiveObjects

let clientOptions = ARTClientOptions(key: "your-ably-api-key")
clientOptions.plugins = [.liveObjects: AblyLiveObjects.Plugin.self]
```

> [!IMPORTANT]
> If you update ably-cocoa to 1.3.0 or later while the standalone package is still in your dependency graph, package resolution fails immediately with:
>
> ```text
> error: multiple packages ('ably-cocoa', 'ably-cocoa-plugin-support') declare targets with a conflicting name: '_AblyPluginSupportPrivate'; target names need to be unique across the package graph
> error: multiple packages ('ably-cocoa', 'ably-liveobjects-swift-plugin') declare targets with a conflicting name: 'AblyLiveObjects'; target names need to be unique across the package graph
> ```
>
> The fix is to remove the standalone package dependency, as described above.

### Step 2: Adopt the path-based API

ably-cocoa 1.3.0 replaces the instance-based API of the standalone plugin (last published in its 0.4.1 release) with the path-based API: instead of obtaining and operating on explicit `LiveMap`/`LiveCounter` instances, data is accessed and mutated through `PathObject`s — stable references to locations within the channel object that resolve to values dynamically at runtime. See the [PathObject documentation](https://ably.com/docs/liveobjects/concepts/path-object).

The headline API changes:

| Standalone plugin (≤ 0.4.1)                                    | ably-cocoa 1.3.0+                                                                                                       |
| -------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `channel.objects`, returning `RealtimeObjects`                 | `channel.object`, returning `RealtimeObject`                                                                            |
| `try await channel.objects.getRoot()`, returning `any LiveMap` | `try await channel.object.get()`, returning `any LiveMapPathObject`                                                     |
| Operate on explicit `LiveMap`/`LiveCounter` instances          | Navigate with `PathObject`s: `rootObject.get(key:)`, then cast with `asLiveMap()` / `asLiveCounter()` / `asPrimitive()` |

For example:

```swift
// Standalone plugin (≤ 0.4.1) — instance-based
let rootObject = try await channel.objects.getRoot()
try await rootObject.set(key: "myKey", value: "myValue")
let value = try rootObject.get(key: "myKey")?.stringValue

// ably-cocoa 1.3.0+ — path-based
let rootObject = try await channel.object.get()
try await rootObject.set(key: "myKey", value: "myValue")
let value = try rootObject.get(key: "myKey").asPrimitive().stringValue()
```

A `PathObject` is purely navigational: it can be created before the data at its path exists, and it survives the object at its path being replaced — there is no need to re-fetch anything when the underlying object changes. The [example app](Example) demonstrates the path-based API.

---

## Example app

This repository contains an example app, written using SwiftUI, which demonstrates how to use the plugin. The code for this app is in the [`Example`](Example) directory.

In order to allow the app to use modern SwiftUI features, it supports the following OS versions:

- macOS 14 and above
- iOS 17 and above
- tvOS 17 and above

To run the app:

1. Open the `AblyLiveObjects.xcworkspace` workspace in Xcode.
2. Follow the instructions inside the `Secrets.example.swift` file to add your Ably API key to the example app.
3. Run the `AblyLiveObjectsExample` target. If you wish to run it on an iOS or tvOS device, you'll need to set up code signing.

---

## Releases

The plugin is released as part of ably-cocoa; see the [ably-cocoa CHANGELOG](../CHANGELOG.md) for details of releases (and [CHANGELOG.md](./CHANGELOG.md) for the historical releases of the standalone plugin package). You can also view all Ably releases on [changelog.ably.com](https://changelog.ably.com).

---

## Contribute

Read the [CONTRIBUTING.md](./CONTRIBUTING.md) guidelines to contribute to Ably or [share feedback or request a new feature](https://forms.gle/mBw9M53NYuCBLFpMA).

## Support, feedback and troubleshooting

For help or technical support, visit Ably's [support page](https://ably.com/support). You can also view the [community-reported GitHub issues](https://github.com/ably/ably-cocoa/issues) or raise one yourself.
