// Copyright Sierra

import Foundation
import SierraSDK

public protocol AgentVoiceChatCoordinatorDelegate: AnyObject {
    /// Called when the user taps the switch-to-chat button in voice. The host should
    /// present the chat controller created via `coordinator.makeChatController()` so the
    /// conversation continues in chat with the transcript preserved.
    func coordinatorDidRequestShowingChat(_ coordinator: AgentVoiceChatCoordinator)

    /// Called when the user taps the reconnect-voice button in chat. The host should
    /// present the voice controller created via `coordinator.makeVoiceController()` so the
    /// conversation continues in voice.
    func coordinatorDidRequestVoiceReconnect(_ coordinator: AgentVoiceChatCoordinator)

    /// Called when the voice session ends naturally (user tapped the End button or the
    /// session ended for another reason). The host should typically dismiss or pop the
    /// voice controller. Default: no-op.
    func coordinatorVoiceDidEnd(_ coordinator: AgentVoiceChatCoordinator)

    /// Called when the voice session encounters an error. Default: no-op.
    func coordinator(_ coordinator: AgentVoiceChatCoordinator, didEncounterVoiceError error: Error)

    /// Called when the voice session receives agent-produced attachments. Hosts can inspect the
    /// payload and route into native app surfaces.
    func coordinator(
        _ coordinator: AgentVoiceChatCoordinator,
        didReceiveAgentAttachment attachments: [AgentAttachment]
    )
}

public extension AgentVoiceChatCoordinatorDelegate {
    func coordinatorVoiceDidEnd(_ coordinator: AgentVoiceChatCoordinator) {}
    func coordinator(_ coordinator: AgentVoiceChatCoordinator, didEncounterVoiceError error: Error) {}
    func coordinator(
        _ coordinator: AgentVoiceChatCoordinator,
        didReceiveAgentAttachment attachments: [AgentAttachment]
    ) {}
}

public final class AgentVoiceChatCoordinator {
    private struct PersistedConversationState: Codable {
        let conversationID: String?
        let encryptionKey: String?
        let voiceConversationID: String?
        let voiceResumeToken: String?
    }

    public struct Options {
        public var voiceOptions: AgentVoiceControllerOptions
        public var chatOptions: AgentChatControllerOptions

        /// Shared listener for events that the agent runtime can emit during either a chat or a
        /// voice conversation (e.g. `onSecretExpiry`, `onLinkClick`). Implement once and the
        /// coordinator routes the same logic into both surfaces. Hosts that need surface-specific
        /// behavior can still set `chatOptions.conversationCallbacks` directly; the listener is
        /// only adapted into chat callbacks when none are provided. Retain this listener in your
        /// app code for as long as the coordinator may use it.
        public weak var agentEventListener: AgentEventListener?

        /// When true, the voice view includes a navigation-bar button that lets the user switch
        /// from voice to chat without ending the conversation. On tap, the SVP session is closed
        /// with the `continue_in_chat` close reason and the chat view is presented with the
        /// transcript preserved. End and dismissal still terminate the conversation as usual.
        public var canSwitchToChat: Bool = true

        /// When true, the chat view shown after a voice session ends includes a navigation-bar
        /// button that lets the user reconnect to voice and continue the same conversation. On
        /// reconnect, the server emits a `continue-in-voice` client event, allowing the agent to
        /// greet the user and acknowledge the return to voice.
        public var canReconnectToVoice: Bool = false

        /// When true (and `canSwitchToChat` is also true), the voice session's natural end --
        /// whether the user taps the End button or the agent ends the conversation server-side --
        /// is treated like a switch-to-chat: the coordinator fires
        /// `coordinatorDidRequestShowingChat` instead of `coordinatorVoiceDidEnd`, and the chat
        /// view opens with the voice transcript seeded. No-op if `canSwitchToChat` is false.
        public var autoShowChatOnEnd: Bool = true

        public init(
            voiceOptions: AgentVoiceControllerOptions,
            chatOptions: AgentChatControllerOptions,
            agentEventListener: AgentEventListener? = nil,
            canSwitchToChat: Bool = true,
            canReconnectToVoice: Bool = false,
            autoShowChatOnEnd: Bool = true
        ) {
            self.voiceOptions = voiceOptions
            self.chatOptions = chatOptions
            self.agentEventListener = agentEventListener
            self.canSwitchToChat = canSwitchToChat
            self.canReconnectToVoice = canReconnectToVoice
            self.autoShowChatOnEnd = autoShowChatOnEnd
        }
    }

    public private(set) var voiceConversationID: String?
    public private(set) var conversationID: String?
    public private(set) var encryptionKey: String?
    public private(set) var voiceResumeToken: String?

    public weak var delegate: AgentVoiceChatCoordinatorDelegate?
    public weak var agentEventListener: AgentEventListener?

    private let agent: Agent
    private let options: Options
    private var pendingContinueInChat = false
    private var chatCallbacksAdapter: ChatCallbacksAdapter?

    public init(agent: Agent, options: Options) {
        self.agent = agent
        self.options = options
        self.agentEventListener = options.agentEventListener
        restorePersistedConversationState()
    }

    public func makeVoiceController() -> AgentVoiceController {
        var voiceOptions = options.voiceOptions
        let shouldResumeConversation =
            voiceConversationID != nil || (voiceOptions.resumeConversation && voiceOptions.voiceConversationID != nil)
        let voiceConversationID = self.voiceConversationID ?? voiceOptions.voiceConversationID ?? UUID().uuidString
        self.voiceConversationID = voiceConversationID

        voiceOptions.voiceConversationID = voiceConversationID
        voiceOptions.resumeConversation = shouldResumeConversation
        voiceOptions.resumeToken = voiceResumeToken
        if shouldResumeConversation {
            voiceOptions.resumeReason = .continueInVoice
        }
        if options.canSwitchToChat {
            voiceOptions.canSwitchToChat = true
            voiceOptions.onSwitchToChat = { [weak self] in
                self?.handleSwitchToChat()
            }
            voiceOptions.endRoutesToChat = options.autoShowChatOnEnd
        }

        let voiceController = AgentVoiceController(agent: agent, options: voiceOptions)
        voiceController.voiceCallbacks = self
        return voiceController
    }

    public func makeChatController() -> AgentChatController {
        if pendingContinueInChat {
            seedChatContinuationStateIfAvailable()
            pendingContinueInChat = false
        }

        var chatOptions = options.chatOptions
        // Expose the reconnect-to-voice button only when (a) the host opted in via
        // `options.canReconnectToVoice` and (b) the conversation actually originated in voice.
        if options.canReconnectToVoice && voiceConversationID != nil {
            chatOptions.canReconnectToVoice = true
            chatOptions.onReconnectVoice = { [weak self] in
                guard let self else { return }
                self.delegate?.coordinatorDidRequestVoiceReconnect(self)
            }
        }
        // When the conversation ends from the chat side, drop coordinator state so a subsequent
        // Reconnect-voice tap doesn't try to resume an already-ended chat.
        chatOptions.onConversationEnded = { [weak self] in
            self?.resetConversation()
        }
        // Bridge the shared `AgentEventListener` into chat callbacks when the host hasn't set its
        // own. Hosts that supply `chatOptions.conversationCallbacks` keep full control and the
        // adapter stays out of the way.
        if chatOptions.conversationCallbacks == nil, let agentEventListener {
            let adapter = ChatCallbacksAdapter(listener: agentEventListener)
            chatCallbacksAdapter = adapter
            chatOptions.conversationCallbacks = adapter
        } else {
            chatCallbacksAdapter = nil
        }
        return AgentChatController(agent: agent, options: chatOptions)
    }

    /// Discards any persisted voice/chat conversation state held by the coordinator so the next
    /// `makeVoiceController()` or `makeChatController()` starts fresh.
    public func resetConversation() {
        voiceConversationID = nil
        conversationID = nil
        encryptionKey = nil
        voiceResumeToken = nil
        pendingContinueInChat = false
        agent.resetConversation()
    }

    private func handleSwitchToChat() {
        pendingContinueInChat = true
        delegate?.coordinatorDidRequestShowingChat(self)
    }

    private func seedChatContinuationStateIfAvailable() {
        guard let conversationID, let encryptionKey else { return }

        guard
            let jsonData = try? JSONSerialization.data(
                withJSONObject: persistedChatContinuationState(
                    conversationID: conversationID,
                    encryptionKey: encryptionKey
                )
            ),
            let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            debugLog("AgentVoiceChatCoordinator: failed to serialize chat continuation state")
            return
        }

        agent.getStorage().setItem(persistedConversationStorageKey(), jsonString)
    }

    private func persistedConversationStorageKey() -> String {
        // Keep this in sync with persistedConversationKey() on the web side
        "embed-chat-\(agent.config.token)"
    }

    private func persistedChatContinuationState(
        conversationID: String,
        encryptionKey: String
    ) -> [String: Any] {
        var state: [String: Any] = [
            "conversationID": conversationID,
            "encryptionKey": encryptionKey,
            "continueInChatOnResume": true,
        ]
        if let voiceConversationID {
            state["voiceConversationID"] = voiceConversationID
        }
        if let voiceResumeToken {
            state["voiceResumeToken"] = voiceResumeToken
        }
        return state
    }

    private func restorePersistedConversationState() {
        guard let persistedState = loadPersistedConversationState() else { return }
        conversationID = persistedState.conversationID
        encryptionKey = persistedState.encryptionKey
        if voiceConversationID == nil {
            voiceConversationID = persistedState.voiceConversationID
        }
        if voiceResumeToken == nil {
            voiceResumeToken = persistedState.voiceResumeToken
        }
    }

    private func loadPersistedConversationState() -> PersistedConversationState? {
        guard
            let jsonString = agent.getStorage().getItem(persistedConversationStorageKey()),
            let jsonData = jsonString.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode(PersistedConversationState.self, from: jsonData)
    }
}

/// Bridge that forwards the chat-side `ConversationCallbacks` events the coordinator cares about
/// (currently just the shared `AgentEventListener` events) to a single shared listener. Used only
/// when the host did not supply its own `chatOptions.conversationCallbacks`; otherwise the host's
/// callbacks pass through unchanged.
private final class ChatCallbacksAdapter: ConversationCallbacks {
    weak var listener: AgentEventListener?

    init(listener: AgentEventListener) {
        self.listener = listener
    }

    func onLinkClick(url: URL) -> Bool {
        listener?.onLinkClick(url: url) ?? false
    }

    func onSecretExpiry(secretName: String, replyHandler: @escaping (Result<String?, any Error>) -> Void) {
        guard let listener else {
            replyHandler(.success(nil))
            return
        }
        listener.onSecretExpiry(secretName: secretName, replyHandler: replyHandler)
    }
}

extension AgentVoiceChatCoordinator: VoiceCallbacks {
    public func onVoiceEnded() {
        if options.canSwitchToChat && options.autoShowChatOnEnd {
            handleSwitchToChat()
            return
        }
        resetConversation()
        delegate?.coordinatorVoiceDidEnd(self)
    }

    public func onVoiceDismissed() {
        resetConversation()
    }

    public func onVoiceError(error: Error) {
        delegate?.coordinator(self, didEncounterVoiceError: error)
    }

    public func didReceiveAgentAttachment(attachments: [AgentAttachment]) {
        delegate?.coordinator(self, didReceiveAgentAttachment: attachments)
    }

    public func onLinkClick(url: URL) -> Bool {
        agentEventListener?.onLinkClick(url: url) ?? false
    }

    public func onSecretExpiry(secretName: String, replyHandler: @escaping (Result<String?, any Error>) -> Void) {
        guard let agentEventListener else {
            // No listener is registered; fall back to the protocol default so the orchestrator
            // doesn't hang waiting for a reply.
            replyHandler(.success(nil))
            return
        }
        agentEventListener.onSecretExpiry(secretName: secretName, replyHandler: replyHandler)
    }

    public func onSessionInfoReceived(conversationID: String, encryptionKey: String) {
        self.conversationID = conversationID
        self.encryptionKey = encryptionKey
    }

    public func onResumeTokenReceived(token: String) {
        self.voiceResumeToken = token
    }
}
