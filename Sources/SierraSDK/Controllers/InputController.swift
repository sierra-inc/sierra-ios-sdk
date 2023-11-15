// Copyright Sierra

import UIKit

class InputController : UIViewController, UITextViewDelegate, ConversationDelegate {
    private let conversation: Conversation
    private let placeholder: String
    private let chatStyle: ChatStyle
    private var placeholderVisible: Bool = false

    init(conversation: Conversation, placeholder: String, chatStyle: ChatStyle) {
        self.conversation = conversation
        self.placeholder = placeholder
        self.chatStyle = chatStyle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("Unreachable")
    }

    private lazy var inputTextView: UITextView = {
        let input = ExpandingTextView(frame: .zero)
        input.translatesAutoresizingMaskIntoConstraints = false
        input.font = UIFont.preferredFont(forTextStyle: .body)
        input.adjustsFontForContentSizeCategory = true
        input.accessibilityLabel = NSLocalizedString("Message", comment: "Accessibility label for the message input field in the chat")
        input.backgroundColor = .systemBackground
        input.layer.borderWidth = 1
        input.layer.cornerRadius = chatStyle.layout.bubbleRadius
        input.layer.masksToBounds = true
        let padding: CGFloat = 10
        input.textContainerInset = UIEdgeInsets(top: padding, left: padding, bottom: padding, right: SendButton.defaultSize.width + padding)
        input.delegate = self
        return input
    }()

    private lazy var sendButton: UIButton = {
        let button = SendButton(fillColor: chatStyle.colors.userBubble, strokeColor: chatStyle.colors.userBubbleText, action: .init(handler: { _ in
            self.maybeSend()
        }))
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override func loadView() {
        let view = UIView(frame: UIScreen.main.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.backgroundColor = .clear
        self.view = view
        view.addSubview(inputTextView)
        view.addSubview(sendButton)
        NSLayoutConstraint.activate([
            inputTextView.topAnchor.constraint(equalTo: view.topAnchor),
            inputTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputTextView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            sendButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -5),
            sendButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -5),
        ])
        showPlaceholder()
        updateLayerColors()
        updateSendButton()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        conversation.addDelegate(self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        conversation.removeDelegate(self)
    }

    override open func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
       super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateLayerColors()
        }
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

    private func updateLayerColors() {
        inputTextView.layer.borderColor = UIColor.systemFill.cgColor
    }

    private func updateSendButton() {
        let isEmpty = placeholderVisible || inputTextView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sendButton.isEnabled = !isEmpty && conversation.canSend
    }

    private func maybeSend() {
        let messageText = inputTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if conversation.canSend && messageText.count > 0 {
            Task {
                await conversation.sendUserMessage(text: messageText)
            }
            inputTextView.text = ""
            updateSendButton()
        }
    }

    // MARK: ConversationDelegate

    func conversation(_ conversation: Conversation, didChangeCanSend canSend: Bool) {
        updateSendButton()
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

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let key = presses.first?.key else { return }

        if (key.keyCode == .keyboardReturn || key.keyCode == .keyboardReturnOrEnter) && key.modifierFlags == .shift {
            self.maybeSend()
            return
        }

        super.pressesBegan(presses, with: event)
    }

    func textViewDidChange(_ textView: UITextView) {
        updateSendButton()
    }
}
