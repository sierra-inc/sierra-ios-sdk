// Copyright Sierra

import UIKit

/// Optional layout for an ended conversation. Omitted properties keep their defaults.
public struct ChatConversationEndedStyle {
    public enum MessageAlignment: String {
        case start, center, end
    }

    /// Logical alignment of the ended message.
    public let messageAlignment: MessageAlignment?
    /// Keep the composer background, border, sizing, and insets. Defaults to true.
    public let showComposerContainer: Bool?
    /// Space above the new-chat action, in points. Clamped to 0-320; zero removes it.
    public let actionSpacing: CGFloat?
    /// Style of this conversation's new-chat button, separate from the list button.
    public let newChatButtonStyle: ChatButtonStyle?
    /// Show the conversation disclosure after the conversation ends. Defaults to true.
    public let showDisclosure: Bool?

    public init(messageAlignment: MessageAlignment? = nil,
                showComposerContainer: Bool? = nil,
                actionSpacing: CGFloat? = nil,
                newChatButtonStyle: ChatButtonStyle? = nil,
                showDisclosure: Bool? = nil) {
        self.messageAlignment = messageAlignment
        self.showComposerContainer = showComposerContainer
        self.actionSpacing = actionSpacing
        self.newChatButtonStyle = newChatButtonStyle
        self.showDisclosure = showDisclosure
    }

    package func toJSONString() -> String? {
        var json: [String: Any] = [:]
        if let messageAlignment { json["messageAlignment"] = messageAlignment.rawValue }
        if let showDisclosure { json["showDisclosure"] = showDisclosure }
        if let showComposerContainer { json["showComposerContainer"] = showComposerContainer }
        if let actionSpacing, actionSpacing.isFinite { json["actionSpacing"] = actionSpacing }
        if let newChatButtonStyle {
            let button = newChatButtonStyle.toJSON()
            if !button.isEmpty { json["newChatButtonStyle"] = button }
        }
        if json.isEmpty { return nil }
        do {
            let data = try JSONSerialization.data(withJSONObject: json)
            return String(data: data, encoding: .utf8)
        } catch {
            debugLog("Error serializing ended conversation style: \(error)")
            return nil
        }
    }
}
