internal import _AblyPluginSupportPrivate
import Ably

/// The channel-configuration precondition guards for the path-based public API. Each public
/// read/write entry point runs the relevant guard before touching the object graph, per
/// RTO23a/RTO25/RTO26. The guards reuse the core SDK's own `nosync_` precondition accessors
/// (channel state, object modes, `echoMessages`, connection state), so they raise the same errors
/// the internal engine's node accessors already produce rather than inventing new checks.
internal enum ChannelConfigGuards {
    /// Validates the access (read/subscribe) API preconditions: the channel must be attachable (not
    /// DETACHED/FAILED) and configured with the `object_subscribe` mode. Spec: RTO25.
    internal static func throwIfInvalidAccessApiConfiguration(coreSDK: CoreSDK, internalQueue: DispatchQueue) throws(ARTErrorInfo) {
        // Check order: channel state, then `object_subscribe` mode.
        let error = internalQueue.ably_syncNoDeadlock { () -> ARTErrorInfo? in
            // RTO25b — channel state (reuses the engine's node-accessor check).
            nosync_channelStateError(coreSDK: coreSDK, notIn: [.detached, .failed], operationDescription: "access API")
                // RTO25a / RTO2a2 — `object_subscribe` mode.
                ?? nosync_missingChannelModeError(coreSDK: coreSDK, requiredMode: .objectSubscribe, modeName: "object_subscribe")
        }
        if let error {
            throw error
        }
    }

    /// Validates only the `object_subscribe` channel mode (no channel-state check), for
    /// `RealtimeObject.get()` (RTO23a). Unlike the access methods, `get()` delegates channel-state
    /// handling to the ensure-attached procedure (RTL33), so it must not pre-empt that with a state
    /// gate. Spec: RTO23a.
    internal static func throwIfMissingObjectSubscribeMode(coreSDK: CoreSDK, internalQueue: DispatchQueue) throws(ARTErrorInfo) {
        // The `object_subscribe` mode only (no channel-state check).
        let error = internalQueue.ably_syncNoDeadlock { () -> ARTErrorInfo? in
            nosync_missingChannelModeError(coreSDK: coreSDK, requiredMode: .objectSubscribe, modeName: "object_subscribe")
        }
        if let error {
            throw error
        }
    }

    /// Validates the write (mutation) API preconditions: message echo must be enabled, the channel
    /// must be usable (not DETACHED/FAILED/SUSPENDED) and configured with the `object_publish` mode.
    /// Spec: RTO26.
    internal static func throwIfInvalidWriteApiConfiguration(coreSDK: CoreSDK, internalQueue: DispatchQueue) throws(ARTErrorInfo) {
        // Check order: echoMessages, then channel state, then `object_publish` mode.
        let error = internalQueue.ably_syncNoDeadlock { () -> ARTErrorInfo? in
            // RTO26c — `echoMessages` must be enabled.
            nosync_echoMessagesDisabledError(coreSDK: coreSDK)
                // RTO26b — channel state (reuses the engine's node-accessor check).
                ?? nosync_channelStateError(coreSDK: coreSDK, notIn: [.detached, .failed, .suspended], operationDescription: "write API")
                // RTO26a — `object_publish` mode.
                ?? nosync_missingChannelModeError(coreSDK: coreSDK, requiredMode: .objectPublish, modeName: "object_publish")
        }
        if let error {
            throw error
        }
    }

    /// RTO23e / RTL33 — the *ensure-active-channel* procedure that `RealtimeObject.get()` runs before
    /// waiting for sync:
    ///
    /// - **RTL33a** — ATTACHED or SUSPENDED: already usable, no attach performed.
    /// - **RTL33b** — INITIALIZED / DETACHED / DETACHING / ATTACHING: implicitly attach (per RTL4, via
    ///   the `CoreSDK.nosync_attach` plugin bridge) and await completion. A single attach resolves the
    ///   in-flight ATTACHING/DETACHING cases per RTL4h, so one call covers all four states. The
    ///   `ARTErrorInfo` that caused an attach failure is propagated (RTL33b1).
    /// - **RTL33c** — FAILED (and any unknown state): reject with code 90001, statusCode 400.
    ///
    /// The state read and the attach initiation happen in a **single** internal-queue block, so no
    /// channel-state change can be lost between the read and the attach's callback registration
    /// (lost-wakeup discipline).
    ///
    /// Spec: RTO23e, RTL33.
    internal static func ensureActiveChannel(coreSDK: CoreSDK, internalQueue: DispatchQueue) async throws(ARTErrorInfo) {
        let result: Result<Void, ARTErrorInfo> = await withCheckedContinuation { continuation in
            internalQueue.async {
                let state = coreSDK.nosync_channelState

                // The RTL33c rejection, reused for FAILED and any unknown state.
                let invalidStateError = LiveObjectsError.objectsOperationFailedInvalidChannelState(
                    operationDescription: "get",
                    channelState: state,
                )
                let invalidStateFailure: Result<Void, ARTErrorInfo> = .failure(invalidStateError.toARTErrorInfo())

                switch state {
                case .attached, .suspended:
                    // RTL33a
                    continuation.resume(returning: .success(()))
                case .initialized, .detached, .detaching, .attaching:
                    // RTL33b — implicit attach; the callback fires on the internal queue (RTL33b1
                    // propagates the attach-failure error).
                    coreSDK.nosync_attach { error in
                        continuation.resume(returning: error.map { .failure($0) } ?? .success(()))
                    }
                case .failed:
                    // RTL33c
                    continuation.resume(returning: invalidStateFailure)
                @unknown default:
                    continuation.resume(returning: invalidStateFailure)
                }
            }
        }

        switch result {
        case .success:
            return
        case let .failure(error):
            throw error
        }
    }

    /// Validates that the channel is in a publishable state (connection active, channel not
    /// FAILED/SUSPENDED). The connection-active portion is RTO15b (the RTL6c publish conditions); the
    /// channel-state portion is RTO26b.
    /// Note: currently unused in the write path — the core SDK's publish enforces RTL6c itself — and
    /// retained (with tests) for parity should a pre-publish gate be wanted.
    internal static func throwIfUnpublishableState(coreSDK: CoreSDK, internalQueue: DispatchQueue) throws(ARTErrorInfo) {
        // Check order: connection active, then channel state (FAILED/SUSPENDED).
        let error = internalQueue.ably_syncNoDeadlock { () -> ARTErrorInfo? in
            // The connection must be in a publishable (active) state; if not, surface the connection's
            // own state error: the connection's `errorReason`, or the core SDK's inactive-connection
            // error when it has none (RTL6c4).
            coreSDK.nosync_connectionStateError
                ?? nosync_channelStateError(coreSDK: coreSDK, notIn: [.failed, .suspended], operationDescription: "publish")
        }
        if let error {
            throw error
        }
    }

    /// RTPO19c1a — validates a subscription `depth` (throws 40003 for a non-positive value). The
    /// shipped Swift `init(depth:)` is non-throwing and frozen, so the check lives here, to be called
    /// from `subscribe(options:listener:)` once path subscriptions are wired up.
    internal static func validateSubscriptionDepth(_ depth: Int?) throws(ARTErrorInfo) {
        if let depth, depth <= 0 {
            throw LiveObjectsError.invalidInput(message: "Subscription depth must be a positive integer, got \(depth)").toARTErrorInfo()
        }
    }

    // MARK: - Private on-queue checks

    // The following helpers read `nosync_` core-SDK accessors (each guard wraps its checks in a single
    // `ably_syncNoDeadlock` hop). Each returns the relevant `ARTErrorInfo` if the check fails, or `nil`
    // if it passes — so a guard can chain them with `??` for short-circuiting evaluation in check
    // order.

    /// RTO25b/RTO26b — the channel-state check (reuses the engine's node-accessor precondition).
    private static func nosync_channelStateError(
        coreSDK: CoreSDK,
        notIn invalidStates: [_AblyPluginSupportPrivate.RealtimeChannelState],
        operationDescription: String,
    ) -> ARTErrorInfo? {
        let currentState = coreSDK.nosync_channelState
        if invalidStates.contains(currentState) {
            let error = LiveObjectsError.objectsOperationFailedInvalidChannelState(
                operationDescription: operationDescription,
                channelState: currentState,
            )
            return error.toARTErrorInfo()
        }
        return nil
    }

    /// RTO2a2/RTO2b2 — the required-channel-mode check (40024): fails when the effective modes are
    /// absent or do not contain the required mode.
    private static func nosync_missingChannelModeError(
        coreSDK: CoreSDK,
        requiredMode: _AblyPluginSupportPrivate.ChannelMode,
        modeName: String,
    ) -> ARTErrorInfo? {
        if !coreSDK.nosync_objectChannelModes.contains(requiredMode) {
            return LiveObjectsError.channelModeRequired(mode: modeName).toARTErrorInfo()
        }
        return nil
    }

    /// RTO26c — the `echoMessages` client-option check.
    private static func nosync_echoMessagesDisabledError(coreSDK: CoreSDK) -> ARTErrorInfo? {
        if !coreSDK.echoMessages {
            return LiveObjectsError.echoMessagesDisabled.toARTErrorInfo()
        }
        return nil
    }
}
