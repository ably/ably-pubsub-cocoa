import AblyPubSubDevice.Private

class TestProxyTransportFactory: RealtimeTransportFactory {
    // This value will be used by all TestProxyTransportFactory instances created by this factory (including those created before this property is updated).
    var fakeNetworkResponse: FakeNetworkResponse?

    // This value will be used by all TestProxyTransportFactory instances created by this factory (including those created before this property is updated).
    var networkConnectEvent: ((ARTRealtimeTransport, URL) -> Void)?

    var transportCreatedEvent: ((ARTRealtimeTransport) -> Void)?

    func transport(withRest rest: ARTHttpClientInternal, options: ARTClientOptions, resumeKey: String?, logger: InternalLog) -> ARTRealtimeTransport {
        let testProxyTransport = TestProxyTransport(
            factory: self,
            rest: rest,
            options: options,
            resumeKey: resumeKey,
            logger: logger
        )

        transportCreatedEvent?(testProxyTransport)

        return testProxyTransport
    }
}
