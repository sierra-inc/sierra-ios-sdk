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

    /// Placeholder value displayed in the chat input when it is empty.
    public var inputPlaceholder: String = "Message…"

    /// Customize the look and feel of the chat
    public var chatStyle: ChatStyle = DEFAULT_CHAT_STYLE

    /// Customization of the Conversation that the controller will create/
    public var conversationOptions: ConversationOptions?

    /// Optional delegate that will be told when the conversation that
    /// is being conducted changes state. This delegate is active for the
    /// lifespan of the AgentChatController instance, even if view is hidden.
    public weak var conversationDelegate: ConversationDelegate?

    public init(name: String) {
        self.name = name
    }
}

public class AgentChatController : UIViewController {
    private let options: AgentChatControllerOptions
    private let conversation: Conversation
    private let messagesController: MessagesController
    private let inputController: InputController
    private weak var optionsConversationDelegate: ConversationDelegate?

    public init(agent: Agent, options: AgentChatControllerOptions) {
        self.options = options
        conversation = agent.newConversation(options: options.conversationOptions)
        if !options.greetingMessage.isEmpty {
            conversation.addGreetingMessage(options.greetingMessage)
        }
        messagesController = MessagesController(conversation: conversation, options: MessagesControllerOptions(
            disclosure: options.disclosure,
            errorMessage: options.errorMessage,
            chatStyle: options.chatStyle
        ))
        inputController = InputController(conversation: conversation, placeholder: options.inputPlaceholder, chatStyle: options.chatStyle)
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

        if let optionsConversationDelegate {
            conversation.addDelegate(optionsConversationDelegate)
        }
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("Unreachable")
    }

    deinit {
        if let optionsConversationDelegate {
            conversation.removeDelegate(optionsConversationDelegate)
        }
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
        let readableGuide = view.readableContentGuide
        NSLayoutConstraint.activate([
            messagesView.leadingAnchor.constraint(equalTo: safeAreaGuide.leadingAnchor),
            messagesView.trailingAnchor.constraint(equalTo: safeAreaGuide.trailingAnchor),
            messagesView.topAnchor.constraint(equalTo: safeAreaGuide.topAnchor),
            messagesView.bottomAnchor.constraint(equalTo: inputView.topAnchor, constant: -12),
            inputView.leadingAnchor.constraint(equalTo: readableGuide.leadingAnchor),
            inputView.trailingAnchor.constraint(equalTo: readableGuide.trailingAnchor),
            inputView.bottomAnchor.constraint(equalTo: keyboardGuide.topAnchor, constant: -9),
        ])
    }
}
