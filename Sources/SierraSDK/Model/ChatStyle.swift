// Copyright Sierra

import UIKit

public struct ChatStyle {
    public let colors: ChatStyleColors
    public let layout: ChatStyleLayout
}

public let DEFAULT_CHAT_STYLE = ChatStyle(colors: DEFAULT_CHAT_STYLE_COLORS, layout: DEFAULT_CHAT_STYLE_LAYOUT)

public struct ChatStyleColors {
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
}

public let DEFAULT_CHAT_STYLE_COLORS = ChatStyleColors(
    assistantBubble: .systemGray6,
    assistantBubbleText: .label,
    userBubble: .systemBlue,
    userBubbleText: .white,
    disclosureText: .secondaryLabel
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
}

public let DEFAULT_CHAT_STYLE_LAYOUT = ChatStyleLayout(
    bubbleXPadding: 12,
    bubbleYPadding: 11,
    bubbleXMargin: 16,
    bubbleYMargin: 8,
    bubbleMaxWidthFraction: 0.85,
    bubbleMaxWidthAbsolute: 600
)
