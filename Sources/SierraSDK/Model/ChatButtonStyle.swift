// Copyright Sierra

import UIKit

/// Optional overrides for a chat button. Dimensions use CSS strings with px, em, rem, or % units.
/// Border width does not support percentages.
public struct ChatButtonStyle {
    public enum Alignment: String { case start, center, end }

    public var alignment: Alignment?
    public var backgroundColor: UIColor?
    public var textColor: UIColor?
    public var borderColor: UIColor?
    public var borderWidth: String?
    public var height: String?
    public var width: String?
    public var padding: String?
    public var borderRadius: String?
    /// Decorative SVG before the label. Sanitized by the shared renderer.
    public var iconSVG: String?

    public init(alignment: Alignment? = nil, backgroundColor: UIColor? = nil,
                textColor: UIColor? = nil, borderColor: UIColor? = nil,
                borderWidth: String? = nil, height: String? = nil, width: String? = nil,
                padding: String? = nil, borderRadius: String? = nil, iconSVG: String? = nil) {
        self.alignment = alignment
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.height = height
        self.width = width
        self.padding = padding
        self.borderRadius = borderRadius
        self.iconSVG = iconSVG
    }

    package func toJSON() -> [String: Any] {
        var json: [String: Any] = [:]
        json["alignment"] = alignment?.rawValue
        json["backgroundColor"] = backgroundColor?.toHex()
        json["textColor"] = textColor?.toHex()
        json["borderColor"] = borderColor?.toHex()
        json["iconSVG"] = iconSVG
        json["borderWidth"] = borderWidth
        json["height"] = height
        json["padding"] = padding
        json["borderRadius"] = borderRadius
        json["width"] = width
        return json
    }

    package func toJSONString() -> String? {
        let json = toJSON()
        guard !json.isEmpty else { return nil }
        do {
            return String(data: try JSONSerialization.data(withJSONObject: json), encoding: .utf8)
        } catch {
            debugLog("Error serializing chat button style: \(error)")
            return nil
        }
    }
}
