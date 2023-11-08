// Copyright Sierra

import UIKit

public struct ChatStyle {
    public let colors: ChatStyleColors
    public let layout: ChatStyleLayout

    public init(colors: ChatStyleColors, layout: ChatStyleLayout) {
        self.colors = colors
        self.layout = layout
    }
}

public let DEFAULT_CHAT_STYLE = ChatStyle(colors: DEFAULT_CHAT_STYLE_COLORS, layout: DEFAULT_CHAT_STYLE_LAYOUT)

public struct ChatStyleColors {
    /// The background color for the chat view.
    let backgroundColor: UIColor

    /// The background color of the chat bubble for messages from the AI assistant.
    let assistantBubble: UIColor

    /// The color of the text in chat bubbles for messages from the AI assistant.
    let assistantBubbleText: UIColor

    /// The background color of the chat bubble for messages from the user.
    let userBubble: UIColor

    /// The color of the text in chat bubbles for messages from the user.
    let userBubbleText: UIColor

    /// The color of the optional diclosure text that appears before any chat messages.
    let disclosureText: UIColor

    /// The color that error messages are displayed in
    let errorText: UIColor

    public init(backgroundColor: UIColor, assistantBubble: UIColor, assistantBubbleText: UIColor, userBubble: UIColor, userBubbleText: UIColor, disclosureText: UIColor, errorText: UIColor) {
        self.backgroundColor = backgroundColor
        self.assistantBubble = assistantBubble
        self.assistantBubbleText = assistantBubbleText
        self.userBubble = userBubble
        self.userBubbleText = userBubbleText
        self.disclosureText = disclosureText
        self.errorText = errorText
    }
}

public let DEFAULT_CHAT_STYLE_COLORS = ChatStyleColors(
    backgroundColor: .systemBackground,
    assistantBubble: .systemGray6,
    assistantBubbleText: .label,
    userBubble: .systemBlue,
    userBubbleText: .white,
    disclosureText: .secondaryLabel,
    errorText: .systemRed
)

public struct ChatStyleLayout {
    /// Padding inside the bubble, between the background and the text.
    let bubbleXPadding: CGFloat
    let bubbleYPadding: CGFloat

    /// Margin between the edges (x) and adjacent bubbles (y).
    let bubbleXMargin: CGFloat
    let bubbleYMargin: CGFloat

    /// Maxium fraction of the container that the bubble takes up horizontally (0 to disable)
    let bubbleMaxWidthFraction: CGFloat

    /// Maximum absolute width of the bubble (0 to disable)
    let bubbleMaxWidthAbsolute: CGFloat

    public init(bubbleXPadding: CGFloat, bubbleYPadding: CGFloat, bubbleXMargin: CGFloat, bubbleYMargin: CGFloat, bubbleMaxWidthFraction: CGFloat, bubbleMaxWidthAbsolute: CGFloat) {
        self.bubbleXPadding = bubbleXPadding
        self.bubbleYPadding = bubbleYPadding
        self.bubbleXMargin = bubbleXMargin
        self.bubbleYMargin = bubbleYMargin
        self.bubbleMaxWidthFraction = bubbleMaxWidthFraction
        self.bubbleMaxWidthAbsolute = bubbleMaxWidthAbsolute
    }
}

public let DEFAULT_CHAT_STYLE_LAYOUT = ChatStyleLayout(
    bubbleXPadding: 12,
    bubbleYPadding: 11,
    bubbleXMargin: 0,
    bubbleYMargin: 8,
    bubbleMaxWidthFraction: 0.85,
    bubbleMaxWidthAbsolute: 600
)
