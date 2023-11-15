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

    public init(backgroundColor: UIColor = .systemBackground,
                assistantBubble: UIColor = .systemGray6,
                assistantBubbleText: UIColor = .label,
                userBubble: UIColor = .systemBlue,
                userBubbleText: UIColor = .white,
                disclosureText: UIColor = .secondaryLabel,
                errorText: UIColor = .systemRed) {
        self.backgroundColor = backgroundColor
        self.assistantBubble = assistantBubble
        self.assistantBubbleText = assistantBubbleText
        self.userBubble = userBubble
        self.userBubbleText = userBubbleText
        self.disclosureText = disclosureText
        self.errorText = errorText
    }
}

public let DEFAULT_CHAT_STYLE_COLORS = ChatStyleColors()

public struct ChatStyleLayout {
    /// Radius of the bubble. Very large or very small values may not work with buble tails, in which
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

    /// Maxium fraction of the container that the bubble takes up horizontally (0 to disable)
    let bubbleMaxWidthFraction: CGFloat

    /// Maximum absolute width of the bubble (0 to disable)
    let bubbleMaxWidthAbsolute: CGFloat

    public init(bubbleRadius: CGFloat = 20, 
                bubbleTail: Bool = true,
                bubbleXPadding: CGFloat = 14,
                bubbleYPadding: CGFloat = 9,
                bubbleXMargin: CGFloat = 0,
                bubbleYMargin: CGFloat = 6,
                bubbleMaxWidthFraction: CGFloat = 0.85,
                bubbleMaxWidthAbsolute: CGFloat = 600) {
        self.bubbleRadius = bubbleRadius
        self.bubbleTail = bubbleTail
        self.bubbleXPadding = bubbleXPadding
        self.bubbleYPadding = bubbleYPadding
        self.bubbleXMargin = bubbleXMargin
        self.bubbleYMargin = bubbleYMargin
        self.bubbleMaxWidthFraction = bubbleMaxWidthFraction
        self.bubbleMaxWidthAbsolute = bubbleMaxWidthAbsolute
    }
}

public let DEFAULT_CHAT_STYLE_LAYOUT = ChatStyleLayout()
