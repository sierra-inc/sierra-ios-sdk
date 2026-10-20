// Copyright Sierra

import UIKit

/// Sends disclosure link taps to the voice controller's link handler instead of the system default.
final class DisclosureLinkDelegate: NSObject, UITextViewDelegate {
    private let onLinkTap: (URL) -> Void

    init(onLinkTap: @escaping (URL) -> Void) {
        self.onLinkTap = onLinkTap
    }

    @available(iOS 17.0, *)
    func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
        guard case let .link(url) = textItem.content else {
            return defaultAction
        }
        return UIAction { [onLinkTap] _ in onLinkTap(url) }
    }

    // The default long-press menu can open the link without the host app's onLinkClick.
    @available(iOS 17.0, *)
    func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? {
        nil
    }

    func textView(
        _ textView: UITextView,
        shouldInteractWith url: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        if interaction == .invokeDefaultAction {
            onLinkTap(url)
        }
        return false
    }
}
