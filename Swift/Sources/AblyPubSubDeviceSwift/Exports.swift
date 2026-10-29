// Swift users import this module instead of `AblyPubSubDevice`: it re-exports the whole Objective-C API and adds `async` versions of its callback-based operations.
//
// The Objective-C module keeps the `AblyPubSubDevice` name, because Objective-C code that writes `@import AblyPubSubDevice;` would not see the SDK through a re-export from a Swift module.
@_exported import AblyPubSubDevice
