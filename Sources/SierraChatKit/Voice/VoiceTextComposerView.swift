// Copyright Sierra

import UIKit

public final class VoiceTextComposerView: UIView {
    public let textField = UITextField()
    public let sendButton = UIButton(type: .system)
    public var onSend: (() -> Void)?

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
        layer.cornerRadius = 18
        clipsToBounds = true
        isUserInteractionEnabled = true

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(focusTextField))
        tapGesture.cancelsTouchesInView = false
        addGestureRecognizer(tapGesture)

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.placeholder = placeholder
        textField.font = font
        textField.textColor = textColor
        textField.returnKeyType = .send
        textField.autocorrectionType = .yes
        textField.autocapitalizationType = .sentences
        textField.clearButtonMode = .never
        textField.addTarget(self, action: #selector(textFieldEditingChanged), for: .editingChanged)
        textField.addTarget(self, action: #selector(textFieldEditingChanged), for: [.editingDidBegin, .editingDidEnd])
        addSubview(textField)

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

        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            textField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            sendButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            sendButton.widthAnchor.constraint(equalToConstant: 24),
            sendButton.heightAnchor.constraint(equalToConstant: 24),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 38),
        ])
    }

    public func updateSendButtonVisibility(animated: Bool = true) {
        let shouldShow =
            textField.isEditing &&
            (textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
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

    @objc private func focusTextField() {
        guard textField.isEnabled else { return }
        textField.becomeFirstResponder()
    }

    @objc private func textFieldEditingChanged() {
        updateSendButtonVisibility()
    }

    @objc private func sendTapped() {
        onSend?()
    }
}
