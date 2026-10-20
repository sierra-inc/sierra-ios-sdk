// Copyright Sierra

import UIKit

/// A single outer shadow around the composer. Dimensions are in points and default to zero.
/// Use the color's alpha channel to set opacity.
public struct ChatComposerShadow {
    public let color: UIColor
    /// Positive values move the shadow right, including in right-to-left layouts.
    public let offsetX: CGFloat?
    /// Positive values move the shadow down.
    public let offsetY: CGFloat?
    /// Negative values are clamped to zero by the renderer.
    public let blurRadius: CGFloat?
    /// Negative values shrink the shadow.
    public let spreadRadius: CGFloat?

    public init(color: UIColor, offsetX: CGFloat? = nil, offsetY: CGFloat? = nil,
                blurRadius: CGFloat? = nil, spreadRadius: CGFloat? = nil) {
        self.color = color
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.blurRadius = blurRadius
        self.spreadRadius = spreadRadius
    }

    package func toJSON() -> [String: Any] {
        var json: [String: Any] = [:]
        json["color"] = color.toHex()
        for (key, value) in [("offsetX", offsetX), ("offsetY", offsetY),
                             ("blurRadius", blurRadius), ("spreadRadius", spreadRadius)] {
            if let value = value, value.isFinite {
                json[key] = value
            }
        }
        return json
    }
}

/// Layout overrides for the message composer (the text input and its action buttons).
///
/// Every property is optional and overrides only its own default, so an omitted
/// `ChatComposerStyle` leaves the composer unchanged. Supplying `outerInsets` insets the
/// composer from the edges of the chat and moves the input background onto the composer itself,
/// so the inset gutter shows the chat background.
///
/// Composer colors stay on `ChatStyleColors`: `inputBackground`, `inputBorder`,
/// `inputFocusBorder`, `inputText`, and `inputPlaceholder`.
///
/// Insets are directional: `leading` and `trailing` follow the layout direction, so the same
/// configuration mirrors correctly in a right-to-left locale.
public struct ChatComposerStyle {
    /// Space between the edges of the chat and the composer, in points.
    public let outerInsets: NSDirectionalEdgeInsets?

    /// Space between the composer's edges and its content, in points. Replaces the default
    /// padding around the text input and its action buttons.
    public let contentInsets: NSDirectionalEdgeInsets?

    /// Minimum height of the composer, in points.
    public let minimumHeight: CGFloat?

    /// Number of lines the text input grows to before it starts scrolling.
    public let maximumLines: Int?

    /// Corner radius of the composer, in points.
    public let cornerRadius: CGFloat?

    /// Width of the composer's border, in points. Drawn in `ChatStyleColors.inputBorder`.
    public let borderWidth: CGFloat?

    /// Width and height of the send and upload buttons, in points.
    public let actionButtonSize: CGFloat?

    /// Width and height of the send and upload button glyphs, in points.
    /// The rendered size is clamped to the effective action button size.
    /// Does not resize SVGs that replace the complete send button.
    public let actionIconSize: CGFloat?

    /// Show the upload/send separator. Defaults to true. When false, the default gap is 24 points.
    /// Use actionButtonSpacing to override the gap with or without the divider.
    public let showActionDivider: Bool?

    /// Outer shadow around the composer. Use outerInsets to leave room for it.
    public let shadow: ChatComposerShadow?

    /// Horizontal gap between the upload and send button edges, in points, with the optional
    /// divider centered in the gap. Omit to keep default spacing. Negative values clamp to zero.
    public let actionButtonSpacing: CGFloat?

    public init(outerInsets: NSDirectionalEdgeInsets? = nil,
                contentInsets: NSDirectionalEdgeInsets? = nil,
                minimumHeight: CGFloat? = nil,
                maximumLines: Int? = nil,
                cornerRadius: CGFloat? = nil,
                borderWidth: CGFloat? = nil,
                actionButtonSize: CGFloat? = nil,
                actionIconSize: CGFloat? = nil,
                showActionDivider: Bool? = nil,
                shadow: ChatComposerShadow? = nil,
                actionButtonSpacing: CGFloat? = nil) {
        self.outerInsets = outerInsets
        self.contentInsets = contentInsets
        self.minimumHeight = minimumHeight
        self.maximumLines = maximumLines
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.actionButtonSize = actionButtonSize
        self.actionIconSize = actionIconSize
        self.showActionDivider = showActionDivider
        self.shadow = shadow
        self.actionButtonSpacing = actionButtonSpacing
    }

    // `leading` and `trailing` serialize as the logical `start` and `end` keys the embed expects.
    private static func insetsJSON(_ insets: NSDirectionalEdgeInsets) -> [String: CGFloat] {
        return [
            "top": insets.top,
            "start": insets.leading,
            "bottom": insets.bottom,
            "end": insets.trailing,
        ].filter { $0.value.isFinite }
    }

    package func toJSON() -> [String: Any] {
        var json: [String: Any] = [:]
        if let outerInsets = outerInsets {
            let insets = Self.insetsJSON(outerInsets)
            if !insets.isEmpty {
                json["outerInsets"] = insets
            }
        }
        if let contentInsets = contentInsets {
            let insets = Self.insetsJSON(contentInsets)
            if !insets.isEmpty {
                json["contentInsets"] = insets
            }
        }
        if let minimumHeight = minimumHeight, minimumHeight.isFinite {
            json["minimumHeight"] = minimumHeight
        }
        if let maximumLines = maximumLines {
            json["maximumLines"] = maximumLines
        }
        if let cornerRadius = cornerRadius, cornerRadius.isFinite {
            json["cornerRadius"] = cornerRadius
        }
        if let borderWidth = borderWidth, borderWidth.isFinite {
            json["borderWidth"] = borderWidth
        }
        if let actionButtonSize = actionButtonSize, actionButtonSize.isFinite {
            json["actionButtonSize"] = actionButtonSize
        }
        if let actionIconSize = actionIconSize, actionIconSize.isFinite {
            json["actionIconSize"] = actionIconSize
        }
        json["showActionDivider"] = showActionDivider
        json["shadow"] = shadow?.toJSON()
        if let actionButtonSpacing = actionButtonSpacing, actionButtonSpacing.isFinite {
            json["actionButtonSpacing"] = actionButtonSpacing
        }
        return json
    }

    /// The value of the `composerStyle` query parameter, or nil when nothing is configured and
    /// the parameter should be omitted so older embeds keep their defaults.
    package func toJSONString() -> String? {
        let json = toJSON()
        if json.isEmpty {
            return nil
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: [])
            return String(data: data, encoding: .utf8)
        } catch {
            debugLog("Error serializing composer style to JSON: \(error)")
            return nil
        }
    }
}
