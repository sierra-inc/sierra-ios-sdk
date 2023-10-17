// Copyright Sierra

import UIKit

class InputController : UIViewController, UITextViewDelegate {
    private let conversation: Conversation
    private let placeholder: String
    private var placeholderVisible: Bool = false

    init(conversation: Conversation, placeholder: String) {
        self.conversation = conversation
        self.placeholder = placeholder
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("Unreachable")
    }

    private lazy var inputTextView: UITextView = {
        let input = ExpandingTextView(frame: .zero)
        input.translatesAutoresizingMaskIntoConstraints = false
        input.returnKeyType = .send
        input.font = UIFont.preferredFont(forTextStyle: .body)
        input.adjustsFontForContentSizeCategory = true
        input.accessibilityLabel = NSLocalizedString("Message", comment: "Accessibility label for the message input field in the chat")
        input.backgroundColor = .systemBackground
        input.layer.borderColor = UIColor.systemFill.cgColor
        input.layer.borderWidth = 1
        input.layer.cornerRadius = 16
        input.layer.masksToBounds = true
        input.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        input.delegate = self
        return input
    }()

    override func loadView() {
        let view = UIView(frame: UIScreen.main.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.backgroundColor = .clear
        self.view = view
        view.addSubview(inputTextView)
        NSLayoutConstraint.activate([
            inputTextView.topAnchor.constraint(equalTo: view.topAnchor),
            inputTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputTextView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        showPlaceholder()
    }

    private func showPlaceholder() {
        inputTextView.text = placeholder
        inputTextView.textColor = .secondaryLabel
        placeholderVisible = true
    }

    private func hidePlaceholder() {
        inputTextView.text = nil
        inputTextView.textColor = .label
        placeholderVisible = false
    }

    // MARK: UITextViewDelegate

    func textViewDidBeginEditing(_ textView: UITextView) {
        if placeholderVisible {
            hidePlaceholder()
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.text.isEmpty {
            showPlaceholder()
        }
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            let messageText = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if conversation.canSend && messageText.count > 0 {
                Task {
                    await conversation.sendUserMessage(text: messageText)
                }
                textView.text = ""
            }
            return false
        }
        return true
    }

}
