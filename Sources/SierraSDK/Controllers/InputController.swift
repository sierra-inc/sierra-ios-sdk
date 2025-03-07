// Copyright Sierra

import UIKit

@available(*, deprecated)
class InputController : UIViewController, UITextViewDelegate, ConversationDelegate {
    private let conversation: Conversation
    private let placeholder: String
    private let conversationEndedMessage: String
    private let chatStyle: ChatStyle
    private var placeholderVisible: Bool = false

    init(conversation: Conversation, placeholder: String, conversationEndedMessage: String, chatStyle: ChatStyle) {
        self.conversation = conversation
        self.placeholder = placeholder
        self.conversationEndedMessage = conversationEndedMessage
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

    private lazy var topBorder: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemFill
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override func loadView() {
        let view = UIView(frame: UIScreen.main.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.backgroundColor = .clear
        self.view = view
        view.addSubview(inputTextView)
        view.addSubview(sendButton)
        view.addSubview(topBorder)

        let readableGuide = view.readableContentGuide

        NSLayoutConstraint.activate([
            inputTextView.topAnchor.constraint(equalTo: view.topAnchor),
            inputTextView.leadingAnchor.constraint(equalTo: readableGuide.leadingAnchor),
            inputTextView.trailingAnchor.constraint(equalTo: readableGuide.trailingAnchor),
            inputTextView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            sendButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -5),
            sendButton.trailingAnchor.constraint(equalTo: readableGuide.trailingAnchor, constant: -5),

            topBorder.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBorder.topAnchor.constraint(equalTo: view.topAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 1),
        ])
        topBorder.isHidden = true
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

    // Sending is no longer possible, make that apparent by having the input look disabled.
    private func disableSend() {
        inputTextView.text = ""
        inputTextView.isEditable = false
        inputTextView.isSelectable = false
        inputTextView.resignFirstResponder()
    }

    private func enableSend() {
        inputTextView.isEditable = true
        inputTextView.isSelectable = true
    }

    // MARK: ConversationDelegate

    func conversation(_ conversation: Conversation, didChangeCanSend canSend: Bool) {
        updateSendButton()
    }

    public func conversation(_ conversation: Conversation, didTransfer transfer: ConversationTransfer) {
        if transfer.isSynchronous && !transfer.isContactCenter {
            disableSend()
        }
    }

    public func conversation(_ conversation: Conversation, didChangeHumanAgentParticipation participation: HumanAgentParticipation?, previousValue: HumanAgentParticipation?) {
        if participation?.state == .left {
            disableSend()
        } else if participation?.state == .joined {
            enableSend()
        }
    }

    func conversation(_ conversation: Conversation, didChangeConversationEnded conversationEnded: Bool) {
        if conversationEnded {
            disableSend()
            inputTextView.text = conversationEndedMessage
            inputTextView.textColor = .secondaryLabel
            inputTextView.backgroundColor = chatStyle.colors.backgroundColor
            inputTextView.layer.borderWidth = 0
            inputTextView.textAlignment = .center
            topBorder.isHidden = false
            sendButton.isHidden = true
        }
    }

    // MARK: UITextViewDelegate

    func textViewDidBeginEditing(_ textView: UITextView) {
        if placeholderVisible {
            hidePlaceholder()
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.text.isEmpty && !conversation.isSynchronouslyTransferred {
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
