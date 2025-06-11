// Copyright Sierra

import UIKit
import WebKit

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

    /// Message shown when there is no internet connection.
    public var noInternetConnectionErrorMessage: String = "No internet connection. Please check your connection and try again."

    /// Message shown when the chat cannot be loaded.
    public var chatLoadErrorMessage: String = "Could not load the chat"

    /// Customize the look and feel of the chat
    public var chatStyle: ChatStyle = DEFAULT_CHAT_STYLE

    /// If set to true user will be able to save a conversation transcript via a menu item.
    public var canSaveTranscript: Bool = false;

    /// If set to true user will be able to end a conversation via a menu item.
    public var canEndConversation: Bool = false;

    /// If set to true user will be able to start a new conversation via a menu item.
    public var canStartNewChat: Bool = false;

    /// Menu label for the conversation transcript saving item.
    public var saveTranscriptLabel: String = "Save Transcript"

    /// Menu label for the conversation ending item.
    public var endConversationLabel: String = "End Conversation"

    /// File name for the generated transcript file.
    public var transcriptFileName: String = "Transcript"

    /// Customization of the Conversation that the controller will create.
    public var conversationOptions: ConversationOptions?

    /// Optional callbacks that will be invoked at various points in the conversation lifecycle.
    public weak var conversationCallbacks: ConversationCallbacks?

    @available(*, deprecated, message: "Use conversationCallbacks instead.")
    public weak var conversationDelegate: ConversationDelegate?

    public init(name: String) {
        self.name = name
    }
}

extension AgentChatControllerOptions {
    func toQueryItems() -> [URLQueryItem] {
        var queryItems = [URLQueryItem]()

        // Should match the Brand type from bots/useChat.tsx
        let brand: [String: Any] = [
            "botName": name,
            "errorMessage": errorMessage,
            "greetingMessage": greetingMessage,
            "disclosure": disclosure ?? "",
            "inputPlaceholder": inputPlaceholder,
            "agentTransferWaitingMessage": humanAgentTransferWaitingMessage,
            "agentTransferQueueSizeMessage": humanAgentTransferQueueSizeMessage,
            "agentTransferQueueNextMessage": humanAgentTransferQueueNextMessage,
            "agentJoinedMessage": humanAgentTransferJoinedMessage,
            "agentLeftMessage": humanAgentTransferLeftMessage,
            "conversationEndedMessage": conversationEndedMessage,
            "chatStyle": chatStyle.toJSONString(),
        ]
        do {
            let brandData = try JSONSerialization.data(withJSONObject: brand, options: [])
            if let brandJSON = String(data: brandData, encoding: .utf8) {
                queryItems.append(URLQueryItem(name: "brand", value: brandJSON))
            } else {
                debugLog("Error: Unable to encode brand data as a string")
            }
        } catch {
            debugLog ("Error serializing brand object: \(error)")
        }

        if let co = conversationOptions {
            let locale = co.locale ?? Locale.current
            queryItems.append(URLQueryItem(name: "locale", value: locale.identifier))
            if let variables = co.variables {
                for (name, value) in variables {
                    queryItems.append(URLQueryItem(name: "variable", value: "\(name):\(value)"))
                }
            }
            if let secrets = co.secrets {
                for (name, value) in secrets {
                    queryItems.append(URLQueryItem(name: "secret", value: "\(name):\(value)"))
                }
            }
            if let enableContactCenter = co.enableContactCenter {
                queryItems.append(URLQueryItem(name: "enableContactCenter", value: "\(enableContactCenter)"))
            }
            if let customGreeting = co.customGreeting, !customGreeting.isEmpty {
                queryItems.append(URLQueryItem(name: "greeting", value: customGreeting))
            }
        }

        if canEndConversation {
            queryItems.append(URLQueryItem(name: "canEndConversation", value: "true"))
        }

        if canStartNewChat {
            queryItems.append(URLQueryItem(name: "canStartNewChat", value: "true"))
        }

        if canSaveTranscript {
            queryItems.append(URLQueryItem(name: "canPrintTranscript", value: "true"))
        }
        return queryItems
    }
}

public class AgentChatController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler {
    private var webView: CustomWebView!
    private var webViewLoaded = false
    private let agent: Agent
    private var options: AgentChatControllerOptions
    private var loadingSpinner: UIActivityIndicatorView?
    private weak var optionsConversationCallbacks: ConversationCallbacks?
    private var requestEndConversationEnabled = false

    public init(agent: Agent, options: AgentChatControllerOptions) {
        self.agent = agent
        self.options = options

        // The custom greeting was initially a UI-only concept and thus specified via AgentChatControllerOptions,
        // but it now also affects the API, so it's in ConversationOptions. Read it from both places
        // so that old clients don't need to change anything.
        var conversationOptions = options.conversationOptions
        if !options.greetingMessage.isEmpty && conversationOptions?.customGreeting == nil {
            if conversationOptions == nil {
                conversationOptions = ConversationOptions()
            }
            conversationOptions?.customGreeting = options.greetingMessage
            self.options.conversationOptions = conversationOptions
        }

        optionsConversationCallbacks = options.conversationCallbacks

        super.init(nibName: nil, bundle: nil)
        setupWebView()

        navigationItem.title = options.name
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

    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        let contentController = configuration.userContentController

        // Add the script message handler
        contentController.add(self, name: "chatHandler")

        webView = CustomWebView(frame: .zero, configuration: configuration)
        webView.backgroundColor = options.chatStyle.colors.backgroundColor
        webView.isOpaque = true

        // Make the content invisible until fully loaded
        webView.scrollView.alpha = 0.0

        let loadingSpinner = UIActivityIndicatorView(style: .large)
        loadingSpinner.color = options.chatStyle.colors.titleBarText
        loadingSpinner.translatesAutoresizingMaskIntoConstraints = false
        loadingSpinner.hidesWhenStopped = true

        webView.addSubview(loadingSpinner)
        NSLayoutConstraint.activate([
            loadingSpinner.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            loadingSpinner.centerYAnchor.constraint(equalTo: webView.centerYAnchor)
        ])
        self.loadingSpinner = loadingSpinner

        webView.navigationDelegate = self
        webView.customUserAgent = getUserAgent(isWebView: true)
        webView.scrollView.backgroundColor = options.chatStyle.colors.backgroundColor
        webView.scrollView.keyboardDismissMode = .interactive
    }

    public override func loadView() {
        self.view = webView
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Try again to load if we didn't get successfuly do it the first time we were shown.
        if !webViewLoaded {
            self.loadingSpinner?.startAnimating()
            loadChatURL()
        }
    }

    private func loadChatURL() {
        guard var urlComponents = URLComponents(string: self.agent.config.url) else {
            debugLog("Invalid URL: \(self.agent.config.url)")
            return
        }

        // Turn config and options into query parameters that mobile.tsx expects
        var queryItems = self.options.toQueryItems()
        if let target = self.agent.config.target, !target.isEmpty {
            queryItems.append(URLQueryItem(name: "target", value: target))
        }

        // Always hideTitleBar for iOS
        queryItems.append(URLQueryItem(name: "hideTitleBar", value: "true"))

        // In iOS, we persist state via sessionStorage since we can rely on it being
        // maintained across the iOS lifecycle.
        queryItems.append(URLQueryItem(name: "persistenceMode", value: "tab"))

        urlComponents.queryItems = queryItems
        if let url = urlComponents.url {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }

    private func updateActionMenu() {
        var menuItems: [UIMenuElement] = []
        
        if options.canEndConversation {
            let endConversationAction = UIAction(title: options.endConversationLabel, image: UIImage(systemName: "xmark.circle")) { [weak self] _ in
                Task {
                    await self?.endConversation()
                }
            }
            endConversationAction.attributes = requestEndConversationEnabled ? [] : [.disabled]
            menuItems.append(endConversationAction)
        }
        
        if options.canSaveTranscript {
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

    // MARK: - WKScriptMessageHandler

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }

        if message.name == "chatHandler" {
            if let type = body["type"] as? String {
                switch type {
                case "onOpen":
                    // Fade in only the content with a smooth animation
                    DispatchQueue.main.async {
                        self.webViewLoaded = true
                        self.loadingSpinner?.stopAnimating()
                        UIView.animate(withDuration: 0.3, animations: {
                            self.webView.scrollView.alpha = 1.0
                        })
                    }
                case "onConversationIDAvailable":
                    updateActionMenu()
                case "onTransfer":
                    if let dataJSONStr = body["dataJSONStr"] as? String {
                       if let transfer = ConversationTransfer.fromJSON(dataJSONStr) {
                           optionsConversationCallbacks?.onConversationTransfer(transfer: transfer)
                       }
                    }
                case "onAgentMessageEnd":
                    optionsConversationCallbacks?.onAgentMessageEnd()
                case "onRequestEndConversationEnabledChange":
                    if let enabled = body["enabled"] as? Bool {
                        requestEndConversationEnabled = enabled
                        updateActionMenu()
                        optionsConversationCallbacks?.onRequestEndConversationEnabledChange(enabled)
                    }
                case "onEndChat":
                    optionsConversationCallbacks?.onConversationEnded()
                case "onPrint":
                    if let url = body["url"] as? String,
                        let formData = body["formData"] as? String {
                        handlePrint(url: URL(string: url)!, formData: formData)
                    }
                default:
                    debugLog("Received unknown message type: \(type)")
                    break
                }
            }
        }

    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "chatHandler")
    }

    // MARK: - WKNavigationDelegate Methods

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadingSpinner?.stopAnimating()
        handleNavigationError(error)
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadingSpinner?.stopAnimating()
        handleNavigationError(error)
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Allow navigation within the app
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url,
           !url.absoluteString.hasPrefix(self.agent.config.url) {
            // Handle external links - open in browser
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(.allow)
    }

    private func handleNavigationError(_ error: Error) {
        let errorCode = (error as NSError).code

        if errorCode == NSURLErrorCancelled {
            return
        }

        let errorMessage: String
        if errorCode == NSURLErrorNotConnectedToInternet {
            errorMessage = options.noInternetConnectionErrorMessage
        } else {
            errorMessage = options.chatLoadErrorMessage
        }

        let alert = UIAlertController(title: "Error", message: errorMessage, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Close", style: .destructive) { [weak self] _ in
            // If presented modally, dismiss the view controller
            if self?.presentingViewController != nil {
                self?.dismiss(animated: true)
            }
            // If pushed onto a navigation stack, pop back
            else if let navigationController = self?.navigationController {
                navigationController.popViewController(animated: true)
            }
        })
        alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in
            self?.loadChatURL()
            self?.loadingSpinner?.startAnimating()
        })
        present(alert, animated: true)
    }

    // MARK: - Printing Support

    private func handlePrint(url: URL, formData: String) {
        Task {
            do {
                let pdfData = try await generatePDFData(url: url, formData: formData)
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
    }

    func generatePDFData(url: URL, formData: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = formData.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let generator = TranscriptPDFGenerator(request: request)
        let pdfData = try await generator.generate()
        return pdfData
    }
}

class CustomWebView: WKWebView {
    override var inputAccessoryView: UIView? {
        return nil
    }
}

extension AgentChatController: UIDocumentInteractionControllerDelegate {
    private func saveTranscript() async {
        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.color = .tintColor
        let barButton = UIBarButtonItem(customView: activityIndicator)
        let previousRightBarButtonItem = self.navigationItem.rightBarButtonItem
        self.navigationItem.rightBarButtonItem = barButton
        activityIndicator.startAnimating()
        defer {
            activityIndicator.stopAnimating()
            self.navigationItem.rightBarButtonItem = previousRightBarButtonItem
        }

        do {
            try await webView.evaluateJavaScript("sierraMobile.printTranscript()", completionHandler: nil)
        } catch {
            debugLog("Cannot save transcript, error: \(error)")
        }
    }

    private func endConversation() async {
        debugLog("Ending conversation")
        do {
            try await webView.evaluateJavaScript("sierraMobile.endConversation()", completionHandler: nil)
        } catch {
            debugLog("Cannot end conversation, error: \(error)")
        }
    }

    public func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        return self
    }
}

@available(*, deprecated)
public class DeprecatedAgentChatController : UIViewController, ConversationDelegate {
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

extension DeprecatedAgentChatController: UIDocumentInteractionControllerDelegate {
    private func saveTranscript() async {
        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.color = .tintColor
        let barButton = UIBarButtonItem(customView: activityIndicator)
        let previousRightBarButtonItem = self.navigationItem.rightBarButtonItem
        self.navigationItem.rightBarButtonItem = barButton
        activityIndicator.startAnimating()
        defer {
            activityIndicator.stopAnimating()
            self.navigationItem.rightBarButtonItem = previousRightBarButtonItem
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
