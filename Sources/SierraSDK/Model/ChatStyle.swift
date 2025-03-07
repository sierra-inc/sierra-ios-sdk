// Copyright Sierra

import UIKit

public struct ChatStyle {
    public let colors: ChatStyleColors

    @available(*, deprecated)
    public let layout: ChatStyleLayout

    public init(colors: ChatStyleColors) {
        self.colors = colors
        self.layout = DEFAULT_CHAT_STYLE_LAYOUT
    }

    @available(*, deprecated)
    public init(colors: ChatStyleColors, layout: ChatStyleLayout) {
        self.colors = colors
        self.layout = layout
    }
}

public let DEFAULT_CHAT_STYLE = ChatStyle(colors: DEFAULT_CHAT_STYLE_COLORS, layout: DEFAULT_CHAT_STYLE_LAYOUT)

public struct ChatStyleColors {
    /// The background color for the chat view.
    public let backgroundColor: UIColor
    
    /// The color of the user input text and default color for assistant messages.
    public let text: UIColor?

    /// The color of the border separating the user input from the chat messages.
    public let border: UIColor?

    /// The color of the navigation bar of the chat view
    public let titleBar: UIColor

    /// The color of the text in the navigation bar of the chat view
    public let titleBarText: UIColor

    /// The background color of the chat bubble for messages from the AI assistant.
    public let assistantBubble: UIColor

    /// The color of the text in chat bubbles for messages from the AI assistant.
    public let assistantBubbleText: UIColor

    /// The background color of the chat bubble for messages from the user.
    public let userBubble: UIColor

    /// The color of the text in chat bubbles for messages from the user.
    public let userBubbleText: UIColor

    /// The color of the optional disclosure text that appears before any chat messages.
    @available(*, deprecated)
    public let disclosureText: UIColor

    /// The color that error messages are displayed in
    @available(*, deprecated)
    public let errorText: UIColor

    /// The color that the waiting message is displayed in
    @available(*, deprecated)
    public let statusText: UIColor
    
    /// Override the tint color of the chat view (it will normally inherit the application's)
    @available(*, deprecated)
    public let tintColor: UIColor?

    public init(backgroundColor: UIColor = .systemBackground,
                text: UIColor? = .label,
                border: UIColor? = nil,
                assistantBubble: UIColor = .systemGray6,
                assistantBubbleText: UIColor = .label,
                userBubble: UIColor = .systemBlue,
                userBubbleText: UIColor = .white,
                disclosureText: UIColor = .secondaryLabel,
                errorText: UIColor = .systemRed,
                humanAgentTransferWaitingText: UIColor = .secondaryLabel,
                titleBar: UIColor = .systemBackground,
                titleBarText: UIColor = .label,
                tintColor: UIColor? = nil) {
        self.backgroundColor = backgroundColor
        self.text = text
        self.border = border
        self.assistantBubble = assistantBubble
        self.assistantBubbleText = assistantBubbleText
        self.userBubble = userBubble
        self.userBubbleText = userBubbleText
        self.disclosureText = disclosureText
        self.errorText = errorText
        self.statusText = humanAgentTransferWaitingText
        self.titleBar = titleBar
        self.titleBarText = titleBarText
        self.tintColor = tintColor
    }
}

public let DEFAULT_CHAT_STYLE_COLORS = ChatStyleColors()

@available(*, deprecated)
public struct ChatStyleLayout {
    /// Radius of the bubble. Very large or very small values may not work with bubble tails, in which
    /// case they should be disabled (via the `bubbleTail` property).
    let bubbleRadius: CGFloat

    /// Whether the bubbles have a "tail" that anchors them to the edges of the chat screen.
    let bubbleTail: Bool

    /// Padding inside the bubble, between the background and the text.
    let bubbleXPadding: CGFloat
    let bubbleYPadding: CGFloat

    /// Margin between the edges (x) and adjacent bubbles (y).
    let bubbleXMargin: CGFloat
    let bubbleYMargin: CGFloat

    /// Maximum fraction of the container that the bubble takes up horizontally (0 to disable)
    let bubbleMaxWidthFraction: CGFloat

    /// Maximum absolute width of the bubble (0 to disable)
    let bubbleMaxWidthAbsolute: CGFloat

    /// Radius of the bubble that's used when waiting for a human agent to join the conversation.
    let humanAgentWaitingBubbleRadius: CGFloat

    public init(bubbleRadius: CGFloat = 20,
                bubbleTail: Bool = true,
                bubbleXPadding: CGFloat = 14,
                bubbleYPadding: CGFloat = 9,
                bubbleXMargin: CGFloat = 0,
                bubbleYMargin: CGFloat = 6,
                bubbleMaxWidthFraction: CGFloat = 0.85,
                bubbleMaxWidthAbsolute: CGFloat = 600,
                humanAgentWaitingBubbleRadius: CGFloat = 12) {
        self.bubbleRadius = bubbleRadius
        self.bubbleTail = bubbleTail
        self.bubbleXPadding = bubbleXPadding
        self.bubbleYPadding = bubbleYPadding
        self.bubbleXMargin = bubbleXMargin
        self.bubbleYMargin = bubbleYMargin
        self.bubbleMaxWidthFraction = bubbleMaxWidthFraction
        self.bubbleMaxWidthAbsolute = bubbleMaxWidthAbsolute
        self.humanAgentWaitingBubbleRadius = humanAgentWaitingBubbleRadius
    }
}

public let DEFAULT_CHAT_STYLE_LAYOUT = ChatStyleLayout()

extension UIColor {
    func toHex() -> String? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        // https://stackoverflow.com/a/22334560
        let multiplier = CGFloat(255.999999)

        guard self.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        
        // Clamp values to be below 1.0
        red = min(red, 1.0)
        green = min(green, 1.0)
        blue = min(blue, 1.0)

        if alpha == 1.0 {
            return String(
                format: "#%02lX%02lX%02lX",
                Int(red * multiplier),
                Int(green * multiplier),
                Int(blue * multiplier)
            )
        }
        else {
            return String(
                format: "#%02lX%02lX%02lX%02lX",
                Int(red * multiplier),
                Int(green * multiplier),
                Int(blue * multiplier),
                Int(alpha * multiplier)
            )
        }
    }
}

extension ChatStyleColors {
    // Match the ChatStyle.colors type from ui/chat/chat.tsx.
    func toJSON() -> [String: String?] {
        var json = [
            "background": backgroundColor.toHex(),
            "titleBar": titleBar.toHex(),
            "titleBarText": titleBarText.toHex(),
            "assistantBubble": assistantBubble.toHex(),
            "assistantBubbleText": assistantBubbleText.toHex(),
            "userBubble": userBubble.toHex(),
            "userBubbleText": userBubbleText.toHex(),
        ]
        if let text = text {
            json["text"] = text.toHex()
        }
        if let border = border {
            json["border"] = border.toHex()
        }
        return json
    }
}

extension ChatStyle {
    func toJSON() -> [String: Any] {
        return [
            "colors": colors.toJSON(),
        ]
    }

    func toJSONString() -> String {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: toJSON(), options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            } else {
                debugLog("Error: Unable to convert JSON data to string.")
            } 
        } catch {
            debugLog("Error serializing object to JSON: \(error)")
        }
        return ""
    }

}
