// Copyright Sierra

import UIKit
import WebKit

/// Controls whether the message label (speaker name and timestamp) is shown
/// above or below chat message bubbles.
public enum MessageLabelPlacement: String {
    /// Use the server-configured value from the Style panel.
    case `default` = ""
    /// Show the message label above chat bubbles.
    case above = "above"
    /// Show the message label below chat bubbles.
    case below = "below"
}

/// Controls the text direction of the chat interface.
public enum TextDirection: String {
    /// Left-to-right layout (default).
    case ltr = "ltr"
    /// Right-to-left layout, for languages like Arabic and Hebrew.
    case rtl = "rtl"
    /// Automatically configured from the conversation locale.
    case auto = "auto"
}

public struct AgentChatControllerOptions {
    /// Name for this virtual agent, displayed as the navigation item title.
    public let name: String

    /// Use chat interface strings configured on the server (greeting, error messages, etc.),
    /// including server-managed locale/direction settings for those strings.
    /// When enabled, server-configured values take precedence over local string options.
    public var useConfiguredChatStrings: Bool = false

    /// Use styling configured on the server (colors, typography, logo, etc.).
    /// When enabled, server-configured styles take precedence over local chatStyle.
    ///
    /// Note: iOS hides the title bar in the web view by default and uses the native UINavigationBar
    /// instead. The native navigation bar colors are still configured via chatStyle.colors.titleBar
    /// and chatStyle.colors.titleBarText, which remain necessary for iOS even when using
    /// server-configured styles.
    public var useConfiguredStyle: Bool = false

    /// Message shown from the agent when starting the conversation. Overridden by server-configured
    /// greeting message if useConfiguredChatStrings is true.
    public var greetingMessage: String = "How can I help you today?"

    /// Secondary text to display above the agent message at the start of a conversation. Overridden
    /// by server-configured disclosure if useConfiguredChatStrings is true.
    public var disclosure: String?

    /// Message shown when an error is encountered during the conversation unless the server
    /// provided an alternate message to display. Overridden by server-configured error message if
    /// useConfiguredChatStrings is true.
    public var errorMessage: String = "Oops, an error was encountered! Please try again."

    // Message shown when a conversation was ended due to inactivity. Overridden by
    // server-configured inactivity message if useConfiguredChatStrings is true.
    public var inactivityMessage: String?

    /// Message shown when waiting for a human agent to join the conversation. Overridden by
    /// server-configured human agent transfer waiting message if useConfiguredChatStrings is true.
    public var humanAgentTransferWaitingMessage: String = "Waiting for agent…"

    /// Message shown when waiting for a human agent to join the conversation, and the queue size is
    /// known. "{QUEUE_SIZE}" will be replaced with the size of the queue. Overridden by
    /// server-configured human agent transfer queue size message if useConfiguredChatStrings is
    /// true.
    public var humanAgentTransferQueueSizeMessage: String = "Queue Size: {QUEUE_SIZE}"

    /// Message shown when waiting for a human agent to join the conversation, and the user is next
    /// in line. Overridden by server-configured human agent transfer queue next message if
    /// useConfiguredChatStrings is true.
    public var humanAgentTransferQueueNextMessage: String = "You are next in line"

    /// Message shown when a human agent has joined the conversation. Overridden by
    /// server-configured human agent transfer joined message if useConfiguredChatStrings is true.
    public var humanAgentTransferJoinedMessage: String = "Agent connected"

    /// Message shown when a human agent has left the conversation. Overridden by server-configured
    /// human agent transfer left message if useConfiguredChatStrings is true.
    public var humanAgentTransferLeftMessage: String = "Agent disconnected"

    /// Placeholder value displayed in the chat input when it is empty. Overridden by
    /// server-configured input placeholder if useConfiguredChatStrings is true. Defaults to
    /// "Message…" when this value is empty.
    public var inputPlaceholder: String = ""

    /// Shown in place of the chat input when the conversation has ended. Overridden by
    /// server-configured conversation ended message if useConfiguredChatStrings is true. Defaults
    /// to "Chat ended" when this value is empty.
    public var conversationEndedMessage: String = ""

    /// Message shown when there is no internet connection.
    public var noInternetConnectionErrorMessage: String = "No internet connection. Please check your connection and try again."

    /// Message shown when the chat cannot be loaded.
    public var chatLoadErrorMessage: String = "Could not load the chat"

    /// Customize the look and feel of the chat.
    ///
    /// When useConfiguredStyle is true, the web content styling comes from the server.
    /// However, this property is still used for native iOS UI elements:
    /// - colors.titleBar: Navigation bar background color
    /// - colors.titleBarText: Navigation bar text color and loading spinner color
    /// - colors.backgroundColor: Container view and WebView background color
    /// - typography.customFonts: Custom fonts to load for the web content
    public var chatStyle: ChatStyle = DEFAULT_CHAT_STYLE

    /// Inline SVG markup for the chat send button. Replaces the default send arrow (including
    /// its background) when provided. Overridden by the server-configured value if useConfiguredStyle
    /// is true.
    public var sendButtonSVG: String?

    /// Inline SVG markup for the send button when it is disabled (e.g. the input is empty).
    /// Falls back to sendButtonSVG when not provided. Overridden by the server-configured value
    /// if useConfiguredStyle is true.
    public var sendButtonDisabledSVG: String?

    /// If set to true user will be able to save a conversation transcript via a menu item.
    public var canSaveTranscript: Bool = false;

    /// If set to true user will be able to end a conversation via a menu item.
    public var canEndConversation: Bool = false;

    /// If set to true, the user is asked to confirm before the conversation ends. The
    /// confirmation is shown inline within the chat (covering the transcript and input). Only
    /// effective when `canEndConversation` is true.
    public var confirmEndConversation: Bool = false;

    /// If set to true, an end conversation button is shown in the chat footer (above the input)
    /// while the user is speaking with a live agent. Only effective when `canEndConversation` is
    /// true.
    public var footerEndConversationButton: Bool = false;

    /// If set to true, indicates the app uses a custom action bar and the SDK should not show
    /// its native end conversation button, even when canEndConversation is true. The end
    /// conversation functionality remains available via the endConversation() method.
    public var useCustomActionBar: Bool = false;

    /// If set to true, a "new chat" button is shown on the conversation view after the
    /// conversation has ended. Only effective when `canEndConversation` is true. When the
    /// conversation list is enabled, the list view always includes its own button to start
    /// a new chat regardless of this setting.
    public var canStartNewChat: Bool = false;

    /// Start the chat with messages at the top of the chat frame, allowing the conversation to
    /// expand downward until the frame height has been reached, at which point older messages
    /// scroll out of view.
    public var startAtTop: Bool = false;

    /// Whether to show a scroll-to-bottom indicator when the user scrolls up in the chat.
    public var showScrollToBottom: Bool = false;

    /// Pin the disclosure text to the top of the chat frame so that it is visible throughout
    /// the conversation and never scrolls out of view.
    public var pinDisclosure: Bool = false;

    /// Whether to show timestamps on chat messages. When nil and useConfiguredStyle is true, the
    /// server-configured value is used.
    public var showTimestamps: Bool?

    /// Whether to show speaker labels (e.g. the agent name) on chat messages. When nil and
    /// useConfiguredStyle is true, the server-configured value is used.
    public var showSpeakerLabels: Bool?

    /// Whether to show per-message avatars for agents. When enabled, the chat shows avatars next to
    /// live agent messages using image URLs provided by the contact center. If agentAvatarURL is also
    /// set, that image is shown next to virtual agent messages. When nil and useConfiguredStyle is
    /// true, the server-configured value is used.
    public var showAvatars: Bool?

    /// HTTPS URL of an image to show next to virtual agent messages when showAvatars is enabled.
    /// Values are trimmed and must be 2048 characters or fewer. When nil and useConfiguredStyle is
    /// true, the server-configured value is used.
    public var agentAvatarURL: String?

    /// Controls whether the message label (speaker name and timestamp) is shown above or below chat
    /// message bubbles. When `.default` and useConfiguredStyle is true, the server-configured
    /// value is used.
    public var messageLabelPlacement: MessageLabelPlacement = .default

    /// Explicitly set whether or not to auto-detect locale-specific chat strings and text direction
    /// from the conversation locale.
    public var autoDetectChatStrings: Bool?

    /// Explicitly set the text direction of the chat window.
    /// - `.ltr`: Forces the chat window to use a left-to-right language layout.
    /// - `.rtl`: Forces the chat window to use a right-to-left language layout.
    /// - `.auto`: Text direction is automatically configured from the conversation locale.
    /// When nil, automatically determined from locale if auto-detection is active --
    /// either via `autoDetectChatStrings` or the server's Agent Studio configuration
    /// when `useConfiguredChatStrings` is true. Otherwise falls back to the server
    /// value when `useConfiguredChatStrings` is true, or left-to-right.
    public var textDirection: TextDirection?

    /// Menu label for the conversation transcript saving item.
    public var saveTranscriptLabel: String = "Save Transcript"

    /// Menu label for the conversation ending item.
    public var endConversationLabel: String = "End Conversation"

    /// Label for the new chat button.
    public var newChatButtonLabel: String = "Start new chat"

    /// File name for the generated transcript file.
    public var transcriptFileName: String = "Transcript"

    /// Message that will be automatically sent from the user when the conversation starts.
    public var initialUserMessage: String?

    /// A signed JWT that identifies the end user for this session. When set, the token is
    /// forwarded to the server on every chat request for identity resolution. The server
    /// extracts the `sub` claim and resolves a persistent EndUser, enabling cross-session
    /// memory and conversation history. Must be an RS256-signed JWT with `aud: "sierra.ai"`.
    public var userIdentityToken: String?

    /// Whether to show the conversation list UI. Requires userIdentityToken.
    public var enableConversationList: Bool = false

    /// Whether to show the conversation list by default when the chat opens.
    /// Only takes effect when enableConversationList is true.
    public var showConversationListByDefault: Bool = false

    /// Customization of the Conversation that the controller will create.
    public var conversationOptions: ConversationOptions?

    /// Optional callbacks that will be invoked at various points in the conversation lifecycle.
    public weak var conversationCallbacks: ConversationCallbacks?

    @available(*, deprecated, message: "Use conversationCallbacks instead.")
    public weak var conversationDelegate: ConversationDelegate?

    public init(name: String) {
        self.name = name
    }

    // MARK: - SDK-internal options
    //
    // These options are configured by `AgentVoiceChatCoordinator` and are not part of the
    // public SDK surface. To opt into unified voice/chat flows, use the coordinator rather
    // than setting these directly.

    /// When true, shows a native navigation-bar button in the chat title bar that lets the
    /// user reconnect to voice. The coordinator sets this only when the conversation
    /// originally started in voice and has been continued in chat.
    package var canReconnectToVoice: Bool = false

    /// Label used for the reconnect-voice button.
    package var reconnectVoiceLabel: String = "Reconnect voice"

    /// Callback invoked when the reconnect-voice button is tapped.
    package var onReconnectVoice: (() -> Void)?

    /// Invoked when the conversation ends, separate from the host's
    /// `conversationCallbacks.onConversationEnded` so the coordinator can clear its own
    /// state without interposing on the host's callbacks.
    package var onConversationEnded: (() -> Void)?
}

private extension AgentChatControllerOptions {
    // A baseline instance with the hardcoded English defaults, used to detect which fields the
    // caller has actually customized. When locale auto-detect or server-configured chat strings are
    // enabled, any field still equal to its default is omitted so locale defaults or server values
    // can take effect.
    static let defaults = AgentChatControllerOptions(name: "")

    var shouldOmitDefaultChatStrings: Bool {
        autoDetectChatStrings == true || useConfiguredChatStrings
    }

    var hasCustomGreetingMessage: Bool {
        greetingMessage != Self.defaults.greetingMessage
    }

    var shouldUseGreetingMessageAsCustomGreeting: Bool {
        if greetingMessage.isEmpty {
            return false
        }
        if !shouldOmitDefaultChatStrings {
            return true
        }
        return hasCustomGreetingMessage
    }
}

extension AgentChatControllerOptions {
    func toQueryItems(conversationState: String? = nil) -> [URLQueryItem] {
        var queryItems = [URLQueryItem]()

        // Should match the web embed's Brand shape.
        var brand: [String: Any] = [
            "botName": name,
            "greetingMessage": greetingMessage,
            "errorMessage": errorMessage,
            "inactivityMessage": inactivityMessage ?? "",
            "agentTransferWaitingMessage": humanAgentTransferWaitingMessage,
            "agentTransferQueueSizeMessage": humanAgentTransferQueueSizeMessage,
            "agentTransferQueueNextMessage": humanAgentTransferQueueNextMessage,
            "agentJoinedMessage": humanAgentTransferJoinedMessage,
            "agentLeftMessage": humanAgentTransferLeftMessage,
            "chatStyle": chatStyle.toJSONString(),
            "messageLabelPlacement": messageLabelPlacement.rawValue,
        ]
        if let showTimestamps { brand["showTimestamps"] = showTimestamps }
        if let showSpeakerLabels { brand["showBotName"] = showSpeakerLabels }
        if let showAvatars { brand["showAvatars"] = showAvatars }
        if let agentAvatarURL { brand["agentAvatarURL"] = agentAvatarURL }
        if let sendButtonSVG { brand["sendButtonSVG"] = sendButtonSVG }
        if let sendButtonDisabledSVG { brand["sendButtonDisabledSVG"] = sendButtonDisabledSVG }
        // If locale auto-detect or server-configured chat strings are enabled, remove any messages
        // that are set to their default value so server-configured values or locale defaults can win.
        if shouldOmitDefaultChatStrings {
            if !hasCustomGreetingMessage {
                brand.removeValue(forKey: "greetingMessage")
            }
            if errorMessage == Self.defaults.errorMessage {
                brand.removeValue(forKey: "errorMessage")
            }
            if humanAgentTransferWaitingMessage == Self.defaults.humanAgentTransferWaitingMessage {
                brand.removeValue(forKey: "agentTransferWaitingMessage")
            }
            if humanAgentTransferQueueSizeMessage == Self.defaults.humanAgentTransferQueueSizeMessage {
                brand.removeValue(forKey: "agentTransferQueueSizeMessage")
            }
            if humanAgentTransferQueueNextMessage == Self.defaults.humanAgentTransferQueueNextMessage {
                brand.removeValue(forKey: "agentTransferQueueNextMessage")
            }
            if humanAgentTransferJoinedMessage == Self.defaults.humanAgentTransferJoinedMessage {
                brand.removeValue(forKey: "agentJoinedMessage")
            }
            if humanAgentTransferLeftMessage == Self.defaults.humanAgentTransferLeftMessage {
                brand.removeValue(forKey: "agentLeftMessage")
            }
        }
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

        // Subset of the ChatUiStrings type from chat/ui-strings.ts
        var chatInterfaceStrings: [String: Any] = [
            "inputPlaceholder": inputPlaceholder,
            "disclosure": disclosure ?? "",
            "conversationEndedMessage": conversationEndedMessage,
            "newChatButtonLabel": newChatButtonLabel,
        ]
        if shouldOmitDefaultChatStrings, newChatButtonLabel == Self.defaults.newChatButtonLabel {
            chatInterfaceStrings.removeValue(forKey: "newChatButtonLabel")
        }
        do {
            let chatInterfaceStringsData = try JSONSerialization.data(withJSONObject: chatInterfaceStrings, options: [])
            if let chatInterfaceStringsJSON = String(data: chatInterfaceStringsData, encoding: .utf8) {
                queryItems.append(URLQueryItem(name: "chatInterfaceStrings", value: chatInterfaceStringsJSON))
            } else {
                debugLog("Error: Unable to encode chatInterfaceStrings data as a string")
            }
        } catch {
            debugLog("Error serializing chatInterfaceStrings object: \(error)")
        }

        if let co = conversationOptions {
            let locale = co.locale ?? Locale.current
            queryItems.append(URLQueryItem(name: "locale", value: locale.identifier))
            // Variables and secrets are intentionally not added to the URL. They are delivered to
            // the web embed via the window.__sierraInitialMemory bridge global (see
            // addInitialMemoryUserScript) so they cannot leak into device, proxy, or analytics logs.
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

        if confirmEndConversation {
            queryItems.append(URLQueryItem(name: "confirmEndConversation", value: "true"))
        }

        if footerEndConversationButton {
            queryItems.append(URLQueryItem(name: "footerEndConversationButton", value: "true"))
        }

        if canStartNewChat {
            queryItems.append(URLQueryItem(name: "canStartNewChat", value: "true"))
        }

        if startAtTop {
            queryItems.append(URLQueryItem(name: "startAtTop", value: "true"))
        }

        if showScrollToBottom {
            queryItems.append(URLQueryItem(name: "showScrollToBottom", value: "true"))
        }

        if pinDisclosure {
            queryItems.append(URLQueryItem(name: "pinDisclosure", value: "true"))
        }

        if canSaveTranscript {
            queryItems.append(URLQueryItem(name: "canPrintTranscript", value: "true"))
        }

        if let initialUserMessage = initialUserMessage, !initialUserMessage.isEmpty {
            queryItems.append(URLQueryItem(name: "initialUserMessage", value: initialUserMessage))
        }

        if useConfiguredChatStrings {
            queryItems.append(URLQueryItem(name: "useConfiguredChatStrings", value: "true"))
        }

        if useConfiguredStyle {
            queryItems.append(URLQueryItem(name: "useConfiguredStyle", value: "true"))
        }

        if let autoDetectChatStrings {
            queryItems.append(
                URLQueryItem(
                    name: "autoDetectChatStrings",
                    value: autoDetectChatStrings ? "true" : "false"
                )
            )
        }

        if let textDirection = textDirection {
            queryItems.append(URLQueryItem(name: "textDirection", value: textDirection.rawValue))
        }

        if let userIdentityToken = userIdentityToken, !userIdentityToken.isEmpty {
            queryItems.append(URLQueryItem(name: "userIdentityToken", value: userIdentityToken))
        }

        if let conversationState, !conversationState.isEmpty {
            queryItems.append(URLQueryItem(name: "state", value: conversationState))
        }

        if enableConversationList {
            queryItems.append(URLQueryItem(name: "enableConversationList", value: "true"))
        }

        if showConversationListByDefault {
            queryItems.append(URLQueryItem(name: "showConversationListByDefault", value: "true"))
        }

        return queryItems
    }
}

public class AgentChatController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
    private var webView: CustomWebView!
    private var webViewLoaded = false
    private let agent: Agent
    private var options: AgentChatControllerOptions
    private let conversationState: String?
    private var loadingSpinner: UIActivityIndicatorView?
    private weak var optionsConversationCallbacks: ConversationCallbacks?
    private var requestEndConversationEnabled = false
    private var conversationEnded = false
    private var transferredToHumanAgent = false
    private var currentConversationID: String?
    private var showingConversationList = false
    private var isPageVisible = false
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var didRevealContent = false
    private var revealFallbackWorkItem: DispatchWorkItem?

    /// Creates a chat controller backed by a WKWebView.
    ///
    /// - Parameters:
    ///   - agent: The Sierra agent to chat with.
    ///   - options: Long-lived configuration that is safe to reuse across presentations.
    ///   - conversationState: Optional opaque state token returned by the public Sierra API
    ///     identifying a specific conversation to resume. Supply this only on the controller
    ///     instance that should resume that conversation; do not retain it on long-lived
    ///     configuration, since reusing the same value after the user starts a new
    ///     conversation will cause that new conversation to be replaced by the original one.
    public init(
        agent: Agent,
        options: AgentChatControllerOptions,
        conversationState: String? = nil
    ) {
        self.agent = agent
        self.options = options
        self.conversationState = conversationState

        // The custom greeting was initially a UI-only concept and thus specified via AgentChatControllerOptions,
        // but it now also affects the API, so it's in ConversationOptions. Read it from both places
        // so that old clients don't need to change anything.
        var conversationOptions = options.conversationOptions
        if options.shouldUseGreetingMessageAsCustomGreeting && conversationOptions?.customGreeting == nil {
            if conversationOptions == nil {
                conversationOptions = ConversationOptions()
            }
            conversationOptions?.customGreeting = options.greetingMessage
            self.options.conversationOptions = conversationOptions
        }

        optionsConversationCallbacks = options.conversationCallbacks
        showingConversationList = options.enableConversationList && options.showConversationListByDefault && options.userIdentityToken != nil

        super.init(nibName: nil, bundle: nil)
        setupWebView()

        navigationItem.title = options.name
        updateNavigationBarAppearance()
        updateNavigationItems()
    }

    private func updateNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = options.chatStyle.colors.titleBar
        appearance.titleTextAttributes[.foregroundColor] = options.chatStyle.colors.titleBarText
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance
        navigationItem.compactScrollEdgeAppearance = appearance
    }

    private func updateNavigationItems() {
        guard !options.useCustomActionBar else { return }

        if options.enableConversationList && !showingConversationList {
            if #available(iOS 16.0, *) {
                navigationItem.backAction = UIAction { [weak self] _ in
                    guard let self else { return }
                    Task { await self.showConversationList() }
                }
                navigationItem.leftBarButtonItem = nil
                navigationItem.hidesBackButton = false
            } else {
                let backAction = UIAction(title: "", image: UIImage(systemName: "chevron.backward")) { [weak self] _ in
                    guard let self else { return }
                    Task { await self.showConversationList() }
                }
                navigationItem.leftBarButtonItem = UIBarButtonItem(primaryAction: backAction)
                navigationItem.hidesBackButton = true
            }
        } else {
            if #available(iOS 16.0, *) {
                navigationItem.backAction = nil
            }
            navigationItem.leftBarButtonItem = nil
            navigationItem.hidesBackButton = false
        }

        updateActionMenu()
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("Unreachable")
    }

    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        let contentController = configuration.userContentController

        // Add the script message handler
        contentController.add(self, name: "chatHandler")
        contentController.addScriptMessageHandler(self, contentWorld: .page, name: "chatReplyHandler")

        // Pre-populate storage before the web content loads. This allows the web embed to read
        // stored conversation state synchronously during init.
        addStorageUserScript(to: contentController)
        addCapabilitiesUserScript(to: contentController)
        addInitialMemoryUserScript(to: contentController)

        applyAppBoundDomainsConfig(configuration)
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

#if targetEnvironment(simulator)
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
#endif
    }

    public override func loadView() {
        // Create a container view to hold the webview with keyboard layout guide constraints
        let containerView = UIView()
        containerView.backgroundColor = options.chatStyle.colors.backgroundColor

        // Add webview to container
        webView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(webView)

        // Set up constraints using keyboard layout guide
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: containerView.keyboardLayoutGuide.topAnchor)
        ])

        self.view = containerView
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Try again to load if we didn't get successfully do it the first time we were shown.
        if !webViewLoaded {
            self.loadingSpinner?.startAnimating()
            loadChatURL()
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        addLifecycleObservers()
        dispatchAppStatusChange(true)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        dispatchAppStatusChange(false)
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        removeLifecycleObservers()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }

        // Update native UI elements for the new appearance
        updateNavigationBarAppearance()
        view.backgroundColor = options.chatStyle.colors.backgroundColor
        webView.backgroundColor = options.chatStyle.colors.backgroundColor
        webView.scrollView.backgroundColor = options.chatStyle.colors.backgroundColor
        loadingSpinner?.color = options.chatStyle.colors.titleBarText

        // Reload the WebView with updated color values
        reloadWebViewForAppearanceChange()
    }

    /// Reloads the WebView with current color values after an appearance change.
    /// Preserves conversation state by updating the storage user script before reloading.
    private func reloadWebViewForAppearanceChange() {
        webViewLoaded = false
        isPageVisible = false
        didRevealContent = false
        revealFallbackWorkItem?.cancel()
        revealFallbackWorkItem = nil
        webView.scrollView.alpha = 0.0
        loadingSpinner?.startAnimating()
        let contentController = webView.configuration.userContentController
        contentController.removeAllUserScripts()
        addStorageUserScript(to: contentController)
        addCapabilitiesUserScript(to: contentController)
        addInitialMemoryUserScript(to: contentController)
        loadChatURL()
    }

    /// Adds a user script that pre-populates conversation storage for the web embed.
    private func addStorageUserScript(to contentController: WKUserContentController) {
        let storage = agent.getStorage().getAll()
        if let jsonData = try? JSONSerialization.data(withJSONObject: storage),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let storageScript = WKUserScript(
                source: "window.__sierraSyncStorage = \(jsonString);",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
            contentController.addUserScript(storageScript)
        }
    }

    /// Advertises which optional native callbacks this SDK build supports so the web embed can
    /// avoid registering bridge functions that would no-op or hang on older hosts.
    private func addCapabilitiesUserScript(to contentController: WKUserContentController) {
        let capabilitiesScript = WKUserScript(
            source: "window.__sierraMobileCapabilities = { onUserIdentityTokenExpiry: true };",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(capabilitiesScript)
    }

    /// Delivers the initial agent memory (variables and secrets) to the web embed via a
    /// document-start global instead of URL query parameters, so the values cannot leak into
    /// device, proxy, or analytics logs.
    private func addInitialMemoryUserScript(to contentController: WKUserContentController) {
        var memory: [String: [String: String]] = [:]
        if let variables = options.conversationOptions?.variables, !variables.isEmpty {
            memory["variables"] = variables
        }
        if let secrets = options.conversationOptions?.secrets, !secrets.isEmpty {
            memory["secrets"] = secrets
        }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: memory),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            return
        }
        let memoryScript = WKUserScript(
            source: "window.__sierraInitialMemory = \(jsonString);",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(memoryScript)
    }

    private func loadChatURL() {
        guard var urlComponents = URLComponents(string: self.agent.config.url) else {
            debugLog("Invalid URL: \(self.agent.config.url)")
            return
        }

        // Turn config and options into query parameters that the iOS web embed expects.
        var queryItems = self.options.toQueryItems(conversationState: self.conversationState)
        if let target = self.agent.config.target, !target.isEmpty {
            queryItems.append(URLQueryItem(name: "target", value: target))
        }

        // Always hideTitleBar for iOS
        queryItems.append(URLQueryItem(name: "hideTitleBar", value: "true"))

        // Use custom persistence mode to enable Agent-level storage via JS bridge.
        // This allows conversation state to persist across controller recreation
        // (when the same Agent is reused) and optionally survive app restarts (DISK mode).
        queryItems.append(URLQueryItem(name: "persistenceMode", value: "custom"))

        urlComponents.queryItems = queryItems

        // Fix RFC 3986 vs WHATWG mismatch: JavaScript's URLSearchParams decodes + as space,
        // but iOS doesn't encode + by default. Force-encode + as %2B for compatibility.
        urlComponents.percentEncodedQuery = urlComponents.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")

        if let url = urlComponents.url {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }

    private func updateActionMenu() {
        if showingConversationList {
            navigationItem.rightBarButtonItems = nil
            return
        }

        var rightItems: [UIBarButtonItem] = []
        if !conversationEnded, !transferredToHumanAgent, let reconnectVoiceButton = makeReconnectVoiceButton() {
            rightItems.append(reconnectVoiceButton)
        }

        var menuItems: [UIMenuElement] = []

        if options.canEndConversation && !options.useCustomActionBar {
            let endConversationAction = UIAction(title: options.endConversationLabel, image: UIImage(systemName: "xmark.circle")) { [weak self] _ in
                Task {
                    await self?.endConversation()
                }
            }
            endConversationAction.attributes = requestEndConversationEnabled ? [] : [.disabled]
            menuItems.append(endConversationAction)
        }

        if options.canSaveTranscript && !options.useCustomActionBar {
            menuItems.append(UIAction(title: options.saveTranscriptLabel, image: UIImage(systemName: "square.and.arrow.down.on.square")) { [weak self] _ in
                Task {
                    await self?.saveTranscript()
                }
            })
        }
        if !menuItems.isEmpty {
            let menuButton = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), style: .plain, target: self, action: nil)
            menuButton.menu = UIMenu(children: menuItems)
            rightItems.append(menuButton)
        }
        navigationItem.rightBarButtonItems = rightItems.isEmpty ? nil : rightItems
    }

    private func makeReconnectVoiceButton() -> UIBarButtonItem? {
        guard options.canReconnectToVoice else { return nil }
        return UIBarButtonItem(
            primaryAction: UIAction(
                title: options.reconnectVoiceLabel,
                image: UIImage(systemName: "waveform")
            ) { [weak self] _ in
                self?.options.onReconnectVoice?()
            }
        )
    }

    /// How long to keep the spinner up for a resumed conversation while waiting for
    /// `onConversationReady`. Only reached when the embed does not send that message (e.g. an
    /// older embed build); the normal path reveals as soon as the transcript has rendered.
    private static let revealFallbackInterval: TimeInterval = 10

    /// Stops the loading spinner and fades in the web content. Idempotent: the reveal animation
    /// runs only once per load. Cancels any pending fallback reveal.
    private func revealWebContent() {
        revealFallbackWorkItem?.cancel()
        revealFallbackWorkItem = nil
        guard !didRevealContent else { return }
        didRevealContent = true
        loadingSpinner?.stopAnimating()
        UIView.animate(withDuration: 0.3, animations: {
            self.webView.scrollView.alpha = 1.0
        })
    }

    /// Keeps the spinner up for a resumed conversation until `onConversationReady` arrives,
    /// scheduling a fallback reveal so the spinner is never stranded if that message never comes.
    private func scheduleRevealFallback() {
        guard !didRevealContent, revealFallbackWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.revealWebContent()
        }
        revealFallbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.revealFallbackInterval,
            execute: workItem
        )
    }

    // MARK: - WKScriptMessageHandler

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }

        if message.name == "chatHandler" {
            if let type = body["type"] as? String {
                switch type {
                case "onOpen":
                    let isNewConversation = body["isNewConversation"] as? Bool ?? true
                    DispatchQueue.main.async {
                        self.webViewLoaded = true
                        // If we became visible before the web content finished loading,
                        // ensure that appstatuschange is dispatched now.
                        self.dispatchAppStatusChange(true)

                        if isNewConversation {
                            // New conversation: the greeting is already rendered, so reveal now.
                            self.revealWebContent()
                        } else {
                            // Resuming an existing conversation: keep the spinner up until the
                            // transcript has rendered (onConversationReady) so we don't flash an
                            // empty greeting state. A fallback timer guards against older embeds
                            // that never send onConversationReady.
                            self.scheduleRevealFallback()
                        }
                    }
                case "onConversationReady":
                    DispatchQueue.main.async {
                        self.revealWebContent()
                    }
                case "onConversationIDAvailable":
                    if let unprefixedConversationID = body["unprefixedConversationID"] as? String {
                        // A different conversation is now active in this controller (e.g. the user
                        // started a new chat or switched conversations). Clear per-conversation UI
                        // state so a prior transfer doesn't keep the reconnect-voice button hidden;
                        // the embed re-sends onTransfer for the new conversation if it too is
                        // transferred.
                        if unprefixedConversationID != currentConversationID {
                            currentConversationID = unprefixedConversationID
                            transferredToHumanAgent = false
                        }
                        optionsConversationCallbacks?.onConversationStart(conversationID: unprefixedConversationID)
                    }
                    updateActionMenu()
                case "onTransfer":
                    if let dataJSONStr = body["dataJSONStr"] as? String {
                        if let transfer = ConversationTransfer.fromJSON(dataJSONStr) {
                            // A synchronous transfer hands the conversation off and continues it in
                            // this chat (the user waits for / talks to a live agent); contact-center
                            // transfers always continue in chat too. In both cases reconnecting to
                            // voice would resume the now-inactive virtual agent, so hide the button.
                            if transfer.isSynchronous || transfer.isContactCenter {
                                transferredToHumanAgent = true
                                updateActionMenu()
                            }
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
                case "onExternalAgentJoin":
                    // Backstop for onTransfer (e.g. resuming into a conversation a human agent has
                    // already joined): the conversation is now text-based with the human agent.
                    transferredToHumanAgent = true
                    updateActionMenu()
                    let externalConversationID = body["externalConversationID"] as? String
                    let externalAgentID = body["externalAgentID"] as? String
                    optionsConversationCallbacks?.onExternalAgentJoin(externalConversationID: externalConversationID, externalAgentID: externalAgentID)
                case "onEndChat":
                    optionsConversationCallbacks?.onConversationEnded()
                    options.onConversationEnded?()
                    conversationEnded = true
                    updateActionMenu()
                case "onShowConversationList":
                    showingConversationList = true
                    updateNavigationItems()
                    optionsConversationCallbacks?.onShowConversationList()
                case "onHideConversationList":
                    showingConversationList = false
                    updateNavigationItems()
                    optionsConversationCallbacks?.onHideConversationList()
                case "onPrint":
                    if let url = body["url"] as? String,
                       let formData = body["formData"] as? String {
                        handlePrint(url: URL(string: url)!, formData: formData)
                    }
                case "storeValue":
                    if let key = body["key"] as? String, let value = body["value"] as? String {
                        agent.getStorage().setItem(key, value)
                    }
                case "clearStorage":
                    agent.getStorage().clear()
                default:
                    debugLog("Received unknown message type: \(type)")
                    break
                }
            }
        } else {
            debugLog("Received unknown message: \(message.name)")
        }
    }


    // MARK: - WKScriptMessageHandlerWithReply

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any] else { return }

        if message.name == "chatReplyHandler" {
            if let type = body["type"] as? String {
                switch type {
                case "onSecretExpiry":
                    if let secretName = body["secretName"] as? String {
                        if let optionsConversationCallbacks {
                            optionsConversationCallbacks.onSecretExpiry(secretName: secretName) { result in
                                switch result {
                                case .success(let value): replyHandler(value, nil)
                                case .failure(let error): replyHandler(nil, error.localizedDescription)
                                }
                            }
                        } else {
                            replyHandler(nil, nil)
                        }
                    } else {
                        replyHandler(nil, "secretName is missing")
                    }
                case "onUserIdentityTokenExpiry":
                    if let optionsConversationCallbacks {
                        optionsConversationCallbacks.onUserIdentityTokenExpiry { result in
                            switch result {
                            case .success(let value): replyHandler(value, nil)
                            case .failure(let error): replyHandler(nil, error.localizedDescription)
                            }
                        }
                    } else {
                        replyHandler(nil, nil)
                    }
                case "getCustomFonts":
                    guard let customFonts = options.chatStyle.typography?.customFonts else {
                        // No custom fonts configured
                        replyHandler([], nil)
                        return
                    }
                    var fontsArray: [[String: String]] = []

                    for customFont in customFonts {
                        do {
                            let fontData = try Data(contentsOf: customFont.dataURL)
                            let base64String = fontData.base64EncodedString()
                            let dataURL = "data:\(customFont.fontType.mimeType);base64,\(base64String)"

                            // Should match the web embed's custom font shape.
                            fontsArray.append([
                                "fontFamily": customFont.fontFamily,
                                "fontData": dataURL,
                                "fontWeight": customFont.fontWeight,
                                "fontStyle": customFont.fontStyle
                            ])
                        } catch {
                            debugLog("Failed to load custom font '\(customFont.fontFamily)' from URL: \(customFont.dataURL). Error: \(error)")
                        }
                    }

                    replyHandler(fontsArray, nil)
                default:
                    debugLog("Received unknown message type: \(type)")
                    replyHandler(nil, "Unknown message type: \(type)")
                    break
                }
            }
        } else {
            debugLog("Received unknown reply message: \(message.name)")
        }
    }

    deinit {
        removeLifecycleObservers()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "chatHandler")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "chatReplyHandler", contentWorld: .page)
    }

    private func openExternalURL(_ url: URL) {
        if optionsConversationCallbacks?.onLinkClick(url: url) == true {
            return
        }

        UIApplication.shared.open(url, options: [:], completionHandler: nil)
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
            // Let the host app intercept external links before falling back to the system handler.
            openExternalURL(url)
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

        if optionsConversationCallbacks?.onConversationInitializationError() == true {
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

    private func addLifecycleObservers() {
        guard lifecycleObservers.isEmpty else { return }
        let nc = NotificationCenter.default
        if let windowScene = view.window?.windowScene {
            let sceneWillEnterForeground = nc.addObserver(forName: UIScene.willEnterForegroundNotification, object: windowScene, queue: .main) { [weak self] _ in
                self?.dispatchAppStatusChange(true)
            }
            let sceneDidEnterBackground = nc.addObserver(forName: UIScene.didEnterBackgroundNotification, object: windowScene, queue: .main) { [weak self] _ in
                self?.dispatchAppStatusChange(false)
            }
            lifecycleObservers.append(contentsOf: [sceneWillEnterForeground, sceneDidEnterBackground])
        }
        let willResign = nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.dispatchAppStatusChange(false)
        }
        let didEnterBg = nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.dispatchAppStatusChange(false)
        }
        let didBecome = nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.dispatchAppStatusChange(true)
        }
        lifecycleObservers.append(contentsOf: [willResign, didEnterBg, didBecome])
    }

    private func removeLifecycleObservers() {
        if !lifecycleObservers.isEmpty {
            lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
            lifecycleObservers.removeAll()
        }
    }

    private func dispatchAppStatusChange(_ isVisible: Bool) {
        guard view.window != nil else { return }
        guard webViewLoaded else { return }
        if isVisible {
            if isPageVisible { return }
            isPageVisible = true
        } else {
            if !isPageVisible { return }
            isPageVisible = false
        }
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        let status = isVisible ? "FOREGROUNDED" : "BACKGROUNDED"
        let js = "window.dispatchEvent(new CustomEvent('appstatuschange', { detail: { status: '" + status + "', localTimestampMs: " + String(nowMs) + " } }))"
        webView.evaluateJavaScript(js, completionHandler: nil)
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

    /// Send user attachments without text message (equivalent to web SDK's sendUserAttachment)
    /// - Parameter attachments: Array of UserAttachment objects to send
    /// - Throws: AgentChatError.invalidAttachments if attachments are invalid
    public func sendUserAttachment(_ attachments: [UserAttachment]) async throws {
        do {
            _ = try await webView.callAsyncJavaScript(
                """
                const fn = window.sierraMobile?.sendUserAttachment;
                if (typeof fn === 'function') {
                  return fn(attachments);
                }
                throw new Error('sendUserAttachment is not available');
                """,
                arguments: ["attachments": attachments.map { [
                    "type": $0.type.rawValue,
                    "data": $0.data
                ] }],
                in: nil,
                in: .page
            )
        } catch {
            throw AgentChatError.invalidAttachments("Failed to send attachments: \(error.localizedDescription)")
        }
    }

    /// End the current conversation programmatically.
    /// This is the public API that customers can call themselves. When
    /// `confirmEndConversation` is enabled, the user is asked to confirm before
    /// the conversation actually ends.
    public func endConversation() async {
        debugLog("Ending conversation")
        do {
            try await webView.evaluateJavaScript("sierraMobile.endConversation()", completionHandler: nil)
        } catch {
            debugLog("Cannot end conversation, error: \(error)")
        }
    }

    /// Navigate to the conversation list programmatically
    /// This is the public API that customers can call themselves.
    public func showConversationList() async {
        debugLog("Showing conversation list")
        do {
            try await webView.evaluateJavaScript("sierraMobile.showConversationList()", completionHandler: nil)
        } catch {
            debugLog("Cannot show conversation list, error: \(error)")
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
        // API requests.
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

        if !menuItems.isEmpty {
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
