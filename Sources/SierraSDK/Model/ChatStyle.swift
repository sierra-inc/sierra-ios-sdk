// Copyright Sierra

import UIKit

public struct ChatStyle {
    public let colors: ChatStyleColors
    public let typography: ChatStyleTypography?

    @available(*, deprecated)
    public let layout: ChatStyleLayout

    public init(colors: ChatStyleColors, typography: ChatStyleTypography? = nil) {
        self.colors = colors
        self.typography = typography
        self.layout = DEFAULT_CHAT_STYLE_LAYOUT
    }

    @available(*, deprecated)
    public init(colors: ChatStyleColors, layout: ChatStyleLayout) {
        self.colors = colors
        self.typography = nil
        self.layout = layout
    }
}

public let DEFAULT_CHAT_STYLE = ChatStyle(colors: DEFAULT_CHAT_STYLE_COLORS, layout: DEFAULT_CHAT_STYLE_LAYOUT)

/// Styling overrides for hyperlinks within a region's text (e.g. links in the
/// disclosure or in chat bubbles).
public struct ChatLinkStyle {
    /// The font weight (or boldness) of hyperlinks.
    public let fontWeight: Int?

    /// The font style of hyperlinks: "normal" or "italic".
    public let fontStyle: String?

    /// Underline behavior for hyperlinks: "always", "hover", or "none". "hover"
    /// (the default) underlines on hover only; on touch devices this effectively
    /// means no underline at rest.
    public let underline: String?

    public init(fontWeight: Int? = nil, fontStyle: String? = nil, underline: String? = nil) {
        self.fontWeight = fontWeight
        self.fontStyle = fontStyle
        self.underline = underline
    }

    package func toJSON() -> [String: Any] {
        var json: [String: Any] = [:]
        if let fontWeight = fontWeight {
            json["fontWeight"] = fontWeight
        }
        if let fontStyle = fontStyle {
            json["fontStyle"] = fontStyle
        }
        if let underline = underline {
            json["underline"] = underline
        }
        return json
    }
}

/// Typography overrides for a specific region of the chat UI (e.g. user bubbles,
/// agent bubbles, the title bar, or the disclosure text).
public struct ChatTextStyle {
    /// The font size, in pixels.
    public let fontSize: Int?

    /// The font weight, or boldness.
    public let fontWeight: Int?

    /// The line height, as a unitless multiplier of the font size.
    public let lineHeight: Double?

    /// The horizontal spacing between text characters, in em units.
    public let letterSpacing: Double?

    /// The font family, a comma-separated list of font names. Overrides the
    /// global `fontFamily` for this region.
    public let fontFamily: String?

    /// The font style: "normal" or "italic".
    public let fontStyle: String?

    /// Styling overrides for hyperlinks within this region's text.
    public let link: ChatLinkStyle?

    public init(fontSize: Int? = nil,
                fontWeight: Int? = nil,
                lineHeight: Double? = nil,
                letterSpacing: Double? = nil,
                fontFamily: String? = nil,
                fontStyle: String? = nil,
                link: ChatLinkStyle? = nil) {
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.lineHeight = lineHeight
        self.letterSpacing = letterSpacing
        self.fontFamily = fontFamily
        self.fontStyle = fontStyle
        self.link = link
    }

    package func toJSON() -> [String: Any] {
        var json: [String: Any] = [:]
        if let fontSize = fontSize {
            json["fontSize"] = fontSize
        }
        if let fontWeight = fontWeight {
            json["fontWeight"] = fontWeight
        }
        if let lineHeight = lineHeight {
            json["lineHeight"] = lineHeight
        }
        if let letterSpacing = letterSpacing {
            json["letterSpacing"] = letterSpacing
        }
        if let fontFamily = fontFamily {
            json["fontFamily"] = fontFamily
        }
        if let fontStyle = fontStyle {
            json["fontStyle"] = fontStyle
        }
        if let link = link {
            json["link"] = link.toJSON()
        }
        return json
    }
}

/// Typography settings for chat UI. When useConfiguredStyle is true in AgentChatControllerOptions,
/// these settings are overridden by server-configured typography.
public struct ChatStyleTypography {
    /// The font family, a comma-separated list of font names.
    /// Note: Data for custom fonts must be provided in the `customFonts` property.
    public let fontFamily: String?

    /// The font size, in pixels.
    public let fontSize: Int?

    /// The font weight, or boldness.
    @available(*, deprecated, message: "Has no effect. Use per-region typography (userBubble/assistantBubble/titleBar/disclosure) instead.")
    public let fontWeight: Int?

    /// The line height, as a unitless multiplier of the font size.
    @available(*, deprecated, message: "Has no effect. Use per-region typography (userBubble/assistantBubble/titleBar/disclosure) instead.")
    public let lineHeight: Double?

    /// The horizontal spacing between text characters, in em units.
    @available(*, deprecated, message: "Has no effect. Use per-region typography (userBubble/assistantBubble/titleBar/disclosure) instead.")
    public let letterSpacing: Double?

    /// Typography overrides for chat bubbles from the user.
    public let userBubble: ChatTextStyle?

    /// Typography overrides for chat bubbles from the AI assistant.
    public let assistantBubble: ChatTextStyle?

    /// Typography overrides for the title bar text.
    public let titleBar: ChatTextStyle?

    /// Typography overrides for the disclosure (disclaimer) text.
    public let disclosure: ChatTextStyle?

    /// Typography overrides for the message input text.
    public let messageInput: ChatTextStyle?

    /// Custom fonts that are included in the app bundle.
    public let customFonts: [CustomFont]?

    public init(fontFamily: String? = nil,
                fontSize: Int? = nil,
                fontWeight: Int? = nil,
                lineHeight: Double? = nil,
                letterSpacing: Double? = nil,
                userBubble: ChatTextStyle? = nil,
                assistantBubble: ChatTextStyle? = nil,
                titleBar: ChatTextStyle? = nil,
                disclosure: ChatTextStyle? = nil,
                messageInput: ChatTextStyle? = nil,
                customFonts: [CustomFont]? = nil) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.lineHeight = lineHeight
        self.letterSpacing = letterSpacing
        self.userBubble = userBubble
        self.assistantBubble = assistantBubble
        self.titleBar = titleBar
        self.disclosure = disclosure
        self.messageInput = messageInput
        self.customFonts = customFonts
    }
}

public struct CustomFont {
    /// The font family name to use. Should match the name given in the
    /// `fontFamily` property of the `ChatStyleTypography` struct.
    public let fontFamily: String
    /// The font type (ttf, otf, woff, woff2)
    public let fontType: FontType
    /// The font weight (normal, bold, 100, 400, 700)
    public let fontWeight: String
    /// The font style (normal, italic, oblique)
    public let fontStyle: String
    /// The URL of the font resource to load. Usually obtained from the app bundle.
    public let dataURL: URL

    public init(fontFamily: String,
                fontType: FontType,
                fontWeight: String = "normal",
                fontStyle: String = "normal",
                dataURL: URL) {
        self.fontFamily = fontFamily
        self.fontType = fontType
        self.fontWeight = fontWeight
        self.fontStyle = fontStyle
        self.dataURL = dataURL
    }
}

public enum FontType: String {
    case ttf = "ttf"
    case otf = "otf"
    case woff = "woff"
    case woff2 = "woff2"

    /// The MIME type for this font format
    var mimeType: String {
        switch self {
        case .ttf:
            return "font/ttf"
        case .otf:
            return "font/otf"
        case .woff:
            return "font/woff"
        case .woff2:
            return "font/woff2"
        }
    }
}

/// Color settings for chat UI. When useConfiguredStyle is true in AgentChatControllerOptions, these
/// settings are overridden by server-configured colors.
public struct ChatStyleColors {
    /// The background color for the chat view.
    public let backgroundColor: UIColor

    /// The color of the user input text and default color for assistant messages.
    public let text: UIColor?

    /// The color of the border separating the user input from the chat messages.
    public let border: UIColor?

    /// The background color of the message input area (the region below the divider
    /// that contains the text input). When nil, falls back to `backgroundColor`.
    public let inputBackground: UIColor?

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

    /// The color of the new-chat button. When the button appears as a flat button in the chat
    /// footer, this controls the text color. When the button appears as a filled button in the
    /// conversation list, this controls the background color; in that case `newChatButtonText`
    /// controls the text color. When nil, falls back to `userBubble`.
    public let newChatButton: UIColor?

    /// The text color of the new-chat button in the conversation list. When nil, falls back to
    /// `userBubbleText`.
    public let newChatButtonText: UIColor?

    /// The color of the placeholder text shown in the message input, also used for the send
    /// button arrow when the input is empty. When nil, falls back to `text` at reduced opacity;
    /// when set, it is used at full opacity.
    public let inputPlaceholder: UIColor?

    /// The color of the file upload (attachment) button icon in the chat input. When nil,
    /// falls back to `userBubble`. Override this when `userBubble` does not contrast well
    /// with `backgroundColor` in light or dark mode.
    public let uploadButtonIcon: UIColor?

    /// The color of the disclosure (disclaimer) text shown before any chat messages.
    /// When nil, the default disclosure text color is used.
    public let disclosure: UIColor?

    /// The color of links within the disclosure (disclaimer) text.
    public let disclosureLink: UIColor?

    /// The color of links in chat bubbles for messages from the user.
    public let userBubbleLink: UIColor?

    /// The color of links in chat bubbles for messages from the AI assistant.
    public let assistantBubbleLink: UIColor?

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
                border: UIColor? = .separator,
                inputBackground: UIColor? = nil,
                assistantBubble: UIColor = .systemGray6,
                assistantBubbleText: UIColor = .label,
                userBubble: UIColor = .systemBlue,
                userBubbleText: UIColor = .white,
                newChatButton: UIColor? = .systemBlue,
                newChatButtonText: UIColor? = nil,
                inputPlaceholder: UIColor? = nil,
                uploadButtonIcon: UIColor? = nil,
                disclosure: UIColor? = nil,
                disclosureLink: UIColor? = nil,
                userBubbleLink: UIColor? = nil,
                assistantBubbleLink: UIColor? = nil,
                disclosureText: UIColor = .secondaryLabel,
                errorText: UIColor = .systemRed,
                humanAgentTransferWaitingText: UIColor = .secondaryLabel,
                titleBar: UIColor = .systemBackground,
                titleBarText: UIColor = .label,
                tintColor: UIColor? = nil) {
        self.backgroundColor = backgroundColor
        self.text = text
        self.border = border
        self.inputBackground = inputBackground
        self.assistantBubble = assistantBubble
        self.assistantBubbleText = assistantBubbleText
        self.userBubble = userBubble
        self.userBubbleText = userBubbleText
        self.newChatButton = newChatButton
        self.newChatButtonText = newChatButtonText
        self.inputPlaceholder = inputPlaceholder
        self.uploadButtonIcon = uploadButtonIcon
        self.disclosure = disclosure
        self.disclosureLink = disclosureLink
        self.userBubbleLink = userBubbleLink
        self.assistantBubbleLink = assistantBubbleLink
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
    package func toHex() -> String? {
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
    // Match the web embed's ChatStyle.colors shape.
    package func toJSON() -> [String: String?] {
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
        if let inputBackground = inputBackground {
            json["inputBackground"] = inputBackground.toHex()
        }
        if let newChatButton = newChatButton {
            json["newChatButton"] = newChatButton.toHex()
        }
        if let newChatButtonText = newChatButtonText {
            json["newChatButtonText"] = newChatButtonText.toHex()
        }
        if let inputPlaceholder = inputPlaceholder {
            json["inputPlaceholder"] = inputPlaceholder.toHex()
        }
        if let uploadButtonIcon = uploadButtonIcon {
            json["uploadButtonIcon"] = uploadButtonIcon.toHex()
        }
        if let disclosure = disclosure {
            json["disclosure"] = disclosure.toHex()
        }
        if let disclosureLink = disclosureLink {
            json["disclosureLink"] = disclosureLink.toHex()
        }
        if let userBubbleLink = userBubbleLink {
            json["userBubbleLink"] = userBubbleLink.toHex()
        }
        if let assistantBubbleLink = assistantBubbleLink {
            json["assistantBubbleLink"] = assistantBubbleLink.toHex()
        }
        return json
    }
}

extension ChatStyleTypography {
    package func toJSON() -> [String: Any?] {
        var json: [String: Any?] = [:]
        if let fontFamily = fontFamily {
            json["fontFamily"] = fontFamily
        }
        if let fontSize = fontSize {
            json["fontSize"] = fontSize
            // Set all responsive font sizes
            json["fontSize900"] = fontSize
            json["fontSize750"] = fontSize
            json["fontSize500"] = fontSize
        }
        // The deprecated top-level fontWeight/lineHeight/letterSpacing are
        // intentionally not serialized -- there is no global weight/line-height/
        // letter-spacing. Use the per-region overrides below instead.
        if let userBubble = userBubble {
            json["userBubble"] = userBubble.toJSON()
        }
        if let assistantBubble = assistantBubble {
            json["assistantBubble"] = assistantBubble.toJSON()
        }
        if let titleBar = titleBar {
            json["titleBar"] = titleBar.toJSON()
        }
        if let disclosure = disclosure {
            json["disclosure"] = disclosure.toJSON()
        }
        if let messageInput = messageInput {
            json["messageInput"] = messageInput.toJSON()
        }
        return json
    }
}

extension ChatStyle {
    package func toJSON() -> [String: Any] {
        var json: [String: Any] = [
            "colors": colors.toJSON(),
        ]
        // Match the web embed's ChatStyle shape: serialize typography as "type".
        if let typography = typography {
            json["type"] = typography.toJSON()
        }
        return json
    }

    package func toJSONString() -> String {
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
