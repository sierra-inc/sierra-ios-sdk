// Copyright Sierra

import UIKit

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

    public init(outerInsets: NSDirectionalEdgeInsets? = nil,
                contentInsets: NSDirectionalEdgeInsets? = nil,
                minimumHeight: CGFloat? = nil,
                maximumLines: Int? = nil,
                cornerRadius: CGFloat? = nil,
                borderWidth: CGFloat? = nil,
                actionButtonSize: CGFloat? = nil) {
        self.outerInsets = outerInsets
        self.contentInsets = contentInsets
        self.minimumHeight = minimumHeight
        self.maximumLines = maximumLines
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.actionButtonSize = actionButtonSize
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
