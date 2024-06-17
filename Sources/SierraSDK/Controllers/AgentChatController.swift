// Copyright Sierra

import UIKit

public struct AgentChatControllerOptions {
    /// Name for this virtual agent, displayed as the navigation item title.
    public let name: String

    /// Message shown from the agent when starting the conversation.
    public var greetingMessage: String = "How can I help you today?"

    /// Secondary text to display above the agent message at the start of a conversation.
    public var disclosure: String?

    /// Message shown when an error is encountered during the conversation unless the
    /// server provided an alternate message to display.
    public var errorMessage: String = "Oops, an error was encountered! Please try again."

    /// Message shown when waiting for a human agent to join the conversation.
    public var humanAgentTransferWaitingMessage: String = "Waiting for agent…"

    /// Message shown when waiting for a human agent to join the conversation,
    /// and the queue size is known. "{QUEUE_SIZE}" will be replaced with the
    /// size of the queue.
    public var humanAgentTransferQueueSizeMessage: String = "Queue Size: {QUEUE_SIZE}"

    /// Message shown when waiting for a human agent to join the conversation,
    /// and the user is next in line.
    public var humanAgentTransferQueueNextMessage: String = "You are next in line"

    /// Message shown when a human agent has joined the conversation.
    public var humanAgentTransferJoinedMessage: String = "Agent connected"

    /// Message shown when a human agent has left the conversation.
    public var humanAgentTransferLeftMessage: String = "Agent disconnected"

    /// Placeholder value displayed in the chat input when it is empty.
    public var inputPlaceholder: String = "Message…"

    /// Shown in place of the chat input when the conversation has ended.
    public var conversationEndedMessage: String = "Chat Ended";

    /// Customize the look and feel of the chat
    public var chatStyle: ChatStyle = DEFAULT_CHAT_STYLE

    /// If set to true user will be able to save a conversation transcript via a menu item.
    public var canSaveTranscript: Bool = false;

    /// Menu label for the conversation transcript saving item.
    public var saveTranscriptLabel: String = "Save Transcript"

    /// File name for the generated transcript file.
    public var transcriptFileName: String = "Transcript"

    /// Customization of the Conversation that the controller will create.
    public var conversationOptions: ConversationOptions?

    /// Optional delegate that will be told when the conversation that
    /// is being conducted changes state. This delegate is active for the
    /// lifespan of the AgentChatController instance, even if view is hidden.
    public weak var conversationDelegate: ConversationDelegate?

    public init(name: String) {
        self.name = name
    }
}

public class AgentChatController : UIViewController, ConversationDelegate {
    private let options: AgentChatControllerOptions
    private let conversation: Conversation
    private let messagesController: MessagesController
    private let inputController: InputController
    private weak var optionsConversationDelegate: ConversationDelegate?

    public init(agent: Agent, options: AgentChatControllerOptions) {
        self.options = options

        // The custom greeting was initially a UI-only concept and thus specified via AgentChatControllerOptions,
        // but it now also affects the API. We copy it over to ConversationOptions so that it can be included in
        // API requests..
        var conversationOptions = options.conversationOptions
        if !options.greetingMessage.isEmpty && conversationOptions?.customGreeting == nil {
            if conversationOptions == nil {
                conversationOptions = ConversationOptions()
            }
            conversationOptions?.customGreeting = options.greetingMessage
        }

        conversation = agent.newConversation(options: conversationOptions)
        if !options.greetingMessage.isEmpty {
            conversation.addGreetingMessage(options.greetingMessage)
        } else if let customGreeting = conversationOptions?.customGreeting {
            // Conversely, if the custom greeting is only in ConversationOptions, make sure the UI reflects it too.
            conversation.addGreetingMessage(customGreeting)
        }

        messagesController = MessagesController(conversation: conversation, options: MessagesControllerOptions(
            disclosure: options.disclosure,
            humanAgentTransferWaitingMessage: options.humanAgentTransferWaitingMessage,
            humanAgentTransferQueueSizeMessage: options.humanAgentTransferQueueSizeMessage,
            humanAgentTransferQueueNextMessage: options.humanAgentTransferQueueNextMessage,
            humanAgentTransferJoinedMessage: options.humanAgentTransferJoinedMessage,
            humanAgentTransferLeftMessage: options.humanAgentTransferLeftMessage,
            errorMessage: options.errorMessage,
            chatStyle: options.chatStyle
        ))
        inputController = InputController(conversation: conversation, placeholder: options.inputPlaceholder, conversationEndedMessage: options.conversationEndedMessage, chatStyle: options.chatStyle)
        optionsConversationDelegate = options.conversationDelegate
        super.init(nibName: nil, bundle: nil)

        addChild(messagesController)
        addChild(inputController)

        navigationItem.title = options.name

        // The default transparent appearance does not work well with the inverted scrolling
        // used by MessagesController. Default to an opaque appearance (that has a bottom
        // border). By doing this in the initializer, we give the embedding app a chance to
        // override this behavior if they don't like it.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = options.chatStyle.colors.titleBar
        appearance.titleTextAttributes[.foregroundColor] = options.chatStyle.colors.titleBarText
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance
        navigationItem.compactScrollEdgeAppearance = appearance
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("Unreachable")
    }

    public override func loadView() {
        let view = UIView(frame: UIScreen.main.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.backgroundColor = options.chatStyle.colors.backgroundColor
        self.view = view
        if let tintColor = options.chatStyle.colors.tintColor {
            view.tintColor = tintColor
        }

        let messagesView = messagesController.view!
        let inputView = inputController.view!

        messagesView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        inputView.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        messagesView.translatesAutoresizingMaskIntoConstraints = false
        inputView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(messagesView)
        view.addSubview(inputView)
        messagesController.tableView.keyboardDismissMode = .interactive

        let safeAreaGuide = view.safeAreaLayoutGuide
        let keyboardGuide = view.keyboardLayoutGuide
        NSLayoutConstraint.activate([
            messagesView.leadingAnchor.constraint(equalTo: safeAreaGuide.leadingAnchor),
            messagesView.trailingAnchor.constraint(equalTo: safeAreaGuide.trailingAnchor),
            messagesView.topAnchor.constraint(equalTo: safeAreaGuide.topAnchor),
            messagesView.bottomAnchor.constraint(equalTo: inputView.topAnchor, constant: -12),
            inputView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputView.bottomAnchor.constraint(equalTo: keyboardGuide.topAnchor, constant: -9),
        ])
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        conversation.addDelegate(self)
        if let optionsConversationDelegate {
            conversation.addDelegate(optionsConversationDelegate)
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        conversation.removeDelegate(self)
        if let optionsConversationDelegate {
            conversation.removeDelegate(optionsConversationDelegate)
        }
    }

    // MARK: ConversationDelegate

    public func conversation(_ conversation: Conversation, didChangeCanSaveTranscript canSaveTranscript: Bool) {
        updateActionMenu()
    }

    private func updateActionMenu() {
        var menuItems: [UIMenuElement] = []

        if options.canSaveTranscript && conversation.canSaveTranscript {
            menuItems.append(UIAction(title: options.saveTranscriptLabel, image: UIImage(systemName: "square.and.arrow.down.on.square")) { [weak self] _ in
                Task {
                    await self?.saveTranscript()
                }
            })
        }

        if menuItems.isEmpty {
            navigationItem.rightBarButtonItem = nil
        } else {
            let menuButton = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), style: .plain, target: self, action: nil)
            menuButton.menu = UIMenu(children: menuItems)
            navigationItem.rightBarButtonItem = menuButton
        }
    }
}

extension AgentChatController: UIDocumentInteractionControllerDelegate {
    private func saveTranscript() async {
        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.color = .tintColor
        let barButton = UIBarButtonItem(customView: activityIndicator)
        let previouRightBarButtonItem = self.navigationItem.rightBarButtonItem
        self.navigationItem.rightBarButtonItem = barButton
        activityIndicator.startAnimating()
        defer {
            activityIndicator.stopAnimating()
            self.navigationItem.rightBarButtonItem = previouRightBarButtonItem
        }

        do {
            let pdfData = try await self.conversation.saveTranscript()

            let pdfDataURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(self.options.transcriptFileName).pdf")
            try pdfData.write(to: pdfDataURL)

            let documentInteractionController = UIDocumentInteractionController(url: pdfDataURL)
            documentInteractionController.delegate = self
            documentInteractionController.presentPreview(animated: true)
        } catch {
            debugLog("Cannot save transcript, error: \(error)")
            let alert = UIAlertController(title: nil, message: self.options.errorMessage, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }

    public func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        return self
    }
}
