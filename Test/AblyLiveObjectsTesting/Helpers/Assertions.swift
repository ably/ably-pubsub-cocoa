/// Stops execution because we tried to use a protocol requirement that is not implemented.
func protocolRequirementNotImplemented(_ message: @autoclosure () -> String = String(), file _: StaticString = #file, line _: UInt = #line) -> Never {
    fatalError({
        let returnedMessage = message()
        return "Protocol requirement not implemented\(returnedMessage.isEmpty ? "" : ": \(returnedMessage)")"
    }())
}
