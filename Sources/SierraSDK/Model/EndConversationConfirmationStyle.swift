// Copyright Sierra

import Foundation

/// Style overrides for inline end-conversation confirmation. Omitted values keep their defaults.
public struct EndConversationConfirmationStyle {
    public let showFooterDivider: Bool?
    public let confirmButton: ChatButtonStyle?
    public let cancelButton: ChatButtonStyle?

    public init(showFooterDivider: Bool? = nil,
                confirmButton: ChatButtonStyle? = nil,
                cancelButton: ChatButtonStyle? = nil) {
        self.showFooterDivider = showFooterDivider
        self.confirmButton = confirmButton
        self.cancelButton = cancelButton
    }

    package func toJSONString() -> String? {
        var json: [String: Any] = [:]
        if let showFooterDivider = showFooterDivider {
            json["showFooterDivider"] = showFooterDivider
        }
        if let button = confirmButton?.toJSON(), !button.isEmpty {
            json["confirmButton"] = button
        }
        if let button = cancelButton?.toJSON(), !button.isEmpty {
            json["cancelButton"] = button
        }
        guard !json.isEmpty else { return nil }
        do {
            let data = try JSONSerialization.data(withJSONObject: json)
            return String(data: data, encoding: .utf8)
        } catch {
            debugLog("Error serializing end conversation confirmation style: \(error)")
            return nil
        }
    }
}
