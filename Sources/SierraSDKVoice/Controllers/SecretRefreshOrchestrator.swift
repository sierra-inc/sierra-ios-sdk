// Copyright Sierra

import Foundation
import SierraSDK

/// Orchestrates an agent-initiated secret refresh during a voice call.
///
/// The agent emits a `secret_refresh` custom attachment over SVP `attachments_server`.
/// `AgentVoiceController` peels the attachment off the inbound batch and forwards it here. The
/// orchestrator:
///
/// 1. Waits `initialDelaySeconds` (default 0).
/// 2. Calls the host's `AgentEventListener.onSecretExpiry(secretName:replyHandler:)` (declared on
///    `VoiceCallbacks` via the shared `AgentEventListener` protocol).
/// 3. On `.success(value)` (non-nil), sends:
///    - an SVP `memory_update_client` message so the server writes the fresh value to conversation
///      memory, AND
///    - an SVP `attachments_client` containing a `secret_refreshed` custom attachment, which the
///      server treats as a synthetic user message that triggers a fresh agent turn.
/// 4. On `.success(nil)`, stops without retrying (matches the web SDK interpretation that a `null`
///    reply means "this secret cannot be refreshed").
/// 5. On `.failure`, retries with exponential backoff capped at `maxDelaySeconds`, up to
///    `maxAttempts` total attempts.
///
/// All retry parameters mirror the web SDK's `<SecretRefresh>` component in
/// `journeys/sdk/web-react/secret-refresh.tsx` so behavior stays consistent across surfaces.
internal final class SecretRefreshOrchestrator {
    static let attachmentType = "custom"
    static let secretRefreshDataType = "secret_refresh"
    static let secretRefreshedDataType = "secret_refreshed"

    /// Returns true if the given attachment is a `secret_refresh` custom
    /// attachment that this orchestrator should handle.
    static func isSecretRefreshAttachment(_ raw: [String: Any]) -> Bool {
        guard
            let type = raw["type"] as? String, type == attachmentType,
            let data = raw["data"] as? [String: Any],
            let dataType = data["type"] as? String, dataType == secretRefreshDataType
        else {
            return false
        }
        return true
    }

    private struct RetryConfig {
        let maxAttempts: Int
        let initialRetryDelay: TimeInterval
        let maxDelay: TimeInterval

        static let defaults = RetryConfig(maxAttempts: 1, initialRetryDelay: 5, maxDelay: 10)
    }

    private struct PendingRefresh {
        let secretName: String
        let initialDelay: TimeInterval
        let retryConfig: RetryConfig
    }

    private weak var voiceSession: VoiceSessionManager?
    private weak var callbacks: VoiceCallbacks?
    private var inFlightSecretNames: Set<String> = []
    // Pending/in-flight scheduled attempts, keyed by a per-orchestrator
    // monotonic counter so each item can self-remove on completion. We hold the
    // DispatchWorkItem values so cancel() can call .cancel() on any timers
    // that haven't fired yet (otherwise the dispatch queue keeps them alive
    // until their deadline).
    private var workItems: [Int: DispatchWorkItem] = [:]
    private var nextWorkItemID: Int = 0
    private var cancelled: Bool = false
    private let queue = DispatchQueue(label: "ai.sierra.SecretRefreshOrchestrator")

    init(voiceSession: VoiceSessionManager, callbacks: VoiceCallbacks?) {
        self.voiceSession = voiceSession
        self.callbacks = callbacks
    }

    /// Replace the registered callbacks (used when the host swaps callbacks
    /// after construction).
    func setCallbacks(_ callbacks: VoiceCallbacks?) {
        queue.async { [weak self] in
            self?.callbacks = callbacks
        }
    }

    /// Cancel any in-flight refresh work. Safe to call multiple times.
    func cancel() {
        queue.async { [weak self] in
            guard let self else { return }
            self.cancelled = true
            for item in self.workItems.values {
                item.cancel()
            }
            self.workItems.removeAll()
            self.inFlightSecretNames.removeAll()
        }
    }

    /// Handle a `secret_refresh` custom attachment payload extracted from an
    /// inbound `attachments_server` batch.
    func handle(attachment: [String: Any]) {
        guard let data = attachment["data"] as? [String: Any] else {
            return
        }
        guard let secretName = data["secretName"] as? String, !secretName.isEmpty else {
            debugLog("SecretRefreshOrchestrator: missing or empty secretName, ignoring")
            return
        }

        let initialDelay = (data["initialDelaySeconds"] as? Double) ?? 0
        let retryConfig = parseRetryConfig(data["retryConfig"] as? [String: Any])
        let pending = PendingRefresh(secretName: secretName, initialDelay: max(0, initialDelay), retryConfig: retryConfig)

        queue.async { [weak self] in
            guard let self else { return }
            if self.cancelled { return }
            if self.inFlightSecretNames.contains(secretName) {
                debugLog("SecretRefreshOrchestrator: refresh already in flight for \(secretName), ignoring duplicate")
                return
            }
            self.inFlightSecretNames.insert(secretName)
            self.scheduleAttempt(pending: pending, attemptNumber: 1, after: pending.initialDelay)
        }
    }

    private func parseRetryConfig(_ raw: [String: Any]?) -> RetryConfig {
        let defaults = RetryConfig.defaults
        guard let raw else { return defaults }
        let maxAttempts = (raw["maxAttempts"] as? Int) ?? defaults.maxAttempts
        let initialRetryDelay = (raw["retryDelaySeconds"] as? Double) ?? defaults.initialRetryDelay
        let maxDelay = (raw["maxDelaySeconds"] as? Double) ?? defaults.maxDelay
        return RetryConfig(
            maxAttempts: max(1, maxAttempts),
            initialRetryDelay: max(0, initialRetryDelay),
            maxDelay: max(0, maxDelay)
        )
    }

    private func scheduleAttempt(pending: PendingRefresh, attemptNumber: Int, after delay: TimeInterval) {
        let workItemID = nextWorkItemID
        nextWorkItemID += 1
        let item = DispatchWorkItem { [weak self] in
            // Remove our entry up-front so a long-running session that
            // rotates many secrets doesn't accumulate finished work items.
            // Runs on the orchestrator's serial queue, so this is safe wrt
            // cancel().
            self?.workItems.removeValue(forKey: workItemID)
            self?.attempt(pending: pending, attemptNumber: attemptNumber, retryDelay: pending.retryConfig.initialRetryDelay)
        }
        workItems[workItemID] = item
        if delay <= 0 {
            queue.async(execute: item)
        } else {
            queue.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }

    private func attempt(pending: PendingRefresh, attemptNumber: Int, retryDelay: TimeInterval) {
        if cancelled { return }
        guard let callbacks else {
            debugLog("SecretRefreshOrchestrator: no callbacks registered, dropping refresh for \(pending.secretName)")
            inFlightSecretNames.remove(pending.secretName)
            return
        }

        debugLog("SecretRefreshOrchestrator: attempt \(attemptNumber) for \(pending.secretName)")

        // The host's onSecretExpiry implementation will typically do UIKit work
        // (present an alert, push a view controller, etc.) which UIKit
        // requires on the main thread. Hop to main before invoking the host.
        // The reply handler can come back on any thread; we bounce it back
        // onto our serial queue inside the closure so internal state mutation
        // stays safe.
        DispatchQueue.main.async {
            callbacks.onSecretExpiry(secretName: pending.secretName) { [weak self] result in
                self?.queue.async {
                    guard let self else { return }
                    if self.cancelled { return }
                    switch result {
                    case .success(let value):
                        if let value {
                            self.applySuccess(secretName: pending.secretName, value: value)
                        } else {
                            debugLog("SecretRefreshOrchestrator: host returned nil value for \(pending.secretName); refresh not supported, stopping")
                            self.inFlightSecretNames.remove(pending.secretName)
                        }
                    case .failure(let error):
                        self.handleFailure(pending: pending, attemptNumber: attemptNumber, retryDelay: retryDelay, error: error)
                    }
                }
            }
        }
    }

    private func applySuccess(secretName: String, value: String) {
        guard let voiceSession else {
            debugLog("SecretRefreshOrchestrator: voiceSession was deallocated before refresh applied for \(secretName)")
            inFlightSecretNames.remove(secretName)
            return
        }
        voiceSession.sendMemoryUpdateClient(secrets: [secretName: value])
        let ack: [String: Any] = [
            "type": Self.attachmentType,
            "data": [
                "type": Self.secretRefreshedDataType,
                "secretName": secretName,
            ],
        ]
        voiceSession.sendAttachmentsClient([ack])
        inFlightSecretNames.remove(secretName)
    }

    private func handleFailure(pending: PendingRefresh, attemptNumber: Int, retryDelay: TimeInterval, error: Error) {
        if attemptNumber >= pending.retryConfig.maxAttempts {
            debugLog("SecretRefreshOrchestrator: giving up on \(pending.secretName) after \(attemptNumber) attempt(s): \(error.localizedDescription)")
            inFlightSecretNames.remove(pending.secretName)
            return
        }
        let nextDelay = min(retryDelay * 2, pending.retryConfig.maxDelay)
        debugLog("SecretRefreshOrchestrator: attempt \(attemptNumber) for \(pending.secretName) failed (\(error.localizedDescription)); retrying in \(retryDelay)s")
        let workItemID = nextWorkItemID
        nextWorkItemID += 1
        let item = DispatchWorkItem { [weak self] in
            self?.workItems.removeValue(forKey: workItemID)
            self?.attempt(pending: pending, attemptNumber: attemptNumber + 1, retryDelay: nextDelay)
        }
        workItems[workItemID] = item
        queue.asyncAfter(deadline: .now() + retryDelay, execute: item)
    }
}
