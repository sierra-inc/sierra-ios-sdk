// Copyright Sierra

import Foundation

/// An optional text-message action above the composer.
public struct MessageInputPresetAction {
    public struct ClientEvent {
        public struct Message {
            public var content: String
            public init(content: String) { self.content = content }
        }
        public var message: Message
        public init(message: Message) { self.message = message }
    }
    public var label: String
    public var clientEvent: ClientEvent
    public var showAfterAgentMessageCount: Int?
    public var style: ChatButtonStyle?

    public init(label: String, clientEvent: ClientEvent, showAfterAgentMessageCount: Int? = nil,
                style: ChatButtonStyle? = nil) {
        self.label = label
        self.clientEvent = clientEvent
        self.showAfterAgentMessageCount = showAfterAgentMessageCount
        self.style = style
    }

    package func toJSONString() -> String? {
        var json: [String: Any] = [
            "label": label,
            "clientEvent": ["type": "message", "message": ["content": clientEvent.message.content]],
        ]
        json["showAfterAgentMessageCount"] = showAfterAgentMessageCount
        json["style"] = style?.toJSON()
        do {
            return String(data: try JSONSerialization.data(withJSONObject: json), encoding: .utf8)
        } catch {
            debugLog("Error serializing message input preset action: \(error)")
            return nil
        }
    }
}
