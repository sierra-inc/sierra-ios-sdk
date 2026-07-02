// Copyright Sierra

import UIKit

public final class VoiceTextComposerView: UIView, UITextViewDelegate {
    private enum Metrics {
        static let minimumHeight: CGFloat = 38
        static let maximumVisibleLines: CGFloat = 4
        static let cornerRadius: CGFloat = 18
        static let textLeadingInset: CGFloat = 14
        static let textToSendButtonSpacing: CGFloat = 8
        static let sendButtonTrailingInset: CGFloat = 10
        static let sendButtonBottomInset: CGFloat = 7
        static let sendButtonSize: CGFloat = 24
    }

    public let textView = UITextView()

    @available(*, deprecated, message: "Use textView instead.")
    public let textField = UITextField()

    public let sendButton = UIButton(type: .system)
    public var onSend: (() -> Void)?
    public var onEditingChanged: ((Bool) -> Void)?

    public var text: String {
        get { textView.text ?? "" }
        set {
            textView.text = newValue
            updatePlaceholderVisibility()
            updateSendButtonVisibility(animated: false)
            updateHeightForCurrentText()
        }
    }

    private let placeholderLabel = UILabel()
    private var heightConstraint: NSLayoutConstraint?
    private var lastLayoutWidth: CGFloat = 0
    private func verticalTextContainerInset(for font: UIFont) -> CGFloat {
        max(0, (Metrics.minimumHeight - font.lineHeight) / 2)
    }

    private var maximumHeight: CGFloat {
        let font = textView.font ?? .systemFont(ofSize: 14, weight: .regular)
        let insets = textView.textContainerInset.top + textView.textContainerInset.bottom
        return ceil(font.lineHeight * Metrics.maximumVisibleLines + insets)
    }

    public init(
        placeholder: String = "Type a reply",
        backgroundColor: UIColor? = nil,
        textColor: UIColor = .label,
        font: UIFont = .systemFont(ofSize: 14, weight: .regular),
        sendButtonTintColor: UIColor = UIColor(red: 18 / 255, green: 48 / 255, blue: 76 / 255, alpha: 1),
        sendIcon: UIImage? = nil
    ) {
        super.init(frame: .zero)
        configure(
            placeholder: placeholder,
            backgroundColor: backgroundColor,
            textColor: textColor,
            font: font,
            sendButtonTintColor: sendButtonTintColor,
            sendIcon: sendIcon
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard abs(textView.bounds.width - lastLayoutWidth) > 0.5 else { return }
        lastLayoutWidth = textView.bounds.width
        updateHeightForCurrentText()
    }

    private func configure(
        placeholder: String,
        backgroundColor: UIColor?,
        textColor: UIColor,
        font: UIFont,
        sendButtonTintColor: UIColor,
        sendIcon: UIImage?
    ) {
        translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = backgroundColor ?? UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 36 / 255, green: 36 / 255, blue: 36 / 255, alpha: 1)
                : UIColor(red: 245 / 255, green: 245 / 255, blue: 245 / 255, alpha: 1)
        }
        layer.cornerRadius = Metrics.cornerRadius
        clipsToBounds = true
        isUserInteractionEnabled = true

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(focusTextView))
        tapGesture.cancelsTouchesInView = false
        addGestureRecognizer(tapGesture)

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.font = font
        textView.textColor = textColor
        textView.returnKeyType = .default
        textView.autocorrectionType = .yes
        textView.autocapitalizationType = .sentences
        let verticalInset = verticalTextContainerInset(for: font)
        textView.textContainerInset = UIEdgeInsets(top: verticalInset, left: 0, bottom: verticalInset, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.isScrollEnabled = false
        textView.delegate = self
        addSubview(textView)

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.text = placeholder
        placeholderLabel.font = font
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.isUserInteractionEnabled = false
        addSubview(placeholderLabel)

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.setImage(
            (sendIcon ?? UIImage(named: "SendArrow", in: .module, compatibleWith: nil))?.withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        sendButton.tintColor = sendButtonTintColor
        sendButton.accessibilityLabel = "Send"
        sendButton.isHidden = true
        sendButton.alpha = 0
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        addSubview(sendButton)

        let heightConstraint = heightAnchor.constraint(equalToConstant: Metrics.minimumHeight)
        self.heightConstraint = heightConstraint
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.textLeadingInset),
            textView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -Metrics.textToSendButtonSpacing),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),

            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: textView.centerYAnchor),

            sendButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.sendButtonBottomInset),
            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.sendButtonTrailingInset),
            sendButton.widthAnchor.constraint(equalToConstant: Metrics.sendButtonSize),
            sendButton.heightAnchor.constraint(equalToConstant: Metrics.sendButtonSize),
            heightConstraint,
        ])
    }

    public func updateSendButtonVisibility(animated: Bool = true) {
        let shouldShow =
            textView.isFirstResponder &&
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        guard sendButton.isHidden == shouldShow || sendButton.alpha != (shouldShow ? 1 : 0) else { return }

        if shouldShow {
            sendButton.isHidden = false
        }

        let changes = {
            self.sendButton.alpha = shouldShow ? 1 : 0
        }
        let completion: (Bool) -> Void = { _ in
            self.sendButton.isHidden = !shouldShow
        }

        if animated {
            UIView.animate(withDuration: 0.15, animations: changes, completion: completion)
        } else {
            changes()
            completion(true)
        }
    }

    public func setEnabled(_ enabled: Bool) {
        textView.isEditable = enabled
        textView.isSelectable = enabled
        sendButton.isEnabled = enabled
        alpha = enabled ? 1.0 : 0.5
    }

    public func textViewDidBeginEditing(_ textView: UITextView) {
        updateSendButtonVisibility()
        onEditingChanged?(true)
    }

    public func textViewDidEndEditing(_ textView: UITextView) {
        updateSendButtonVisibility()
        onEditingChanged?(false)
    }

    public func textViewDidChange(_ textView: UITextView) {
        updatePlaceholderVisibility()
        updateSendButtonVisibility()
        updateHeightForCurrentText()
    }

    private func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !text.isEmpty
    }

    private func updateHeightForCurrentText() {
        guard textView.bounds.width > 0, let heightConstraint else { return }

        let contentHeight: CGFloat
        if textView.isScrollEnabled {
            textView.layoutIfNeeded()
            contentHeight = ceil(textView.contentSize.height)
        } else {
            contentHeight = ceil(
                textView.sizeThatFits(
                    CGSize(width: textView.bounds.width, height: CGFloat.greatestFiniteMagnitude)
                ).height
            )
        }

        let nextHeight = min(max(Metrics.minimumHeight, contentHeight), maximumHeight)
        let shouldScroll = contentHeight > maximumHeight
        if textView.isScrollEnabled != shouldScroll {
            textView.isScrollEnabled = shouldScroll
        }

        guard abs(heightConstraint.constant - nextHeight) > 0.5 else { return }

        heightConstraint.constant = nextHeight
    }

    @objc private func focusTextView() {
        guard textView.isEditable else { return }
        textView.becomeFirstResponder()
    }

    @objc private func sendTapped() {
        onSend?()
    }
}
