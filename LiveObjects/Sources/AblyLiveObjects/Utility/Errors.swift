internal import _AblyPluginSupportPrivate
import Ably

/**
 Describes the errors that can be thrown by the LiveObjects SDK. Use ``toARTErrorInfo()`` to convert to an `ARTErrorInfo` that you can throw.
 */
internal enum LiveObjectsError {
    // operationDescription should be a description of a method like "LiveCounter.value"; it will be interpolated into an error message
    case objectsOperationFailedInvalidChannelState(operationDescription: String, channelState: _AblyPluginSupportPrivate.RealtimeChannelState)
    case counterInitialValueInvalid(value: Double)
    case counterIncrementAmountInvalid(amount: Double)
    /// RTO20e1: The channel entered a non-`ATTACHED` state whilst a `publishAndApply` call was waiting for objects sync to complete.
    case publishAndApplyFailedChannelStateChanged(channelState: _AblyPluginSupportPrivate.RealtimeChannelState, reason: ARTErrorInfo?)
    /// RTO23c1: The channel entered a non-`ATTACHED` state whilst a `get()` call was waiting for objects sync to complete.
    case getFailedChannelStateChanged(channelState: _AblyPluginSupportPrivate.RealtimeChannelState, reason: ARTErrorInfo?)
    /// RTLMV3, RTLCV3: A newly created object was not found in the pool after `publishAndApply`.
    case newlyCreatedObjectNotInPool(objectID: String)
    /// RTO15d: The total size of the `ObjectMessage`s to be published (calculated per OM3) exceeds the connection's `maxMessageSize`.
    case maxMessageSizeExceeded(size: Int, maxSize: Int)
    /// RTPO3c2: A write operation (`set`/`remove`/`increment`/`decrement`) was attempted on a path
    /// that does not resolve to a value. Code 92005.
    case pathNotResolved(path: String)
    /// RTTS5d2/RTTS9d, RTPO15e/RTPO16e/RTPO17e/RTPO18e: A typed write wrapper (`asLiveMap`/
    /// `asLiveCounter`) resolved to a value whose type does not match the wrapper. Code 92007.
    case pathTypeMismatch(operationDescription: String)
    /// RTO2a2/RTO2b2: The channel is missing a required channel mode (`object_subscribe` for reads,
    /// `object_publish` for writes). Code 40024.
    case channelModeRequired(mode: String)
    /// RTO26: A write (mutation) operation was attempted while the client's `echoMessages` option is
    /// disabled. Code 40000.
    case echoMessagesDisabled
    /// The channel was released via `channels.release()`, so any in-flight objects operation is failed
    /// with this as the cause. Code 40000. Unspecified; released-channel operations are failed with a
    /// client error.
    case channelReleased
    /// The LiveObjects plugin is not configured on the client. Code 40019. The code is defined here;
    /// plugin-missing detection is not yet wired up.
    case pluginUnavailable
    /// RTLMV4a/b, RTLCV4a, RTPO19c1a (depth validation): invalid input parameter. Code 40003.
    case invalidInput(message: String)
    case other(Error)

    /// The numeric error code returned to callers. The path-based public-API codes
    /// (92005/92007/40024/40019/40003) are absent from core `ARTErrorCode` and are returned as raw
    /// integers; the remaining cases map to their `ARTErrorCode`.
    internal var numericCode: Int {
        switch self {
        case .pathNotResolved:
            92005 // RTPO3c2
        case .pathTypeMismatch:
            92007 // RTTS5d2/RTTS9d
        case .channelModeRequired:
            40024 // RTO2a2/RTO2b2
        case .echoMessagesDisabled:
            40000 // RTO26
        case .channelReleased:
            40000 // client error (channel released)
        case .pluginUnavailable:
            40019
        case .invalidInput:
            40003 // RTLMV4a/RTPO19c1a
        case .objectsOperationFailedInvalidChannelState:
            Int(ARTErrorCode.channelOperationFailedInvalidState.rawValue)
        case .counterInitialValueInvalid, .counterIncrementAmountInvalid:
            // RTLCV4a, RTLC12e1
            Int(ARTErrorCode.invalidParameterValue.rawValue)
        case .publishAndApplyFailedChannelStateChanged, .getFailedChannelStateChanged:
            // RTO20e1, RTO23c1
            Int(ARTErrorCode.unableToApplyObjectsOperationSyncDidNotComplete.rawValue)
        case .newlyCreatedObjectNotInPool:
            Int(ARTErrorCode.internalError.rawValue)
        case .maxMessageSizeExceeded:
            // RTO15d
            Int(ARTErrorCode.maxMessageLengthExceeded.rawValue)
        case .other:
            Int(ARTErrorCode.badRequest.rawValue)
        }
    }

    /// The ``ARTErrorInfo/statusCode`` that should be returned for this error.
    internal var statusCode: Int {
        switch self {
        case .objectsOperationFailedInvalidChannelState,
             .counterInitialValueInvalid,
             .counterIncrementAmountInvalid,
             .publishAndApplyFailedChannelStateChanged,
             .getFailedChannelStateChanged,
             .maxMessageSizeExceeded,
             .pathNotResolved,
             .pathTypeMismatch,
             .channelModeRequired,
             .echoMessagesDisabled,
             .channelReleased,
             .pluginUnavailable,
             .invalidInput,
             .other:
            400
        case .newlyCreatedObjectNotInPool:
            500
        }
    }

    /// The ``ARTErrorInfo/localizedDescription`` that should be returned for this error.
    internal var localizedDescription: String {
        switch self {
        case let .objectsOperationFailedInvalidChannelState(operationDescription: operationDescription, channelState: channelState):
            "\(operationDescription) operation failed (invalid channel state: \(channelState))"
        case let .counterInitialValueInvalid(value: value):
            "Invalid counter initial value (must be a finite number): \(value)"
        case let .counterIncrementAmountInvalid(amount: amount):
            "Invalid counter increment amount (must be a finite number): \(amount)"
        case let .publishAndApplyFailedChannelStateChanged(channelState: channelState, reason: _):
            // RTO20e1
            "operation could not be applied locally: channel entered \(channelState) state whilst waiting for objects sync to complete"
        case let .getFailedChannelStateChanged(channelState: channelState, reason: _):
            // RTO23c1
            "the object could not be retrieved due to the channel entering the \(channelState) state whilst waiting for objects sync to complete"
        case let .newlyCreatedObjectNotInPool(objectID: objectID):
            "Newly created object \(objectID) not found in pool after publishAndApply"
        case let .maxMessageSizeExceeded(size: size, maxSize: maxSize):
            // RTO15d
            "ObjectMessages size \(size) exceeds maximum allowed size of \(maxSize) bytes"
        case let .pathNotResolved(path: path):
            // RTPO3c2
            "Path could not be resolved: \"\(path)\""
        case let .pathTypeMismatch(operationDescription: operationDescription):
            // RTTS5d2/RTTS9d
            operationDescription
        case let .channelModeRequired(mode: mode):
            // RTO2a2/RTO2b2
            "\"\(mode)\" channel mode must be set for this operation"
        case .echoMessagesDisabled:
            // RTO26
            "\"echoMessages\" client option must be enabled for this operation"
        case .channelReleased:
            // Unspecified message for the channel-released cause.
            "Channel has been released using channels.release()"
        case .pluginUnavailable:
            "The LiveObjects plugin is not configured on this client"
        case let .invalidInput(message: message):
            message
        case let .other(error):
            "\(error)"
        }
    }

    /// The ``ARTErrorInfo/cause`` that should be returned for this error.
    internal var cause: ARTErrorInfo? {
        switch self {
        case let .publishAndApplyFailedChannelStateChanged(channelState: _, reason: reason),
             let .getFailedChannelStateChanged(channelState: _, reason: reason):
            // RTO20e1, RTO23c1
            reason
        case .objectsOperationFailedInvalidChannelState,
             .counterInitialValueInvalid,
             .counterIncrementAmountInvalid,
             .newlyCreatedObjectNotInPool,
             .maxMessageSizeExceeded,
             .pathNotResolved,
             .pathTypeMismatch,
             .channelModeRequired,
             .echoMessagesDisabled,
             .channelReleased,
             .pluginUnavailable,
             .invalidInput,
             .other:
            nil
        }
    }

    internal func toARTErrorInfo() -> ARTErrorInfo {
        var userInfo: [String: Any] = [liveObjectsErrorUserInfoKey: self]
        if let cause {
            // Note that here we're making use of an implementation detail of ably-cocoa (the fact that this user info key populates `ARTErrorInfo.cause`).
            userInfo[NSUnderlyingErrorKey] = cause
        }

        return ARTErrorInfo.create(
            withCode: numericCode,
            status: statusCode,
            message: localizedDescription,
            additionalUserInfo: userInfo,
        )
    }
}

// MARK: - ConvertibleToLiveObjectsError Protocol

/// Protocol for types that can be converted to a `LiveObjectsError`.
///
/// We deliberately do not conform `ARTErrorInfo` (or its parent types `NSError` or `Error`) to this protocol, so that we do not accidentally end up flattening an `ARTErrorInfo` into the `.other` `LiveObjectsError` case; if we have an `ARTErrorInfo` then it should just be thrown directly.
///
/// If you need to convert a non-specific `NSError` or `Error` to a `LiveObjects` error, then do so explicitly using `LiveObjectsError.other`.
internal protocol ConvertibleToLiveObjectsError {
    func toLiveObjectsError() -> LiveObjectsError
}

internal extension ConvertibleToLiveObjectsError {
    /// Convenience method to convert directly to an `ARTErrorInfo`.
    func toARTErrorInfo() -> ARTErrorInfo {
        toLiveObjectsError().toARTErrorInfo()
    }
}

// MARK: - Conversion Extensions

extension DecodingError: ConvertibleToLiveObjectsError {
    internal func toLiveObjectsError() -> LiveObjectsError {
        .other(self)
    }
}

extension WireValueDecodingError: ConvertibleToLiveObjectsError {
    internal func toLiveObjectsError() -> LiveObjectsError {
        .other(self)
    }
}

extension WireValue.ConversionError: ConvertibleToLiveObjectsError {
    internal func toLiveObjectsError() -> LiveObjectsError {
        .other(self)
    }
}

extension InboundWireObjectMessage.DecodingError: ConvertibleToLiveObjectsError {
    internal func toLiveObjectsError() -> LiveObjectsError {
        .other(self)
    }
}

extension StringOrData.DecodingError: ConvertibleToLiveObjectsError {
    internal func toLiveObjectsError() -> LiveObjectsError {
        .other(self)
    }
}

extension JSONObjectOrArray.ConversionError: ConvertibleToLiveObjectsError {
    internal func toLiveObjectsError() -> LiveObjectsError {
        .other(self)
    }
}

// MARK: - ARTErrorInfo Extension

/// The `ARTErrorInfo.userInfo` key under which we store the underlying `LiveObjectsError` (see `toARTErrorInfo()`), preserving it for diagnostics.
internal let liveObjectsErrorUserInfoKey = "LiveObjectsError" // internal for AblyLiveObjectsTesting
