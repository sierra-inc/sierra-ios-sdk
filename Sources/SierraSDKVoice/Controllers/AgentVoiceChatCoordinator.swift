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
        let continueInChatOnResume: Bool?
        let agentHandoffOnResume: Bool?
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
        /// transcript preserved. Dismissing the voice view (e.g. back navigation) also closes the
        /// session with `continue_in_chat`, keeping the conversation resumable in chat.
        public var canSwitchToChat: Bool = true

        /// When true, the chat view shown after a voice session ends includes a navigation-bar
        /// button that lets the user reconnect to voice and continue the same conversation. On
        /// reconnect, the server emits a `continue-in-voice` client event, allowing the agent to
        /// greet the user and acknowledge the return to voice.
        public var canReconnectToVoice: Bool = false

        /// When true, the voice session's natural end -- whether the user taps the End button or
        /// the agent ends the conversation server-side -- is treated like a switch-to-chat: the
        /// coordinator fires `coordinatorDidRequestShowingChat` instead of
        /// `coordinatorVoiceDidEnd`, and the chat view opens with the voice transcript seeded.
        /// Independent from `canSwitchToChat`, which only controls whether the manual navigation
        /// bar button is shown.
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
    // One-shot latch: armed by the voice switch action, a dismissal that seeded continuation
    // state, or unconsumed seeded state found at init. Consumed by the next `makeChatController()`
    // call, which seeds storage and suppresses the conversation list for that first presentation.
    private var pendingContinueInChat = false
    // True when the pending switch was agent-initiated (vs a manual "Continue in chat" tap); the
    // seeded chat state then drives the agent on resume instead of switching silently.
    private var pendingAgentHandoff = false
    // One-shot: armed by the reconnect-to-voice action (built-in chat button or
    // `prepareVoiceReconnect()`), consumed by the next `makeVoiceController()`. All other voice
    // launches start a new conversation.
    private var pendingReconnectVoice = false
    // Set when the voice session reports an error; the server then treats the call as disconnected
    // and terminal, so a later dismissal resets instead of seeding chat continuation state.
    private var voiceSessionErrored = false
    private var chatCallbacksAdapter: ChatCallbacksAdapter?

    public init(agent: Agent, options: Options) {
        self.agent = agent
        self.options = options
        self.agentEventListener = options.agentEventListener
        restorePersistedConversationState()
    }

    public func makeVoiceController() -> AgentVoiceController {
        var voiceOptions = options.voiceOptions
        if voiceOptions.userIdentityToken == nil {
            voiceOptions.userIdentityToken = options.chatOptions.userIdentityToken
        }
        let isReconnect = pendingReconnectVoice
        pendingReconnectVoice = false
        voiceSessionErrored = false
        // Launching voice supersedes any voice-to-chat handoff the host never presented; drop the
        // latch so a later chat open doesn't seed a stale resume flag.
        pendingContinueInChat = false
        pendingAgentHandoff = false
        let configuredVoiceConversationID = voiceOptions.voiceConversationID
        let configuredIDChanged =
            configuredVoiceConversationID != nil && configuredVoiceConversationID != voiceConversationID
        if configuredIDChanged {
            resetConversation()
        }
        let shouldResumeConversation =
            isReconnect && voiceConversationID != nil && voiceResumeToken != nil
        if !shouldResumeConversation {
            // Voice resume is an explicit, one-shot reconnect action; every other launch starts a
            // new voice conversation. Clear the in-memory chat credentials too: they describe the
            // previous conversation, and a dismissal before this session delivers its own
            // credentials must not seed them against this launch's voice ID. The previous
            // conversation stays resumable through persisted storage, which is left untouched
            // until this session seeds its replacement.
            voiceConversationID = configuredVoiceConversationID ?? UUID().uuidString
            voiceResumeToken = nil
            conversationID = nil
            encryptionKey = nil
        }

        voiceOptions.voiceConversationID = voiceConversationID
        voiceOptions.resumeConversation = shouldResumeConversation
        voiceOptions.resumeToken = voiceResumeToken
        if shouldResumeConversation {
            voiceOptions.resumeReason = .continueInVoice
        }
        voiceOptions.onSwitchToChat = { [weak self] agentInitiated in
            self?.handleSwitchToChat(agentInitiated: agentInitiated)
        }
        voiceOptions.canSwitchToChat = options.canSwitchToChat
        voiceOptions.autoShowChatOnEnd = options.autoShowChatOnEnd
        voiceOptions.continueInChatOnDismiss = true

        let voiceController = AgentVoiceController(agent: agent, options: voiceOptions)
        voiceController.voiceCallbacks = self
        return voiceController
    }

    public func makeChatController() -> AgentChatController {
        let isVoiceToChatHandoff = pendingContinueInChat
        if isVoiceToChatHandoff {
            seedChatContinuationStateIfAvailable(agentInitiated: pendingAgentHandoff)
            pendingContinueInChat = false
            pendingAgentHandoff = false
        }

        var chatOptions = options.chatOptions
        if isVoiceToChatHandoff {
            chatOptions.showConversationListByDefault = false
        }
        if chatOptions.userIdentityToken?.isEmpty != false {
            chatOptions.userIdentityToken = options.voiceOptions.userIdentityToken
        }
        // Expose the reconnect-to-voice button only when (a) the host opted in via
        // `options.canReconnectToVoice` and (b) the conversation actually originated in voice.
        if options.canReconnectToVoice && voiceConversationID != nil {
            chatOptions.canReconnectToVoice = true
            chatOptions.onReconnectVoice = { [weak self] in
                guard let self else { return }
                self.prepareVoiceReconnect()
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
        pendingAgentHandoff = false
        pendingReconnectVoice = false
        voiceSessionErrored = false
        agent.resetConversation()
    }

    /// Arms the next `makeVoiceController()` call to resume the current voice conversation instead
    /// of starting a new one; the server then emits a `continue-in-voice` client event so the agent
    /// can greet the user back to voice. The built-in reconnect-to-voice chat button
    /// (`Options.canReconnectToVoice`) arms this automatically; call it directly when presenting
    /// voice from a custom reconnect control. One-shot: consumed by the next
    /// `makeVoiceController()` call.
    public func prepareVoiceReconnect() {
        pendingReconnectVoice = true
    }

    private func handleSwitchToChat(agentInitiated: Bool) {
        pendingContinueInChat = true
        pendingAgentHandoff = agentInitiated
        delegate?.coordinatorDidRequestShowingChat(self)
    }

    private func seedChatContinuationStateIfAvailable(agentInitiated: Bool) {
        guard let conversationID, let encryptionKey else { return }

        guard
            let jsonData = try? JSONSerialization.data(
                withJSONObject: persistedChatContinuationState(
                    conversationID: conversationID,
                    encryptionKey: encryptionKey,
                    agentInitiated: agentInitiated
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
        encryptionKey: String,
        agentInitiated: Bool
    ) -> [String: Any] {
        var state: [String: Any] = [
            "conversationID": conversationID,
            "encryptionKey": encryptionKey,
        ]
        // An agent-initiated handoff drives the chat agent (the embed sends a continue-in-chat
        // client event on resume); a manual switch stays silent. The embed reads exactly one flag.
        if agentInitiated {
            state["agentHandoffOnResume"] = true
        } else {
            state["continueInChatOnResume"] = true
        }
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
        voiceConversationID = persistedState.voiceConversationID
        voiceResumeToken = persistedState.voiceResumeToken
        // Seeded resume flags mean the last voice session ended toward chat and no chat controller
        // has consumed them yet (the embed strips them once chat opens). Re-arm the one-shot latch
        // so the next chat open still lands on the continued transcript instead of the list, even
        // across an app restart.
        pendingAgentHandoff = persistedState.agentHandoffOnResume ?? false
        pendingContinueInChat =
            pendingAgentHandoff || (persistedState.continueInChatOnResume ?? false)
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
        if options.autoShowChatOnEnd {
            handleSwitchToChat(agentInitiated: false)
            return
        }
        resetConversation()
        delegate?.coordinatorVoiceDidEnd(self)
    }

    public func onVoiceDismissed() {
        // Dismissal (e.g. back navigation) closes the voice leg with `continue_in_chat`, so persist
        // the continuation state immediately -- the user may not open chat until after an app
        // restart.
        guard conversationID != nil, encryptionKey != nil else {
            // This session never delivered credentials (dismissed or errored before session info
            // arrived), so it created nothing continuable. Leave persisted storage untouched and
            // re-sync memory to it so the previous conversation, if any, stays resumable in chat
            // and voice.
            voiceConversationID = nil
            conversationID = nil
            encryptionKey = nil
            voiceResumeToken = nil
            restorePersistedConversationState()
            return
        }
        if voiceSessionErrored {
            // The server treats an errored call as disconnected and terminal; nothing to resume.
            resetConversation()
            return
        }
        seedChatContinuationStateIfAvailable(agentInitiated: false)
        // Arm the one-shot latch so the next chat open lands on the continued transcript instead
        // of the conversation list.
        pendingContinueInChat = true
        pendingAgentHandoff = false
    }

    public func onVoiceError(error: Error) {
        voiceSessionErrored = true
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
