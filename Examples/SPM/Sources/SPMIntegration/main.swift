import AblyPubSubDevice

// `import AblyPubSubDevice` alone reaches the core's types too.
let options = ARTClientOptions()
options.autoConnect = false
options.key = "xxxx:xxxx"
options.clientId = "me"

let _ = PubSubDevice.createClient(options: options)
