// Copyright Sierra

import UIKit

/// A text view whose intrinsic height matches its contents.
class ExpandingTextView: UITextView {
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        self.isScrollEnabled = false
        NotificationCenter.default.addObserver(self, selector: #selector(textChanged), name: UITextView.textDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: UITextView.textDidChangeNotification, object: nil)
    }

    override var intrinsicContentSize: CGSize {
        let textSize = self.sizeThatFits(CGSize(width: self.frame.width, height: .greatestFiniteMagnitude))
        return CGSize(width: self.frame.width, height: textSize.height)
    }

    @objc private func textChanged() {
        self.invalidateIntrinsicContentSize()
    }
}
