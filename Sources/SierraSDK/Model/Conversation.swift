// Copyright Sierra

import Foundation
import UIKit

public struct ConversationOptions {
    /// Initial values for variables (possible variables are agent-specific).
    public var variables: [String: String]?
    /// Initial values for secrets (possible variables are agent-specific)..
    public var secrets: [String: String]?
    /// Locale to use for the chat conversation, if the agent is multi-lingual.
    /// If not specified, the device's locale will be used.
    public var locale: Locale?
    /// Custom greeting that the agent has used (before it has interacted with
    /// the user).
    public var customGreeting: String?
    /// Enables contact center integration for this agent. Only has an effect
    /// for agents where the integration is controlled per-conversation (as
    /// opposed to being globally enabled or disabled).
    public var enableContactCenter: Bool?

    public init() { }
}

public protocol ConversationCallbacks: AnyObject {
    /// Callback invoked when the user chatting with the virtual agent has requested a transfer to an
    /// external agent.
    func onConversationTransfer(transfer: ConversationTransfer)
    /// Callback invoked when a conversation starts.
    func onConversationStart(conversationID: String)
    /// Callback invoked when the virtual agent finishes replying to the user.
    /// Not invoked for the greeting message.
    func onAgentMessageEnd()
    /// Callback invoked when the ability to end the conversation changes.
    func onRequestEndConversationEnabledChange(_ enabled: Bool)
    /// Callback invoked when the conversation ends.
    func onConversationEnded()
    /// Callback invoked when a non-Sierra agent joins the conversation.
    func onExternalAgentJoin(externalConversationID: String?, externalAgentID: String?)
    /// Callback invoked when a secret needs needs to be refreshed. Reply handler should be invoked with one of:
    /// - a new value for the secret
    /// - nil if the secret cannot be provided due to a known condition (e.g. the user has signed out)
    /// - an error if the secret cannot be fetched right now, but the request should be retried.
    func onSecretExpiry(secretName: String, replyHandler: @escaping (Result<String?, any Error>) -> Void)
}

// Default no-op implementations of ConversationCallbacks, so that clients can
// implement only the subset that they care about.
public extension ConversationCallbacks {
    func onConversationTransfer(transfer: ConversationTransfer) {}
    func onConversationStart(conversationID: String) {}
    func onAgentMessageEnd() {}
    func onRequestEndConversationEnabledChange(_ enabled: Bool) {}
    func onConversationEnded() {}
    func onExternalAgentJoin(externalConversationID: String?, externalAgentID: String?) {}
    func onSecretExpiry(secretName: String, replyHandler: @escaping (Result<String?, any Error>) -> Void) {
        replyHandler(.success(nil))
    }
}

public struct ConversationTransfer {
    /// True if a synchronous transfer was requested, and the user expects the
    /// conversation to continue immediately.
    public let isSynchronous: Bool
    /// True if the transfer was handled by a Sierra Contact Center integration,
    /// and the conversation with the human agent will continue in the same chat.
    public let isContactCenter: Bool
    /// Additional (customer-specific) data, to allow a hand-off from the virtual
    /// agent to the external agent.
    public let data: Dictionary<String, String>
}

extension ConversationTransfer: Decodable {
    private enum CodingKeys: String, CodingKey {
        case isSynchronous, isContactCenter, data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isSynchronous = try container.decodeIfPresent(Bool.self, forKey: .isSynchronous) ?? false
        isContactCenter = try container.decodeIfPresent(Bool.self, forKey: .isContactCenter) ?? false

        let dataArray = try container.decodeIfPresent([[String: String]].self, forKey: .data) ?? []
        var dataMap = [String: String]()
        for item in dataArray {
            if let key = item["key"], let value = item["value"] {
                dataMap[key] = value
            }
        }
        data = dataMap
    }
}

extension ConversationTransfer {
    public static func fromJSON(_ json: String) -> ConversationTransfer? {
        guard let jsonData = json.data(using: .utf8) else {
            debugLog("Could not convert JSON string to data")
            return nil
        }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(ConversationTransfer.self, from: jsonData)
        } catch {
            debugLog("Error decoding transfer data: \(error)")
            return nil
        }
    }
}

func debugLog(_ message: String) {
    #if DEBUG
    debugPrint(message)
    #endif
}


/// Conversation encapsulates the UI state of a agent conversation
@available(*, deprecated)
public class Conversation {
    public var messages: [Message] = []
    public var canSend: Bool = true {
        didSet {
            forEachDelegate { delegate in
                delegate.conversation(self, didChangeCanSend: self.canSend)
            }
        }
    }
    public var conversationEnded: Bool = false {
        didSet {
            forEachDelegate { delegate in
                delegate.conversation(self, didChangeConversationEnded: self.conversationEnded)
            }
        }
    }
    public var isSynchronouslyTransferred: Bool = false
    public var canSaveTranscript: Bool {
        get {
            return state != nil
        }
    }

    private let api: AgentAPI
    private let options: ConversationOptions?
    private var state: String? {
        didSet {
            forEachDelegate { delegate in
                delegate.conversation(self, didChangeCanSaveTranscript: self.canSaveTranscript)
            }
        }
    }
    private var delegates = NSHashTable<AnyObject>.weakObjects()
    private var humanAgentParticipation: HumanAgentParticipation? {
        didSet {
            forEachDelegate { delegate in
                delegate.conversation(self, didChangeHumanAgentParticipation: self.humanAgentParticipation, previousValue: oldValue)
            }
            guard let humanAgentParticipation else {
                stopPolling()
                return
            }
            // Even if the agent has left, another may join, so we can't stop polling.
            startPolling()
        }
    }
    private var pollingTask: Task<Void, Error>?
    private var pollingCursor: String?
    private var hasConversationEndMessage: Bool = false

    init(api: AgentAPI, options: ConversationOptions?) {
        self.api = api
        self.options = options
    }

    public func addGreetingMessage(_ text: String) {
        let message = Message(role: .assistant, content: text)
        messages.append(message)
        forEachDelegate { delegate in
            delegate.conversation(self, didAddMessages: [message.id])
        }
    }

    public func addStatusMessage(_ text: String) {
        let message = Message(role: .status, content: text)
        messages.append(message)
        forEachDelegate { delegate in
            delegate.conversation(self, didAddMessages: [message.id])
        }
    }

    public func messageWithID(_ id: MessageID) -> Message? {
        for message in messages {
            if message.id == id {
                return message
            }
        }
        return nil
    }

    func shouldShowSenderName(_ id: MessageID) -> Bool {
        for (i, message) in messages.enumerated() {
            if message.id == id {
                return i > 0 && message.role != messages[i - 1].role
            }
        }
        return false
    }

    func addDelegate(_ delegate: ConversationDelegate) {
        delegates.add(delegate)
        if delegates.count == 1 && (humanAgentParticipation?.state == .waiting || humanAgentParticipation?.state == .joined) {
            startPolling()
        }
    }

    func removeDelegate(_ delegate: ConversationDelegate) {
        delegates.remove(delegate)
        if delegates.count == 0 {
            stopPolling()
        }
    }

    private func forEachDelegate(_ closure: @escaping (ConversationDelegate) -> Void) {
       for delegate in delegates.allObjects {
           if let delegate = delegate as? ConversationDelegate {
               // Ensure delegate methods are called on the main thread
               DispatchQueue.main.async {
                   closure(delegate)
               }
           }
       }
    }

    public func saveTranscript() async throws -> Data {
        guard let state else {
            throw ConversationError.stateNotAvailable
        }

       let pdfData = try await api.saveTranscript(state: state, options: options)
       return pdfData
    }

    public func sendUserMessage(text: String) async {
        if !canSend {
            debugLog("Cannot send message, send already in progress")
            return
        }
        canSend = false
        let userMessage = Message(role: .user, content: text)
        messages.append(userMessage)

        var polling = false
        var assistantMessageIndex = -1
        var newMessageIDs = [userMessage.id]
        if self.humanAgentParticipation != nil {
            // We're interacting with a human agent, in which case we'll get back
            // responses via the polling loop, and we can't assume that the agent
            // will start typing immediately.
            if pollingTask == nil {
                debugLog("Restarting polling loop")
                self.startPolling()
            }
            polling = true
        } else {
            var assistantMessage = Message.createInitialAssistantMessage()
            assistantMessageIndex = messages.count
            messages.append(assistantMessage)
            newMessageIDs.append(assistantMessage.id)
        }

        forEachDelegate { delegate in
            delegate.conversation(self, didAddMessages: newMessageIDs)
        }

        func cleanupTypingIndicator() {
            if assistantMessageIndex != -1 && messages[assistantMessageIndex].isTypingIndicator {
                let assistantMessageID = messages[assistantMessageIndex].id
                messages.remove(at: assistantMessageIndex)
                forEachDelegate { [assistantMessageID] delegate in
                    delegate.conversation(self, didRemoveMessage: assistantMessageID)
                }
                assistantMessageIndex = -1
            }
        }

        do {
            let stream = try await api.sendMessage(text: text, state: state, options: options, polling: polling)
            for try await event in stream {
                switch event.type {
                case "state":
                    state = event.state
                case "message":
                    guard let message = event.message else { continue }
                    updateWithMessageEvent(&assistantMessageIndex, message)
                case "transfer":
                    guard let transfer = event.transfer else { continue }
                    cleanupTypingIndicator()
                    let conversationTransfer = ConversationTransfer(
                        isSynchronous: transfer.isSynchronous ?? false,
                        isContactCenter: transfer.isContactCenter ?? false,
                        data: transfer.data ?? [:]
                    )
                    forEachDelegate { delegate in
                        delegate.conversation(self, didTransfer: conversationTransfer)
                    }
                    isSynchronouslyTransferred = transfer.isSynchronous ?? false
                    if transfer.isContactCenter ?? false {
                        humanAgentParticipation = HumanAgentParticipation()
                    }
                case "endConversation":
                    guard let endConversation = event.endConversation else { continue }
                    cleanupTypingIndicator()
                    conversationEnded = true
                case "error":
                    guard let error = event.error else { continue }
                    let errorMessage = error.userVisibleMessage
                    cleanupTypingIndicator()
                    forEachDelegate { delegate in
                        delegate.conversation(self, didHaveError: nil, withMessage: errorMessage)
                    }
                default:
                    debugLog("Unknown event type: \(event.type)")
                }
            }
        } catch {
            debugLog("Cannot send message, error: \(error)")
            cleanupTypingIndicator()
            forEachDelegate{ delegate in
                delegate.conversation(self, didHaveError: error, withMessage: (error as? AgentChatError)?.errorMessage)
            }
        }
        if !conversationEnded && (!isSynchronouslyTransferred || humanAgentParticipation?.state == .joined) {
            canSend = true
        }

        await checkForConversationEnd()
    }

    private func startPolling() {
        if pollingTask != nil {
            return
        }

        pollingTask = Task {
            // api.poll is a regenerating hanging GET that may regenerate too
            // frequently when the server is failing fast; we should backoff on errors
            var backoffDelay: TimeInterval = 1
            var consecutiveErrors = 0
            var cancelled = false

            // We may have a typing indicator from a previous polling run that was interrupted
            var typingIndicatorMessageIndex = messages.lastIndex(where: { $0.isTypingIndicator && $0.role == .humanAgent }) ?? -1

            func cleanupTypingIndicator() {
                if typingIndicatorMessageIndex != -1 {
                    if messages[typingIndicatorMessageIndex].isTypingIndicator {
                        let messageID = messages[typingIndicatorMessageIndex].id
                        messages.remove(at: typingIndicatorMessageIndex)
                        forEachDelegate { [messageID] delegate in
                            delegate.conversation(self, didRemoveMessage: messageID)
                        }
                    }
                    typingIndicatorMessageIndex = -1
                }
            }

            while !cancelled && !conversationEnded {
                do {
                    let stream = try await api.poll(state: state, cursor: pollingCursor, options: options)
                    // Consume the stream
                    for try await event in stream {
                        try Task.checkCancellation()
                        switch event.type {
                        case "livePollCursor":
                            guard let newCursor = event.livePollCursor else { continue }
                            pollingCursor = newCursor
                        case "message":
                            backoffDelay = 1
                            consecutiveErrors = 0
                            guard let message = event.message else { continue }
                            if message.role != "human_agent" {
                                continue
                            }
                            // If we somehow missed the humanAgentInfo update but the human agent is sending
                            // messages to the user, they should be able to respond.
                            if self.humanAgentParticipation?.state != .left && !canSend {
                                debugLog("Overriding canSend due to human agent message")
                                var humanAgentParticipation = self.humanAgentParticipation ?? HumanAgentParticipation()
                                humanAgentParticipation.state = .joined
                                self.humanAgentParticipation = humanAgentParticipation
                                canSend = true
                            }

                            // More messages (possibly from the user) appeared after we added the typing indicator. Remove it
                            // so that we can append the new agent message at the bottom.
                            if typingIndicatorMessageIndex != -1 && typingIndicatorMessageIndex != messages.count - 1 {
                                cleanupTypingIndicator()
                            }

                            if typingIndicatorMessageIndex == -1 {
                                var agentMessage = Message(role: .humanAgent, content: message.text ?? "")
                                if let attachments = message.attachments {
                                    agentMessage.appendAttachments(attachments)
                                }
                                messages.append(agentMessage)
                                let agentMessageID = agentMessage.id
                                forEachDelegate { [agentMessageID] delegate in
                                    delegate.conversation(self, didAddMessages: [agentMessageID])
                                }
                            } else {
                                if let attachments = message.attachments {
                                    messages[typingIndicatorMessageIndex].appendAttachments(attachments)
                                }
                                messages[typingIndicatorMessageIndex].appendContent(piece: message.text ?? "")
                                let agentMessageID = messages[typingIndicatorMessageIndex].id
                                typingIndicatorMessageIndex = -1
                                forEachDelegate { [agentMessageID] delegate in
                                    delegate.conversation(self, didChangeMessage: agentMessageID)
                                }
                            }
                        case "humanAgentInfo":
                            guard let info = event.humanAgentInfo else { continue }
                            var humanAgentParticipation = self.humanAgentParticipation ?? HumanAgentParticipation()
                            if let displayName = info.displayName {
                                humanAgentParticipation.agent = HumanAgent(displayName: displayName)
                            }
                            if let queueSize = info.queueSize {
                                humanAgentParticipation.queueSize = queueSize
                            }
                            if info.joined == true {
                                humanAgentParticipation.state = .joined
                                canSend = true
                            }
                            if info.left == true {
                                humanAgentParticipation.state = .left
                                canSend = false
                                cleanupTypingIndicator()
                            }
                            if info.typing == true && typingIndicatorMessageIndex == -1 {
                                var message = Message.createInitialHumanAgentMessage()
                                typingIndicatorMessageIndex = messages.count
                                messages.append(message)
                                forEachDelegate { delegate in
                                    delegate.conversation(self, didAddMessages: [message.id])
                                }
                            }
                            self.humanAgentParticipation = humanAgentParticipation
                        case "endConversation":
                            guard let endConversation = event.endConversation else { continue }
                            cleanupTypingIndicator()
                            conversationEnded = true
                        case "error":
                            guard let error = event.error else { continue }
                            let errorMessage = error.userVisibleMessage
                            forEachDelegate { delegate in
                                delegate.conversation(self, didHaveError: nil, withMessage: errorMessage)
                            }
                        default:
                            debugLog("Unknown event type: \(event.type)")
                        }
                    }
                    await checkForConversationEnd()
                } catch {
                    if let _ = error as? CancellationError {
                        cancelled = true
                    } else {
                        backoffDelay *= pow(1.5, Double(consecutiveErrors))
                        backoffDelay = min(backoffDelay, 60.0)
                        consecutiveErrors += 1
                        debugLog("Polling error: \(error), will retry in \(backoffDelay)s")
                        try await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
                    }
                }
            }
        }
    }

    private func stopPolling() {
        guard let pollingTask else { return }
        pollingTask.cancel()
        self.pollingTask = nil
    }

    private func updateWithMessageEvent(_ assistantMessageIndex: inout Int, _ message: APIEvent.Message) {
        if message.role != "assistant" {
            return
        }
        let messageText = message.text
        let messageAttachments = message.attachments ?? []
        let isEndOfMessage = message.isEndOfMessage
        let preparingFollowup = message.preparingFollowup
        if messageText != nil || !messageAttachments.isEmpty {
            if assistantMessageIndex == -1 {
                let assistantMessage = Message(role: .assistant, content: "")
                assistantMessageIndex = messages.count
                messages.append(assistantMessage)
                forEachDelegate { delegate in
                    delegate.conversation(self, didAddMessages: [assistantMessage.id])
                }
            }
            if let messageText {
                messages[assistantMessageIndex].appendContent(piece: messageText)
            }
            if !messageAttachments.isEmpty {
                messages[assistantMessageIndex].appendAttachments(messageAttachments)
            }
            let assistantMessageID = messages[assistantMessageIndex].id
            forEachDelegate { delegate in
                delegate.conversation(self, didChangeMessage: assistantMessageID)
            }
        }
        if let isEndOfMessage, isEndOfMessage {
            assistantMessageIndex = -1
        }
        if let preparingFollowup, preparingFollowup {
            let assistantMessage = Message.createInitialAssistantMessage()
            assistantMessageIndex = messages.count
            messages.append(assistantMessage)
            forEachDelegate { delegate in
                delegate.conversation(self, didAddMessages: [assistantMessage.id])
            }
        }
    }

    private func checkForConversationEnd() async {
        if conversationEnded && !hasConversationEndMessage {
            hasConversationEndMessage = true
            do {
                var assistantMessageIndex = -1
                let stream = try await api.sendMessage(text: "", state: state, options: options, isConversationEnd: true)
                for try await event in stream {
                    switch event.type {
                    case "message":
                        guard let message = event.message else { continue }
                        updateWithMessageEvent(&assistantMessageIndex, message)
                    default:
                        debugLog("Unknown event type: \(event.type)")
                    }
                }
            } catch {
                debugLog("Cannot send conversation end, error: \(error)")
                // Not notifying the delegate, this is an internal operation that was not user-initiated
            }
        }
    }
}

enum ConversationError: Error {
    case stateNotAvailable
}

@available(*, deprecated, message: "Use ConversationCallbacks instead")
public protocol ConversationDelegate : AnyObject {
    func conversation(_ conversation: Conversation, didAddMessages messageIDs: [MessageID])
    func conversation(_ conversation: Conversation, didRemoveMessage messageID: MessageID)
    func conversation(_ conversation: Conversation, didChangeMessage messageID: MessageID)
    func conversation(_ conversation: Conversation, didHaveError error: Error?, withMessage message: String?)
    func conversation(_ conversation: Conversation, didTransfer transfer: ConversationTransfer)
    func conversation(_ conversation: Conversation, didChangeCanSend canSend: Bool)
    func conversation(_ conversation: Conversation, didChangeHumanAgentParticipation participation: HumanAgentParticipation?, previousValue: HumanAgentParticipation?)
    func conversation(_ conversation: Conversation, didChangeConversationEnded conversationEnded: Bool)
    func conversation(_ conversation: Conversation, didChangeCanSaveTranscript canSaveTranscript: Bool)
}

// Default no-op implementations of ConversationDelegate, so that clients can
// implement only the subset that they care about.
public extension ConversationDelegate {
    func conversation(_ conversation: Conversation, didAddMessages messageIDs: [MessageID]) {}
    func conversation(_ conversation: Conversation, didRemoveMessage messageID: MessageID) {}
    func conversation(_ conversation: Conversation, didChangeMessage messageID: MessageID) {}
    func conversation(_ conversation: Conversation, didHaveError error: Error?, withMessage message: String?) {}
    func conversation(_ conversation: Conversation, didTransfer transfer: ConversationTransfer) {}
    func conversation(_ conversation: Conversation, didChangeCanSend canSend: Bool) {}
    func conversation(_ conversation: Conversation, didChangeHumanAgentParticipation participation: HumanAgentParticipation?, previousValue: HumanAgentParticipation?) {}
    func conversation(_ conversation: Conversation, didChangeConversationEnded conversationEnded: Bool) {}
    func conversation(_ conversation: Conversation, didChangeCanSaveTranscript canSaveTranscript: Bool) {}
}

public typealias MessageID = UUID

// For now attachments are intentionally not public.
typealias MessageAttachment = APIEvent.Message.Attachment

@available(*, deprecated)
public struct Message: Identifiable {

    public let id: MessageID = UUID()

    public enum Role: String, Codable {
        case assistant = "assistant"
        case user = "user"
        case humanAgent = "human_agent"
        case status = "status"
    }
    public let role: Role

    public var content: String

    var attachments: [MessageAttachment] = []

    static private let typingIndicatorContent = "•••"

    public var isTypingIndicator: Bool {
        return content == Message.typingIndicatorContent
    }

    static func createInitialAssistantMessage() -> Message {
        return Message(role: .assistant, content: typingIndicatorContent)
    }

    static func createInitialHumanAgentMessage() -> Message {
        return Message(role: .humanAgent, content: typingIndicatorContent)
    }

    mutating func appendContent(piece: String) {
        if isTypingIndicator {
            content = piece
        } else {
            content += piece
        }
    }

    mutating func appendAttachments(_ attachments: [MessageAttachment]) {
        self.attachments.append(contentsOf: attachments)
    }

    public func attributedContent(font: UIFont? = nil, textColor: UIColor? = nil) -> AttributedString? {
        guard let contentData = content.data(using: .utf8) else { return nil }
        var attributedString: AttributedString
        do {
            attributedString = try AttributedString(
                markdown: contentData,
                options: AttributedString.MarkdownParsingOptions(
                    allowsExtendedAttributes: true,
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
        } catch {
            // Should not happen because we use returnPartiallyParsedIfPossible
            return nil
        }
        if let font {
            attributedString.font = font
        }
        if let textColor {
            attributedString.foregroundColor = textColor
        }
        return attributedString
    }
}

@available(*, deprecated)
public struct HumanAgentParticipation {
    var state: HumanAgentParticipationState = .waiting
    var queueSize: Int? = nil
    var agent: HumanAgent? = nil
}

@available(*, deprecated)
public enum HumanAgentParticipationState {
    case waiting
    case joined
    case left
}

@available(*, deprecated)
public struct HumanAgent {
    let displayName: String
}
