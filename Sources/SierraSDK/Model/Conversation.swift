// Copyright Sierra

import Foundation
import UIKit

public struct ConversationOptions {
    public var variables: [String: String]?
    public var secrets: [String: String]?

    public init() { }
}

/// Conversation encapsulates the UI state of a agent conversation
public class Conversation {
    public var messages: [Message] = []
    public var canSend: Bool = true {
        didSet {
            forEachDelegate { delegate in
                delegate.conversation(self, didChangeCanSend: self.canSend)
            }
        }
    }

    private let api: AgentAPI
    private let options: ConversationOptions?
    private var id: String?
    private var encryptionKey: String?
    private var delegates = NSHashTable<AnyObject>.weakObjects()

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

    public func messageWithID(_ id: MessageID) -> Message? {
        for message in messages {
            if message.id == id {
                return message
            }
        }
        return nil
    }

    func addDelegate(_ delegate: ConversationDelegate) {
        delegates.add(delegate)
    }

    func removeDelegate(_ delegate: ConversationDelegate) {
        delegates.remove(delegate)
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

    public func sendUserMessage(text: String) async {
        if !canSend {
            debugLog("Cannot send message, send already in progress")
            return
        }
        canSend = false
        let userMessage = Message(role: .user, content: text)
        messages.append(userMessage)

        var assistantMessage = Message(role: .assistant, content: "•••")
        var assistantMessageIndex = messages.count
        var assistantMessageID = assistantMessage.id
        messages.append(assistantMessage)
        forEachDelegate { delegate in
            delegate.conversation(self, didAddMessages: [userMessage.id, assistantMessageID])
        }

        var hasAssistantMessagePlaceholder = true
        do {
            let stream = try await api.sendMessage(text: text, conversationID: id, encryptionKey: encryptionKey, options: options)
            for try await update in stream {
                switch update {
                case .setConversationID(let chunk):
                    id = chunk.conversationID
                case .setEncryptionKey(let chunk):
                    encryptionKey = chunk.encryptionKey
                case .event(let event):
                    switch event {
                    case .message(let messageText, let isEndOfMessage, let preparingFollowup):
                        if let messageText {
                            if assistantMessageIndex == -1 {
                                assistantMessage = Message(role: .assistant, content: "")
                                assistantMessageIndex = messages.count
                                assistantMessageID = assistantMessage.id
                                messages.append(assistantMessage)
                                forEachDelegate { [assistantMessageID] delegate in
                                    delegate.conversation(self, didAddMessages: [assistantMessageID])
                                }
                            }
                            if hasAssistantMessagePlaceholder {
                                messages[assistantMessageIndex].content = messageText
                                hasAssistantMessagePlaceholder = false
                            } else {
                                messages[assistantMessageIndex].content += messageText
                            }
                            forEachDelegate { [assistantMessageID] delegate in
                                delegate.conversation(self, didChangeMessage: assistantMessageID)
                            }
                        }
                        if let isEndOfMessage, isEndOfMessage {
                            assistantMessageIndex = -1
                        }
                        if let preparingFollowup, preparingFollowup {
                            assistantMessage = Message(role: .assistant, content: "•••")
                            assistantMessageIndex = messages.count
                            assistantMessageID = assistantMessage.id
                            messages.append(assistantMessage)
                            forEachDelegate { [assistantMessageID] delegate in
                                delegate.conversation(self, didAddMessages: [assistantMessageID])
                            }
                            hasAssistantMessagePlaceholder = true
                        }
                    case .state:
                        // State updates are ignored, and will be removed in the public API.
                        break
                    case .transfer(let transfer):
                        let conversationTransfer = ConversationTransfer(
                            isSynchronous: transfer.isSynchronous ?? false,
                            data: Dictionary(uniqueKeysWithValues: transfer.data?.map{ ($0.key, $0.value) } ?? [])
                        )
                        forEachDelegate { delegate in
                            delegate.conversation(self, didTransfer: conversationTransfer)
                        }
                    case .error(let error):
                        debugLog("Agent error event: \(error)")
                        if hasAssistantMessagePlaceholder {
                            messages.remove(at: assistantMessageIndex)
                            forEachDelegate { [assistantMessageID] delegate in
                                delegate.conversation(self, didRemoveMessage: assistantMessageID)
                            }
                        }
                        forEachDelegate { delegate in
                            delegate.conversation(self, didHaveError: AgentChatError.serverError(error))
                        }
                    }
                }
            }
        } catch {
            debugLog("Cannot begin conversation, error: \(error)")
            if hasAssistantMessagePlaceholder {
                messages.remove(at: assistantMessageIndex)
                forEachDelegate { delegate in
                    delegate.conversation(self, didRemoveMessage: assistantMessageID)
                }
            }
            forEachDelegate { delegate in
                delegate.conversation(self, didHaveError: error)
            }
        }
        canSend = true
    }
}

public protocol ConversationDelegate : AnyObject {
    func conversation(_ conversation: Conversation, didAddMessages messageIDs: [MessageID])
    func conversation(_ conversation: Conversation, didRemoveMessage messageID: MessageID)
    func conversation(_ conversation: Conversation, didChangeMessage messageID: MessageID)
    func conversation(_ conversation: Conversation, didHaveError error: Error)
    func conversation(_ conversation: Conversation, didTransfer transfer: ConversationTransfer)
    func conversation(_ conversation: Conversation, didChangeCanSend canSend: Bool)
}

// Default no-op implementations of ConversationDelegate, so that clients can
// implement only the subset that they care about.
public extension ConversationDelegate {
    func conversation(_ conversation: Conversation, didAddMessages messageIDs: [MessageID]) {}
    func conversation(_ conversation: Conversation, didRemoveMessage messageID: MessageID) {}
    func conversation(_ conversation: Conversation, didChangeMessage messageID: MessageID) {}
    func conversation(_ conversation: Conversation, didHaveError error: Error) {}
    func conversation(_ conversation: Conversation, didTransfer transfer: ConversationTransfer) {}
    func conversation(_ conversation: Conversation, didChangeCanSend canSend: Bool) {}
}

public typealias MessageID = UUID

public struct Message: Identifiable {
    public let id: MessageID = UUID()

    public enum Role: String, Codable {
        case assistant = "assistant"
        case user = "user"
    }
    public let role: Role

    public var content: String

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

public struct ConversationTransfer {
    public let isSynchronous: Bool
    public let data: Dictionary<String, String>
}

func debugLog(_ message: String) {
    #if DEBUG
    debugPrint(message)
    #endif
}
