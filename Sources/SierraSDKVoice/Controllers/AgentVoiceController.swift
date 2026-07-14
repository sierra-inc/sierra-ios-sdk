// Copyright Sierra

import AVFoundation
import SierraSDK
import SierraChatKit
import UIKit

public struct AgentAttachment {
    public let type: String
    public let data: [String: Any]

    public init(type: String, data: [String: Any]) {
        self.type = type
        self.data = data
    }

    fileprivate init?(raw: [String: Any]) {
        guard
            let type = raw["type"] as? String,
            let data = raw["data"] as? [String: Any]
        else {
            return nil
        }
        self.init(type: type, data: data)
    }
}

private let defaultMutePillBackgroundColor = UIColor(red: 231 / 255, green: 231 / 255, blue: 231 / 255, alpha: 1)
private let defaultMutePillIconColor = UIColor(red: 17 / 255, green: 17 / 255, blue: 17 / 255, alpha: 1)
private let messageRailHorizontalInset: CGFloat = 16
private let pillControlsSpacing: CGFloat = 8
private let compactControlsSpacing: CGFloat = 4
private let compactComposerControlsSpacing: CGFloat = 8

public struct AgentVoiceStyle {
    /// Background color for the native voice screen.
    public var backgroundColor: UIColor

    /// Background color for the native navigation bar.
    public var titleBarColor: UIColor

    /// Text/icon color for the native navigation bar.
    public var titleBarTextColor: UIColor

    /// Legacy control tint retained for compatibility with existing style initializers.
    /// The default center placeholder keeps the original system waveform styling.
    @available(*, deprecated, message: "No longer applied; pass colors to the legacy/pill buttons directly.")
    public var controlsColor: UIColor {
        get { legacyControlsColor }
        set { legacyControlsColor = newValue }
    }

    internal var legacyControlsColor: UIColor

    /// Optional fill color override for the mute button. Defaults to `#E7E7E7`.
    public var muteButtonColor: UIColor?

    /// Optional fill color override for the end conversation button. Defaults to a red pill.
    public var endConversationButtonColor: UIColor?

    /// Tint color applied to the mute button glyph and label.
    /// Defaults to `#111111` for the light default mute pill; set this explicitly when using a
    /// dark custom mute button color.
    public var muteButtonIconColor: UIColor

    /// Tint color applied to the end conversation button glyph and label.
    public var endConversationButtonIconColor: UIColor

    /// Text color for the optional disclosure shown below the controls.
    public var conversationDisclosureTextColor: UIColor

    /// Font for the optional disclosure shown below the controls.
    /// Set a custom `UIFont` to configure both the typeface and point size.
    public var conversationDisclosureFont: UIFont

    /// Optional override for the mobile renderer background color.
    /// When nil, the renderer falls back to `backgroundColor`.
    public var rendererBackgroundColor: UIColor?

    /// Transcript bubble colors in the mobile renderer.
    public var messageColors: ChatStyleColors

    /// Transcript bubble typography in the mobile renderer.
    public var messageTypography: ChatStyleTypography

    /// Tint color for the send arrow in the native text composer.
    /// When nil, the default composer uses `messageColors.userBubble`.
    public var textComposerSendButtonTintColor: UIColor?

    public init(
        backgroundColor: UIColor = .systemBackground,
        titleBarColor: UIColor = .systemBackground,
        titleBarTextColor: UIColor = .label,
        controlsColor: UIColor = UIColor(red: 16 / 255, green: 34 / 255, blue: 76 / 255, alpha: 1),
        muteButtonColor: UIColor? = nil,
        endConversationButtonColor: UIColor? = nil,
        muteButtonIconColor: UIColor = UIColor(red: 17 / 255, green: 17 / 255, blue: 17 / 255, alpha: 1),
        endConversationButtonIconColor: UIColor = .white,
        conversationDisclosureTextColor: UIColor = .secondaryLabel,
        conversationDisclosureFont: UIFont = .systemFont(ofSize: 12, weight: .regular),
        rendererBackgroundColor: UIColor? = nil,
        messageColors: ChatStyleColors = DEFAULT_CHAT_STYLE_COLORS,
        messageTypography: ChatStyleTypography = ChatStyleTypography(),
        textComposerSendButtonTintColor: UIColor? = nil
    ) {
        self.backgroundColor = backgroundColor
        self.titleBarColor = titleBarColor
        self.titleBarTextColor = titleBarTextColor
        self.legacyControlsColor = controlsColor
        self.muteButtonColor = muteButtonColor
        self.endConversationButtonColor = endConversationButtonColor
        self.muteButtonIconColor = muteButtonIconColor
        self.endConversationButtonIconColor = endConversationButtonIconColor
        self.conversationDisclosureTextColor = conversationDisclosureTextColor
        self.conversationDisclosureFont = conversationDisclosureFont
        self.rendererBackgroundColor = rendererBackgroundColor
        self.messageColors = messageColors
        self.messageTypography = messageTypography
        self.textComposerSendButtonTintColor = textComposerSendButtonTintColor
    }

    @available(*, deprecated, message: "Use messageColors and messageTypography instead.")
    public init(
        backgroundColor: UIColor = .systemBackground,
        titleBarColor: UIColor = .systemBackground,
        titleBarTextColor: UIColor = .label,
        controlsColor: UIColor = UIColor(red: 16 / 255, green: 34 / 255, blue: 76 / 255, alpha: 1),
        muteButtonColor: UIColor? = nil,
        endConversationButtonColor: UIColor? = nil,
        muteButtonIconColor: UIColor = UIColor(red: 17 / 255, green: 17 / 255, blue: 17 / 255, alpha: 1),
        endConversationButtonIconColor: UIColor = .white,
        conversationDisclosureTextColor: UIColor = .secondaryLabel,
        conversationDisclosureFont: UIFont = .systemFont(ofSize: 12, weight: .regular),
        rendererBackgroundColor: UIColor? = nil,
        textComposerSendButtonTintColor: UIColor? = nil,
        userBubble: UIColor,
        userBubbleText: UIColor,
        assistantBubble: UIColor,
        assistantBubbleText: UIColor,
        messageFontFamily: String = "SF Pro, -apple-system, BlinkMacSystemFont, sans-serif",
        messageFontWeight: Int = 510,
        messageFontSize: String = "14px",
        messageLineHeight: String = "20px",
        messageLetterSpacing: String = "-0.32px"
    ) {
        let fontSize = Self.cssPixelValue(messageFontSize).map { max(1, Int($0.rounded())) }
        let fontSizeDouble = Self.cssPixelValue(messageFontSize)
        let messageBubble = ChatTextStyle(
            fontWeight: messageFontWeight,
            lineHeight: Self.cssPixelValue(messageLineHeight).flatMap { lineHeight in
                fontSizeDouble.map { lineHeight / $0 }
            },
            letterSpacing: Self.cssPixelValue(messageLetterSpacing).flatMap { letterSpacing in
                fontSizeDouble.map { letterSpacing / $0 }
            }
        )
        self.init(
            backgroundColor: backgroundColor,
            titleBarColor: titleBarColor,
            titleBarTextColor: titleBarTextColor,
            controlsColor: controlsColor,
            muteButtonColor: muteButtonColor,
            endConversationButtonColor: endConversationButtonColor,
            muteButtonIconColor: muteButtonIconColor,
            endConversationButtonIconColor: endConversationButtonIconColor,
            conversationDisclosureTextColor: conversationDisclosureTextColor,
            conversationDisclosureFont: conversationDisclosureFont,
            rendererBackgroundColor: rendererBackgroundColor,
            messageColors: ChatStyleColors(
                assistantBubble: assistantBubble,
                assistantBubbleText: assistantBubbleText,
                userBubble: userBubble,
                userBubbleText: userBubbleText
            ),
            messageTypography: ChatStyleTypography(
                fontFamily: messageFontFamily,
                fontSize: fontSize,
                userBubble: messageBubble,
                assistantBubble: messageBubble
            ),
            textComposerSendButtonTintColor: textComposerSendButtonTintColor
        )
    }

    private static func cssPixelValue(_ value: String) -> Double? {
        guard value.hasSuffix("px") else { return nil }
        return Double(value.dropLast(2))
    }
}

extension AgentVoiceStyle {
    /// User transcript bubble background color in the mobile renderer.
    @available(*, deprecated, message: "Use messageColors instead.")
    public var userBubble: UIColor {
        get { messageColors.userBubble }
        set { messageColors = messageColors.with(userBubble: newValue) }
    }

    /// User transcript text color in the mobile renderer.
    @available(*, deprecated, message: "Use messageColors instead.")
    public var userBubbleText: UIColor {
        get { messageColors.userBubbleText }
        set { messageColors = messageColors.with(userBubbleText: newValue) }
    }

    /// Assistant transcript bubble background color in the mobile renderer.
    @available(*, deprecated, message: "Use messageColors instead.")
    public var assistantBubble: UIColor {
        get { messageColors.assistantBubble }
        set { messageColors = messageColors.with(assistantBubble: newValue) }
    }

    /// Assistant transcript text color in the mobile renderer.
    @available(*, deprecated, message: "Use messageColors instead.")
    public var assistantBubbleText: UIColor {
        get { messageColors.assistantBubbleText }
        set { messageColors = messageColors.with(assistantBubbleText: newValue) }
    }

    /// Transcript bubble font family in the mobile renderer.
    @available(*, deprecated, message: "Use messageTypography instead.")
    public var messageFontFamily: String {
        get { messageTypography.fontFamily ?? "SF Pro, -apple-system, BlinkMacSystemFont, sans-serif" }
        set { messageTypography = messageTypography.withGlobal(fontFamily: newValue) }
    }

    /// Transcript bubble font weight in the mobile renderer.
    @available(*, deprecated, message: "Use messageTypography instead.")
    public var messageFontWeight: Int {
        get { messageTypography.userBubble?.fontWeight ?? 510 }
        set { messageTypography = messageTypography.withMessageBubble(fontWeight: newValue) }
    }

    /// Transcript bubble font size in CSS pixels.
    @available(*, deprecated, message: "Use messageTypography instead.")
    public var messageFontSize: String {
        get { "\(messageTypography.fontSize ?? 14)px" }
        set {
            messageTypography = messageTypography.withGlobal(
                fontSize: Self.cssPixelValue(newValue).map { max(1, Int($0.rounded())) }
            )
        }
    }

    /// Transcript bubble line height in CSS pixels.
    @available(*, deprecated, message: "Use messageTypography instead.")
    public var messageLineHeight: String {
        get {
            guard let lineHeight = messageTypography.userBubble?.lineHeight else { return "20px" }
            return "\(lineHeight * Double(messageTypography.fontSize ?? 14))px"
        }
        set {
            let fontSize = Double(messageTypography.fontSize ?? 14)
            messageTypography = messageTypography.withMessageBubble(
                lineHeight: Self.cssPixelValue(newValue).map { $0 / fontSize }
            )
        }
    }

    /// Transcript bubble letter spacing in CSS pixels.
    @available(*, deprecated, message: "Use messageTypography instead.")
    public var messageLetterSpacing: String {
        get {
            guard let letterSpacing = messageTypography.userBubble?.letterSpacing else { return "-0.32px" }
            return "\(letterSpacing * Double(messageTypography.fontSize ?? 14))px"
        }
        set {
            let fontSize = Double(messageTypography.fontSize ?? 14)
            messageTypography = messageTypography.withMessageBubble(
                letterSpacing: Self.cssPixelValue(newValue).map { $0 / fontSize }
            )
        }
    }

    func messageStyleJSONString() -> String {
        ChatStyle(colors: messageColors, typography: messageTypography).toJSONString()
    }
}

private extension ChatStyleColors {
    func with(
        assistantBubble: UIColor? = nil,
        assistantBubbleText: UIColor? = nil,
        userBubble: UIColor? = nil,
        userBubbleText: UIColor? = nil
    ) -> ChatStyleColors {
        ChatStyleColors(
            backgroundColor: backgroundColor,
            text: text,
            border: border,
            assistantBubble: assistantBubble ?? self.assistantBubble,
            assistantBubbleText: assistantBubbleText ?? self.assistantBubbleText,
            userBubble: userBubble ?? self.userBubble,
            userBubbleText: userBubbleText ?? self.userBubbleText,
            newChatButton: newChatButton,
            newChatButtonText: newChatButtonText,
            inputPlaceholder: inputPlaceholder,
            uploadButtonIcon: uploadButtonIcon,
            disclosure: disclosure,
            disclosureLink: disclosureLink,
            userBubbleLink: userBubbleLink,
            assistantBubbleLink: assistantBubbleLink,
            disclosureText: disclosureText,
            errorText: errorText,
            humanAgentTransferWaitingText: statusText,
            titleBar: titleBar,
            titleBarText: titleBarText,
            tintColor: tintColor
        )
    }
}

private extension ChatStyleTypography {
    /// Returns a copy with the global `fontFamily`/`fontSize` replaced, preserving
    /// the per-region typography overrides.
    func withGlobal(fontFamily: String? = nil, fontSize: Int? = nil) -> ChatStyleTypography {
        ChatStyleTypography(
            fontFamily: fontFamily ?? self.fontFamily,
            fontSize: fontSize ?? self.fontSize,
            userBubble: userBubble,
            assistantBubble: assistantBubble,
            titleBar: titleBar,
            disclosure: disclosure,
            customFonts: customFonts
        )
    }

    /// Returns a copy with the message-bubble typography updated. Voice styles
    /// user and assistant transcript bubbles identically, so the same
    /// `ChatTextStyle` is mirrored into both regions.
    func withMessageBubble(
        fontWeight: Int? = nil,
        lineHeight: Double? = nil,
        letterSpacing: Double? = nil
    ) -> ChatStyleTypography {
        let base = userBubble ?? ChatTextStyle()
        let updated = ChatTextStyle(
            fontSize: base.fontSize,
            fontWeight: fontWeight ?? base.fontWeight,
            lineHeight: lineHeight ?? base.lineHeight,
            letterSpacing: letterSpacing ?? base.letterSpacing,
            fontFamily: base.fontFamily,
            fontStyle: base.fontStyle,
            link: base.link
        )
        return ChatStyleTypography(
            fontFamily: fontFamily,
            fontSize: fontSize,
            userBubble: updated,
            assistantBubble: updated,
            titleBar: titleBar,
            disclosure: disclosure,
            customFonts: customFonts
        )
    }
}

/// Configuration for `AgentVoiceController`.
public struct AgentVoiceControllerOptions {
    /// Name for this voice agent, displayed as the navigation item title.
    public let name: String

    /// Optional override for the navigation bar title.
    public var titleBarMessage: String?

    /// Hide the native navigation bar. The containing view is then responsible for any title or
    /// app bar UI.
    public var hideTitleBar: Bool = false

    /// Customize the look and feel of native voice UI elements.
    public var voiceStyle: AgentVoiceStyle = AgentVoiceStyle()

    /// Optional override for the native mute button component.
    public var muteButton: UIButton?

    /// Optional override for the native unmute button component.
    public var unmuteButton: UIButton?

    /// Optional override for the native end-call button component.
    public var endCallButton: UIButton?

    /// Optional override for the compact mute button shown while the text composer is focused.
    public var compactMuteButton: UIButton?

    /// Optional override for the compact unmute button shown while the text composer is focused.
    public var compactUnmuteButton: UIButton?

    /// Optional override for the compact end-call button shown while the text composer is focused.
    public var compactEndCallButton: UIButton?

    /// Optional override for the native text composer component.
    public var textComposerView: VoiceTextComposerView?

    /// Optional spacing override for the native mute/end controls row.
    /// Set this when providing custom buttons that need a spacing different from the SDK defaults.
    public var controlsSpacing: CGFloat?

    /// Optional distribution override for the native mute/end controls row.
    /// Set this when providing custom buttons that should not use the SDK's pill or legacy layout.
    public var controlsDistribution: UIStackView.Distribution?

    /// Text shown in the native voice waveform placeholder before the first
    /// renderable attachment is displayed.
    public var voicePlaceholderText: String = "How can I help you today?"

    /// Optional icon override for the central waveform placeholder. Use an
    /// SVG/vector asset from the host app asset catalog or any `UIImage`. The
    /// image is rendered as-provided (its own colors), so pass a template image
    /// if you want it tinted. It is shown statically, without the speaking-state
    /// pulse animation applied to the default waveform.
    public var voiceWaveformIcon: UIImage?

    /// Optional disclosure text shown below the native mute/end controls.
    public var disclosureText: String?

    /// Optional icon override for the mute button. Use an SVG/vector asset from
    /// the host app asset catalog or any template `UIImage`.
    /// When set, this replaces the default animated waveform.
    public var muteIcon: UIImage?

    /// Optional icon override for the muted state. Defaults to the SDK mic-off icon.
    public var mutedIcon: UIImage?

    /// Optional icon override for the end conversation button. Use an SVG/vector asset from
    /// the host app asset catalog or any template `UIImage`.
    public var endConversationIcon: UIImage?

    /// Optional key/value pairs to include in SVP `open.subMsg.agentParameters`.
    /// These values are treated as secrets by the voice backend and should be
    /// used for sensitive runtime context needed at voice start.
    public var voiceAgentParameters: [String: String]?

    /// Locale used for SVP voice session setup.
    /// Defaults to the current device locale.
    public var locale: Locale = .current

    /// Client-side SVP conversation identifier used to resume a prior voice session. When nil, a
    /// new identifier is generated when the controller starts the session.
    public var voiceConversationID: String?

    /// When true, requests that SVP resume the voice session identified by `voiceConversationID`.
    public var resumeConversation: Bool = false

    /// When true, mutes microphone capture while the agent is speaking.
    /// Prevents speaker audio from being picked up by the mic and
    /// misinterpreted as a user interruption.
    public var disableInterruptions: Bool = false

    /// Sent as `enableText` in the SVP `open` submessage. Defaults to `true`.
    public var enableText: Bool = true

    /// Sent as `forwardAgentAttachments` in the SVP `open` submessage. Defaults to `true`.
    public var forwardAgentAttachments: Bool = true

    /// When true, adds a text input and conversation-event transcript to the native voice surface.
    public var enableTextInput: Bool = false

    /// When true with `enableTextInput`, streams live user transcription text in the renderer.
    public var enableLiveTranscription: Bool = false

    /// Placeholder shown in the native text composer.
    public var textComposerPlaceholder: String = "Type a reply"

    public init(name: String) {
        self.name = name
        self.titleBarMessage = nil
    }

    @available(*, deprecated, message: "Use voiceAgentParameters instead.")
    public var voiceAgentSecrets: [String: String]? {
        get { voiceAgentParameters }
        set { voiceAgentParameters = newValue }
    }

    // MARK: - SDK-internal options
    //
    // These options are configured by `AgentVoiceChatCoordinator` and are not part of the public
    // SDK surface. To opt into unified voice/chat flows, use the coordinator rather than setting
    // these directly.

    /// When true, shows a navigation-bar button that lets the user switch from voice to chat
    /// without ending the conversation. Tapping the button disconnects the SVP session with the
    /// `continue_in_chat` close reason and invokes `onSwitchToChat`.
    internal var canSwitchToChat: Bool = false

    /// Accessibility label and (when an icon is unavailable) title used for the switch-to-chat
    /// button.
    internal var switchToChatLabel: String = "Continue in chat"

    /// Callback invoked when the conversation switches from voice to chat. `agentInitiated` is true
    /// for a server/agent-driven handoff (the agent requested continue-in-chat) and false for a
    /// user action (the switch-to-chat button or an end that routes to chat).
    internal var onSwitchToChat: ((_ agentInitiated: Bool) -> Void)?

    /// When true, tapping End closes the SVP session with the `continue_in_chat` close reason and
    /// invokes `onSwitchToChat` instead of `onVoiceEnded`. Set by `AgentVoiceChatCoordinator` when
    /// `autoShowChatOnEnd` is enabled.
    internal var endRoutesToChat: Bool = false

    /// Optional hint describing why the client is resuming. Only meaningful when
    /// `resumeConversation` is true; when set, the server emits a `continue-in-voice` client event
    /// so the agent can greet the user back to voice.
    internal var resumeReason: AgentVoiceResumeReason?

    /// Server-issued SVP resume token from a prior `opened` message. Sent on the open submessage to
    /// authorize resuming the existing conversation. Captured and persisted by
    /// `AgentVoiceChatCoordinator`; do not set directly.
    internal var resumeToken: String?

}

public extension AgentVoiceControllerOptions {
    /// Replaces the default pill controls with the legacy circular controls.
    ///
    /// Reuses the `muteIcon`, `mutedIcon`, and `endConversationIcon` overrides when set, falling back
    /// to the SDK's circular-control glyphs otherwise. With no arguments this reproduces the pre-pill
    /// appearance using `voiceStyle.muteButtonColor`, `voiceStyle.endConversationButtonColor`,
    /// `voiceStyle.endConversationButtonIconColor`, and `voiceStyle.controlsColor`. Pass
    /// `backgroundColor` or `iconColor` to force all controls to the same fill or glyph color.
    mutating func useLegacyVoiceControls(
        backgroundColor: UIColor? = nil,
        iconColor: UIColor? = nil
    ) {
        let muteBackground = backgroundColor ?? voiceStyle.muteButtonColor ?? voiceStyle.legacyControlsColor
        let endCallBackground = backgroundColor ?? voiceStyle.endConversationButtonColor ?? voiceStyle.legacyControlsColor
        let muteIconColor = iconColor ?? .white
        let endCallIconColor = iconColor ?? voiceStyle.endConversationButtonIconColor
        muteButton = MuteButtonLegacy(backgroundColor: muteBackground, iconColor: muteIconColor, muteIcon: muteIcon)
        unmuteButton = UnmuteButtonLegacy(backgroundColor: muteBackground, iconColor: muteIconColor, unmuteIcon: mutedIcon)
        endCallButton = EndCallButtonLegacy(backgroundColor: endCallBackground, iconColor: endCallIconColor, icon: endConversationIcon)
    }
}

/// Displays a native voice conversation with an embedded WebView for rendering
/// agent attachments. Voice audio is handled natively via VoiceSessionManager
/// (SVP WebSocket), while attachments are rendered by a MobileRendererView
/// that loads the agent's web bundle directly -- no conversation state, no
/// credential seeding, no refresh polling.
public class AgentVoiceController: UIViewController, VoiceSessionDelegate, MobileRendererDelegate {
    private let agent: Agent
    private var options: AgentVoiceControllerOptions
    private var voiceSession: VoiceSessionManager?
    private var secretRefreshOrchestrator: SecretRefreshOrchestrator?
    private var renderer: MobileRendererView?
    private var hasShownFirstAttachment = false
    private var rendererFailed = false
    private var hasAttemptedRendererLoad = false
    private var pendingRenderableAttachmentBatches: [[[String: Any]]] = []
    private var lastRenderableAttachmentsSignature: String?
    private var isMuted = false
    private var latestInputAudioLevel: Float = 0
    private var latestOutputAudioLevel: Float = 0

    private let placeholderContainer = UIView()
    private let placeholderWaveformIcon = UIImageView()
    private let placeholderLabel = UILabel()
    private let loadingContainer = UIView()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private let errorBannerView = UIView()
    private let errorBannerLabel = UILabel()

    private var muteButton: UIButton?
    private var unmuteButton: UIButton?
    private var endButton: UIButton?
    private var compactMuteButton: UIButton?
    private var compactUnmuteButton: UIButton?
    private var compactEndButton: UIButton?
    private var muteLevelDisplay: VoiceMuteLevelDisplaying?
    private var compactMuteLevelDisplay: VoiceMuteLevelDisplaying?
    private let controlsContainer = UIView()
    private var textComposerView: VoiceTextComposerView?
    private var normalButtonsStack: UIStackView?
    private var compactButtonsStack: UIStackView?
    private var shouldNormalButtonsFillMessageRail = false
    private let disclosureLabel = UILabel()
    private var previousNavigationBarHidden: Bool?
    private var hasShutdownVoiceSession = false
    private var hasReceivedInitialGreeting = false
    private var hasReceivedInitialAudioMessage = false
    private var initialGreetingFallbackWorkItem: DispatchWorkItem?
    private let initialGreetingFallbackDelay: TimeInterval = 2.0

    private var shouldHideTitleBar: Bool {
        options.hideTitleBar && !options.canSwitchToChat
    }

    public weak var voiceCallbacks: VoiceCallbacks?

    public init(agent: Agent, options: AgentVoiceControllerOptions = AgentVoiceControllerOptions(name: "Voice Agent")) {
        self.agent = agent
        self.options = options
        let trimmedTitleBarMessage = options.titleBarMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (trimmedTitleBarMessage?.isEmpty == false) ? trimmedTitleBarMessage! : options.name
        super.init(nibName: nil, bundle: nil)
        navigationItem.title = title
        if options.canSwitchToChat {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                primaryAction: UIAction(
                    title: options.switchToChatLabel,
                    image: UIImage(systemName: "bubble.left.and.bubble.right")
                ) { [weak self] _ in
                    self?.switchToChatTapped()
                }
            )
        }
        updateNavigationBarAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("Unreachable")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = options.voiceStyle.backgroundColor
        debugLog("AgentVoiceController: voice view loaded, conversationRendererURL=\(agent.config.conversationRendererURL)")
        setupBottomControls()
        setupWaveformPlaceholder()
        setupErrorBanner()
        setLoadingStateVisible(true)
        startVoiceSession()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard shouldHideTitleBar, let navigationController else { return }
        previousNavigationBarHidden = navigationController.isNavigationBarHidden
        navigationController.setNavigationBarHidden(true, animated: animated)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        voiceSession?.resumeListening()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let previousNavigationBarHidden, let navigationController {
            navigationController.setNavigationBarHidden(previousNavigationBarHidden, animated: animated)
            self.previousNavigationBarHidden = nil
        }
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if shouldShutdownVoiceSessionOnDisappear {
            shutdownVoiceSessionIfNeeded()
            fireDismissedIfNeeded()
        }
    }

    deinit {
        cancelInitialGreetingFallback()
        shutdownVoiceSessionIfNeeded()
        fireDismissedIfNeeded()
    }

    // MARK: - Voice Session

    private func startVoiceSession() {
        let voiceAgentParameters = options.voiceAgentParameters ?? [:]
        let voiceConversationID: String
        if let id = options.voiceConversationID {
            voiceConversationID = id
        } else {
            assert(!options.resumeConversation, "voiceConversationID must be set when resumeConversation is true")
            voiceConversationID = UUID().uuidString
        }
        let session = VoiceSessionManager(
            config: agent.config,
            conversationId: voiceConversationID,
            resumeConversation: options.resumeConversation,
            resumeReason: options.resumeReason,
            resumeToken: options.resumeToken,
            disableInterruptions: options.disableInterruptions,
            locale: options.locale,
            agentParameters: voiceAgentParameters,
            enableText: options.enableText,
            forwardAgentAttachments: options.forwardAgentAttachments,
            enableConversationEvents: options.enableTextInput,
            delegate: self
        )
        self.voiceSession = session
        self.secretRefreshOrchestrator = SecretRefreshOrchestrator(voiceSession: session, callbacks: voiceCallbacks)
        if options.enableTextInput {
            ensureMobileRendererLoaded()
        }
        session.connect()
        updateUI(for: .connecting)
    }

    private func shutdownVoiceSessionIfNeeded(closeReason: AgentVoiceCloseReason = .normal) {
        guard !hasShutdownVoiceSession else { return }
        hasShutdownVoiceSession = true
        secretRefreshOrchestrator?.cancel()
        secretRefreshOrchestrator = nil
        voiceSession?.disconnect(closeReason: closeReason)
        voiceSession = nil
    }

    private var shouldShutdownVoiceSessionOnDisappear: Bool {
        isBeingDismissed || isMovingFromParent || navigationController?.isBeingDismissed == true
    }

    // MARK: - VoiceSessionDelegate

    public func voiceSession(_ session: VoiceSessionManager, didReceiveCredentials conversationID: String, encryptionKey: String) {
        debugLog("Voice session received credentials: conversationID=\(conversationID)")
        DispatchQueue.main.async {
            self.voiceCallbacks?.onSessionInfoReceived(conversationID: conversationID, encryptionKey: encryptionKey)
        }
    }

    public func voiceSession(_ session: VoiceSessionManager, didReceiveResumeToken token: String) {
        DispatchQueue.main.async {
            self.voiceCallbacks?.onResumeTokenReceived(token: token)
        }
    }

    public func voiceSession(_ session: VoiceSessionManager, didChangeState state: VoiceSessionManager.State) {
        DispatchQueue.main.async {
            self.updateUI(for: state)
        }
    }

    public func voiceSessionDidReceiveInitialAudio(_ session: VoiceSessionManager) {
        DispatchQueue.main.async {
            self.hasReceivedInitialAudioMessage = true
            self.cancelInitialGreetingFallback()
        }
    }

    public func voiceSessionDidStartInitialAudioPlayback(_ session: VoiceSessionManager) {
        DispatchQueue.main.async {
            self.markInitialGreetingReceivedIfNeeded()
        }
    }

    public func voiceSession(_ session: VoiceSessionManager, didUpdateInputAudioLevel level: Float) {
        guard !isMuted else { return }
        latestInputAudioLevel = level
        muteLevelDisplay?.setInputLevel(level)
        if compactButtonsStack?.isHidden == false {
            compactMuteLevelDisplay?.setInputLevel(level)
        }
    }

    public func voiceSession(_ session: VoiceSessionManager, didUpdateOutputAudioLevel level: Float) {
        latestOutputAudioLevel = level
        muteLevelDisplay?.setOutputLevel(level)
        if compactButtonsStack?.isHidden == false {
            compactMuteLevelDisplay?.setOutputLevel(level)
        }
    }

    public func voiceSession(_ session: VoiceSessionManager, didReceiveConversationEvent event: AgentVoiceConversationEvent) {
        DispatchQueue.main.async {
            guard self.options.enableTextInput, !self.rendererFailed else {
                return
            }
            self.ensureMobileRendererLoaded()
            self.revealRendererContentIfNeeded()
            self.markInitialGreetingReceivedIfNeeded()
            self.renderer?.pushConversationEvent(event)
        }
    }

    public func voiceSession(_ session: VoiceSessionManager, didReceiveAttachments attachments: [[String: Any]]) {
        // Peel off any secret_refresh custom attachments and route them to
        // the orchestrator. The renderer cannot handle these and the host's
        // VoiceCallbacks is the right destination.
        var attachments = attachments
        var secretRefreshAttachments: [[String: Any]] = []
        attachments.removeAll { raw in
            if SecretRefreshOrchestrator.isSecretRefreshAttachment(raw) {
                secretRefreshAttachments.append(raw)
                return true
            }
            return false
        }
        if !secretRefreshAttachments.isEmpty, let secretRefreshOrchestrator {
            // Pick up the latest callbacks reference each time, in case the host
            // assigned voiceCallbacks after we constructed the orchestrator.
            secretRefreshOrchestrator.setCallbacks(voiceCallbacks)
            for attachment in secretRefreshAttachments {
                secretRefreshOrchestrator.handle(attachment: attachment)
            }
        }

        let attachmentTypes = attachments.compactMap { $0["type"] as? String }
        debugLog(
            "AgentVoiceController: received \(attachments.count) attachment(s) from SVP, types=\(attachmentTypes), renderer=\(renderer != nil ? "ready" : "nil")"
        )

        if options.enableTextInput {
            // Text input mode renders assistant text and attachments from ordered conversation
            // events so cards stay attached to the transcript message they belong to. Rendering
            // attachments_server batches as well would duplicate those cards and can reorder them.
            debugLog("AgentVoiceController: skipping attachments_server render because enableTextInput uses conversation events")
            return
        }

        if !attachments.isEmpty {
            let signature = renderableBatchSignature(attachments)
            if let signature, signature == lastRenderableAttachmentsSignature {
                debugLog("AgentVoiceController: dropping duplicate renderable attachment batch")
                return
            }
            lastRenderableAttachmentsSignature = signature

            let agentAttachments = attachments.compactMap(AgentAttachment.init(raw:))
            DispatchQueue.main.async {
                if !agentAttachments.isEmpty {
                    self.voiceCallbacks?.didReceiveAgentAttachment(attachments: agentAttachments)
                }

                if self.rendererFailed {
                    return
                }

                // Lazily load the renderer so voice startup/UI presentation is never blocked by WebView load.
                self.ensureMobileRendererLoaded()
                if self.rendererFailed {
                    return
                }

                self.revealRendererContentIfNeeded()

                if let renderer = self.renderer {
                    renderer.pushAttachments(attachments)
                } else {
                    self.pendingRenderableAttachmentBatches.append(attachments)
                }
            }
        } else {
            debugLog("AgentVoiceController: no renderable attachments in batch; renderer load skipped")
        }
    }

    private func renderableBatchSignature(_ attachments: [[String: Any]]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: attachments, options: [.sortedKeys]) else {
            return nil
        }
        return data.base64EncodedString()
    }

    private func revealRendererContentIfNeeded() {
        guard !hasShownFirstAttachment else { return }
        hasShownFirstAttachment = true
        placeholderContainer.isHidden = true
        stopWaveformAnimation()
        renderer?.isHidden = false
    }

    public func voiceSession(_ session: VoiceSessionManager, didEncounterError error: Error) {
        debugLog("Voice session error: \(error)")
        if isExternalAudioInterruptionError(error) {
            debugLog("AgentVoiceController: ending voice session due to external audio interruption error: \(error.localizedDescription)")
            DispatchQueue.main.async { self.endConversationForExit() }
            return
        }
        showErrorState(message: userFacingErrorMessage(for: error))
        DispatchQueue.main.async {
            self.voiceCallbacks?.onVoiceError(error: error)
        }
    }

    public func voiceSessionDidEnd(_ session: VoiceSessionManager) {
        DispatchQueue.main.async {
            self.updateUI(for: .ended)
            guard !self.hasShutdownVoiceSession else { return }
            self.hasShutdownVoiceSession = true
            self.fireEndedIfNeeded()
        }
    }

    public func voiceSessionDidRequestContinueInChat(_ session: VoiceSessionManager) {
        DispatchQueue.main.async {
            self.updateUI(for: .ended)
            // The server already closed the SVP session for the handoff; mark it shut down and
            // fire the switch-to-chat exit so the coordinator presents chat. The exit-callback
            // guard prevents double-firing if the user had also tapped Continue in chat.
            self.hasShutdownVoiceSession = true
            self.fireSwitchedToChatIfNeeded(agentInitiated: true)
        }
    }

    // MARK: - Mobile Renderer

    private func loadMobileRenderer() {
        guard !hasAttemptedRendererLoad else { return }
        hasAttemptedRendererLoad = true

        let rendererView = MobileRendererView(agent: agent, options: options)
        rendererView.delegate = self
        rendererView.isHidden = true
        self.renderer = rendererView

        rendererView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rendererView)

        NSLayoutConstraint.activate([
            rendererView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            rendererView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rendererView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rendererView.bottomAnchor.constraint(equalTo: controlsContainer.topAnchor),
        ])
    }

    private func ensureMobileRendererLoaded() {
        if renderer == nil {
            debugLog("AgentVoiceController: loading mobile renderer, conversationRendererURL=\(agent.config.conversationRendererURL)")
            loadMobileRenderer()
            if let renderer {
                let pending = pendingRenderableAttachmentBatches
                pendingRenderableAttachmentBatches.removeAll()
                for batch in pending {
                    renderer.pushAttachments(batch)
                }
            }
        }
    }

    // MARK: - MobileRendererDelegate

    public func mobileRenderer(_ renderer: MobileRendererView, didSendMessage text: String, attachments: [[String: Any]]) {
        debugLog("MobileRendererDelegate: didSendMessage text=\(text.isEmpty ? "(empty)" : "\"\(text.prefix(80))\""), attachments=\(attachments.count)")

        if !text.isEmpty {
            debugLog("MobileRendererDelegate: sending text_client: \(text.prefix(80))")
            voiceSession?.sendTextClient(text)
        }

        if !attachments.isEmpty {
            debugLog("MobileRendererDelegate: sending attachments_client with \(attachments.count) attachment(s)")
            voiceSession?.sendAttachmentsClient(attachments)
        }
    }

    public func mobileRenderer(_ renderer: MobileRendererView, didChangeContentHeight height: CGFloat) {
        // Layout is handled by the WebView's scroll view
    }

    public func mobileRenderer(_ renderer: MobileRendererView, didEncounterError error: Error) {
        debugLog("AgentVoiceController: renderer error: \(error)")
        rendererFailed = true
        DispatchQueue.main.async {
            self.renderer?.isHidden = true
            self.placeholderContainer.isHidden = false
        }
    }

    public func mobileRenderer(_ renderer: MobileRendererView, didClickLink url: URL) {
        if voiceCallbacks?.onLinkClick(url: url) == true {
            return
        }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    // MARK: - Navigation Bar

    private func updateNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = options.voiceStyle.titleBarColor
        appearance.titleTextAttributes = [
            .foregroundColor: options.voiceStyle.titleBarTextColor,
            .font: UIFont.systemFont(ofSize: 17, weight: .medium),
        ]
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance
        navigationItem.compactScrollEdgeAppearance = appearance
    }

    // MARK: - Placeholder UI

    private func setupWaveformPlaceholder() {
        placeholderContainer.translatesAutoresizingMaskIntoConstraints = false
        placeholderContainer.backgroundColor = .clear
        view.addSubview(placeholderContainer)

        placeholderWaveformIcon.translatesAutoresizingMaskIntoConstraints = false
        if let waveformIcon = options.voiceWaveformIcon {
            placeholderWaveformIcon.image = waveformIcon
        } else {
            placeholderWaveformIcon.image = UIImage(systemName: "waveform")
            placeholderWaveformIcon.tintColor = UIColor.systemBlue
        }
        placeholderWaveformIcon.contentMode = .scaleAspectFit
        placeholderContainer.addSubview(placeholderWaveformIcon)

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.text = options.voicePlaceholderText
        placeholderLabel.textColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 238 / 255, green: 238 / 255, blue: 238 / 255, alpha: 184 / 255)
                : UIColor(red: 17 / 255, green: 17 / 255, blue: 17 / 255, alpha: 184 / 255)
        }
        placeholderLabel.font = .systemFont(ofSize: 15, weight: .regular)
        placeholderLabel.textAlignment = .center
        placeholderContainer.addSubview(placeholderLabel)

        loadingContainer.translatesAutoresizingMaskIntoConstraints = false
        loadingContainer.backgroundColor = .clear
        placeholderContainer.addSubview(loadingContainer)

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = false
        loadingIndicator.color = options.voiceStyle.titleBarTextColor
        loadingContainer.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            placeholderContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            placeholderContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            placeholderContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            placeholderContainer.bottomAnchor.constraint(equalTo: controlsContainer.topAnchor),

            placeholderWaveformIcon.centerXAnchor.constraint(equalTo: placeholderContainer.centerXAnchor),
            placeholderWaveformIcon.centerYAnchor.constraint(equalTo: placeholderContainer.centerYAnchor, constant: -22),
            placeholderWaveformIcon.widthAnchor.constraint(equalToConstant: 36),
            placeholderWaveformIcon.heightAnchor.constraint(equalToConstant: 36),

            placeholderLabel.topAnchor.constraint(equalTo: placeholderWaveformIcon.bottomAnchor, constant: 18),
            placeholderLabel.leadingAnchor.constraint(equalTo: placeholderContainer.leadingAnchor, constant: 24),
            placeholderLabel.trailingAnchor.constraint(equalTo: placeholderContainer.trailingAnchor, constant: -24),

            loadingContainer.centerXAnchor.constraint(equalTo: placeholderContainer.centerXAnchor),
            // Align loading spinner with the waveform icon's center so the load-to-ready
            // transition has no vertical jump.
            loadingContainer.centerYAnchor.constraint(equalTo: placeholderContainer.centerYAnchor, constant: -22),
            loadingContainer.leadingAnchor.constraint(greaterThanOrEqualTo: placeholderContainer.leadingAnchor, constant: 24),
            loadingContainer.trailingAnchor.constraint(lessThanOrEqualTo: placeholderContainer.trailingAnchor, constant: -24),

            loadingIndicator.centerXAnchor.constraint(equalTo: loadingContainer.centerXAnchor),
            loadingIndicator.topAnchor.constraint(equalTo: loadingContainer.topAnchor),
            loadingIndicator.bottomAnchor.constraint(equalTo: loadingContainer.bottomAnchor),
        ])
    }

    private func setupErrorBanner() {
        errorBannerView.translatesAutoresizingMaskIntoConstraints = false
        errorBannerView.backgroundColor = UIColor(red: 242 / 255, green: 75 / 255, blue: 39 / 255, alpha: 1)
        errorBannerView.isHidden = true
        view.addSubview(errorBannerView)

        errorBannerLabel.translatesAutoresizingMaskIntoConstraints = false
        errorBannerLabel.textColor = .white
        errorBannerLabel.font = .systemFont(ofSize: 13, weight: .regular)
        errorBannerLabel.textAlignment = .center
        errorBannerLabel.numberOfLines = 2
        errorBannerView.addSubview(errorBannerLabel)

        NSLayoutConstraint.activate([
            errorBannerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            errorBannerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            errorBannerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            errorBannerView.heightAnchor.constraint(equalToConstant: 48),

            errorBannerLabel.leadingAnchor.constraint(equalTo: errorBannerView.leadingAnchor, constant: 16),
            errorBannerLabel.trailingAnchor.constraint(equalTo: errorBannerView.trailingAnchor, constant: -16),
            errorBannerLabel.centerYAnchor.constraint(equalTo: errorBannerView.centerYAnchor),
        ])
    }

    // MARK: - Bottom Controls

    private func setupBottomControls() {
        controlsContainer.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.backgroundColor = .clear
        view.addSubview(controlsContainer)

        let muteButton = options.muteButton ?? defaultMuteButton()
        let unmuteButton = options.unmuteButton ?? defaultUnmuteButton()
        let endCallButton = options.endCallButton ?? defaultEndCallButton()
        let buttonsStack = makeControlButtonsStack(
            muteButton: muteButton,
            unmuteButton: unmuteButton,
            endButton: endCallButton
        )
        configureControlsLayout(buttonsStack: buttonsStack)
    }

    private func defaultMuteButton() -> UIButton {
        let muteButtonColor = options.voiceStyle.muteButtonColor ?? defaultMutePillBackgroundColor
        return MuteButtonPill(
            backgroundColor: muteButtonColor,
            iconColor: defaultMuteButtonIconColor(for: muteButtonColor),
            muteIcon: options.muteIcon,
            waveformIcon: nil
        )
    }

    private func defaultUnmuteButton() -> UIButton {
        let muteButtonColor = options.voiceStyle.muteButtonColor ?? defaultMutePillBackgroundColor
        return UnmuteButtonPill(
            backgroundColor: muteButtonColor,
            unmuteIcon: options.mutedIcon
        )
    }

    private func defaultMuteButtonIconColor(for backgroundColor: UIColor) -> UIColor {
        let configuredIconColor = options.voiceStyle.muteButtonIconColor
        guard
            options.voiceStyle.muteButtonColor != nil,
            configuredIconColor.matches(defaultMutePillIconColor, using: traitCollection)
        else {
            return configuredIconColor
        }
        return backgroundColor.contrastingBlackOrWhite(using: traitCollection)
    }

    private func defaultEndCallButton() -> UIButton {
        let endConversationButtonColor = options.voiceStyle.endConversationButtonColor ?? UIColor(red: 242 / 255, green: 75 / 255, blue: 39 / 255, alpha: 1)
        return EndCallButtonPill(
            backgroundColor: endConversationButtonColor,
            iconColor: options.voiceStyle.endConversationButtonIconColor,
            icon: options.endConversationIcon
        )
    }

    private func makeControlButtonsStack(
        muteButton: UIButton,
        unmuteButton: UIButton,
        endButton: UIButton
    ) -> UIStackView {
        muteButton.addTarget(self, action: #selector(muteTapped), for: .touchUpInside)
        unmuteButton.addTarget(self, action: #selector(muteTapped), for: .touchUpInside)
        endButton.addTarget(self, action: #selector(endTapped), for: .touchUpInside)

        self.muteButton = muteButton
        self.unmuteButton = unmuteButton
        self.endButton = endButton
        muteLevelDisplay = muteButton as? VoiceMuteLevelDisplaying

        let buttonsStack = UIStackView()
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false
        buttonsStack.axis = .horizontal
        buttonsStack.alignment = .center
        if usesLegacyControls(muteButton: muteButton, unmuteButton: unmuteButton, endButton: endButton) {
            buttonsStack.distribution = .fill
            buttonsStack.spacing = 28
            shouldNormalButtonsFillMessageRail = false
        } else {
            buttonsStack.distribution = .fillEqually
            buttonsStack.spacing = pillControlsSpacing
            shouldNormalButtonsFillMessageRail = true
        }
        if let controlsDistribution = options.controlsDistribution {
            buttonsStack.distribution = controlsDistribution
            shouldNormalButtonsFillMessageRail = false
        }
        if let controlsSpacing = options.controlsSpacing {
            buttonsStack.spacing = controlsSpacing
        }
        buttonsStack.addArrangedSubview(makeMuteToggleContainer(muteButton: muteButton, unmuteButton: unmuteButton))
        buttonsStack.addArrangedSubview(endButton)
        updateMuteControl(isMuted: false)
        normalButtonsStack = buttonsStack
        return buttonsStack
    }

    private func usesLegacyControls(muteButton: UIButton, unmuteButton: UIButton, endButton: UIButton) -> Bool {
        muteButton is MuteButtonLegacy ||
            unmuteButton is UnmuteButtonLegacy ||
            endButton is EndCallButtonLegacy
    }

    private func makeMuteToggleContainer(muteButton: UIButton, unmuteButton: UIButton) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        for button in [muteButton, unmuteButton] {
            container.addSubview(button)
            NSLayoutConstraint.activate([
                button.topAnchor.constraint(equalTo: container.topAnchor),
                button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }

        return container
    }

    private func makeCompactControlButtonsStack() -> UIStackView {
        let muteButton = options.compactMuteButton ?? defaultCompactMuteButton()
        let unmuteButton = options.compactUnmuteButton ?? defaultCompactUnmuteButton()
        let endButton = options.compactEndCallButton ?? defaultCompactEndCallButton()

        muteButton.addTarget(self, action: #selector(muteTapped), for: .touchUpInside)
        unmuteButton.addTarget(self, action: #selector(muteTapped), for: .touchUpInside)
        endButton.addTarget(self, action: #selector(endTapped), for: .touchUpInside)

        compactMuteButton = muteButton
        compactUnmuteButton = unmuteButton
        compactEndButton = endButton
        compactMuteLevelDisplay = muteButton as? VoiceMuteLevelDisplaying

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = compactControlsSpacing
        let muteToggleContainer = makeMuteToggleContainer(muteButton: muteButton, unmuteButton: unmuteButton)
        muteToggleContainer.setContentHuggingPriority(.required, for: .horizontal)
        muteToggleContainer.setContentCompressionResistancePriority(.required, for: .horizontal)
        endButton.setContentHuggingPriority(.required, for: .horizontal)
        endButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        stack.addArrangedSubview(muteToggleContainer)
        stack.addArrangedSubview(endButton)
        compactButtonsStack = stack
        updateMuteControl(isMuted: isMuted)
        return stack
    }

    private func defaultCompactMuteButton() -> UIButton {
        let muteButtonColor = options.voiceStyle.muteButtonColor ?? defaultMutePillBackgroundColor
        return MuteButtonPill(
            backgroundColor: muteButtonColor,
            iconColor: defaultMuteButtonIconColor(for: muteButtonColor),
            muteIcon: options.muteIcon,
            layout: .compact
        )
    }

    private func defaultCompactUnmuteButton() -> UIButton {
        let muteButtonColor = options.voiceStyle.muteButtonColor ?? defaultMutePillBackgroundColor
        return UnmuteButtonPill(
            backgroundColor: muteButtonColor,
            unmuteIcon: options.mutedIcon,
            title: "Unmute",
            layout: .compact
        )
    }

    private func defaultCompactEndCallButton() -> UIButton {
        let endConversationButtonColor = options.voiceStyle.endConversationButtonColor ?? UIColor(red: 242 / 255, green: 75 / 255, blue: 39 / 255, alpha: 1)
        return EndCallButtonPill(
            backgroundColor: endConversationButtonColor,
            iconColor: options.voiceStyle.endConversationButtonIconColor,
            icon: options.endConversationIcon,
            layout: .compact
        )
    }

    private func configureControlsLayout(buttonsStack: UIStackView) {
        disclosureLabel.translatesAutoresizingMaskIntoConstraints = false
        disclosureLabel.text = options.disclosureText
        disclosureLabel.textColor = options.voiceStyle.conversationDisclosureTextColor
        disclosureLabel.font = options.voiceStyle.conversationDisclosureFont
        disclosureLabel.textAlignment = .center
        disclosureLabel.numberOfLines = 0
        disclosureLabel.isHidden = options.disclosureText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        let controlsBottomPadding: CGFloat = disclosureLabel.isHidden ? 18 : 4

        let controlsStack = UIStackView()
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        controlsStack.axis = .vertical
        controlsStack.alignment = .center
        controlsStack.spacing = 12
        controlsContainer.addSubview(controlsStack)

        if options.enableTextInput {
            let composer = makeTextComposerView()
            let compactControls = makeCompactControlButtonsStack()
            let editingRow = UIStackView(arrangedSubviews: [composer, compactControls])
            editingRow.translatesAutoresizingMaskIntoConstraints = false
            editingRow.axis = .horizontal
            editingRow.alignment = .center
            editingRow.spacing = compactComposerControlsSpacing
            composer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            composer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            compactControls.setContentHuggingPriority(.required, for: .horizontal)
            compactControls.setContentCompressionResistancePriority(.required, for: .horizontal)
            compactControls.isHidden = true
            controlsStack.addArrangedSubview(editingRow)
            editingRow.widthAnchor.constraint(equalTo: controlsStack.widthAnchor).isActive = true
        }
        controlsStack.addArrangedSubview(buttonsStack)
        controlsStack.addArrangedSubview(disclosureLabel)

        let controlsBottomConstraint: NSLayoutConstraint
        if options.enableTextInput, #available(iOS 15.0, *) {
            controlsBottomConstraint = controlsContainer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        } else {
            controlsBottomConstraint = controlsContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        }

        NSLayoutConstraint.activate([
            controlsContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlsBottomConstraint,

            controlsStack.topAnchor.constraint(equalTo: controlsContainer.topAnchor, constant: 16),
            controlsStack.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor, constant: messageRailHorizontalInset),
            controlsStack.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor, constant: -messageRailHorizontalInset),
            controlsStack.bottomAnchor.constraint(equalTo: controlsContainer.bottomAnchor, constant: -controlsBottomPadding),
            shouldNormalButtonsFillMessageRail
                ? buttonsStack.widthAnchor.constraint(equalTo: controlsStack.widthAnchor)
                : buttonsStack.widthAnchor.constraint(lessThanOrEqualTo: controlsStack.widthAnchor),

            disclosureLabel.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor, constant: 24),
            disclosureLabel.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor, constant: -24),
        ])
        updateTextComposerEditingState(isEditing: false)
    }

    private func makeTextComposerView() -> UIView {
        let composer = options.textComposerView ?? VoiceTextComposerView(
            placeholder: options.textComposerPlaceholder,
            sendButtonTintColor: options.voiceStyle.textComposerSendButtonTintColor ?? options.voiceStyle.messageColors.userBubble
        )
        composer.onEditingChanged = { [weak self] isEditing in
            self?.updateTextComposerEditingState(isEditing: isEditing)
        }
        composer.onSend = { [weak self] in
            self?.sendComposerText()
        }
        textComposerView = composer
        return composer
    }

    private func updateTextComposerEditingState(isEditing: Bool) {
        guard options.enableTextInput else { return }
        compactButtonsStack?.isHidden = !isEditing
        normalButtonsStack?.isHidden = isEditing
        disclosureLabel.isHidden = isEditing || (options.disclosureText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        if isEditing && !isMuted {
            compactMuteLevelDisplay?.setInputLevel(latestInputAudioLevel)
            compactMuteLevelDisplay?.setOutputLevel(latestOutputAudioLevel)
        } else {
            compactMuteLevelDisplay?.resetLevels()
        }
    }

    private func updateMuteControl(isMuted: Bool) {
        muteButton?.isHidden = isMuted
        unmuteButton?.isHidden = !isMuted
        compactMuteButton?.isHidden = isMuted
        compactUnmuteButton?.isHidden = !isMuted
        if isMuted {
            muteLevelDisplay?.resetLevels()
            compactMuteLevelDisplay?.resetLevels()
        } else {
            muteLevelDisplay?.setInputLevel(latestInputAudioLevel)
            muteLevelDisplay?.setOutputLevel(latestOutputAudioLevel)
            if compactButtonsStack?.isHidden == false {
                compactMuteLevelDisplay?.setInputLevel(latestInputAudioLevel)
                compactMuteLevelDisplay?.setOutputLevel(latestOutputAudioLevel)
            }
        }
    }

    private func updateUI(for state: VoiceSessionManager.State) {
        switch state {
        case .connecting:
            setControlButtonsEnabled(true)
            setLoadingStateVisible(!hasReceivedInitialGreeting)
            cancelInitialGreetingFallback()
            stopWaveformAnimation()
        case .listening:
            setLoadingStateVisible(!hasReceivedInitialGreeting)
            scheduleInitialGreetingFallbackIfNeeded()
            setControlButtonsEnabled(true)
            stopWaveformAnimation()
        case .speaking:
            setLoadingStateVisible(!hasReceivedInitialGreeting)
            cancelInitialGreetingFallback()
            setControlButtonsEnabled(true)
            startWaveformAnimation()
        case .ended:
            setLoadingStateVisible(false)
            cancelInitialGreetingFallback()
            latestInputAudioLevel = 0
            latestOutputAudioLevel = 0
            stopWaveformAnimation()
            muteLevelDisplay?.resetLevels()
            compactMuteLevelDisplay?.resetLevels()
            setControlButtonsEnabled(false)
        }
    }

    private func setControlButtonsEnabled(_ enabled: Bool) {
        let alpha: CGFloat = enabled ? 1.0 : 0.5
        for button in [muteButton, unmuteButton, endButton, compactMuteButton, compactUnmuteButton, compactEndButton].compactMap({ $0 }) {
            button.isEnabled = enabled
            button.alpha = alpha
        }
        textComposerView?.setEnabled(enabled && options.enableTextInput)
        navigationItem.rightBarButtonItem?.isEnabled = enabled
    }

    private func showErrorState(message: String) {
        DispatchQueue.main.async {
            self.latestInputAudioLevel = 0
            self.latestOutputAudioLevel = 0
            self.stopWaveformAnimation()
            self.muteLevelDisplay?.resetLevels()
            self.compactMuteLevelDisplay?.resetLevels()
            self.shutdownVoiceSessionIfNeeded()
            self.showErrorBanner(message: message)

            if self.hasShownFirstAttachment {
                // Keep the existing renderer content visible if the call drops mid-conversation.
                self.renderer?.isHidden = false
                self.placeholderContainer.isHidden = true
            } else {
                // Failure before initial response: show a clean canvas behind the error banner.
                self.renderer?.isHidden = true
                self.placeholderContainer.isHidden = true
            }

            self.setLoadingStateVisible(false)
            self.setControlButtonsEnabled(false)
        }
    }

    private func showErrorBanner(message: String) {
        errorBannerLabel.text = message
        errorBannerView.isHidden = false
        view.bringSubviewToFront(errorBannerView)
    }

    private func userFacingErrorMessage(for error: Error) -> String {
        return "Voice connection failed: Please check your credentials or try again later"
    }

    private func isExternalAudioInterruptionError(_ error: Error) -> Bool {
        var currentError: NSError? = error as NSError
        while let nsError = currentError {
            let domain = nsError.domain.lowercased()
            let isAudioRelatedDomain =
                domain.contains("audio") ||
                domain.contains("avfoundation") ||
                domain.contains("avaudiosession")

            if isAudioRelatedDomain,
               let code = AVAudioSession.ErrorCode(rawValue: nsError.code),
               (code == .cannotInterruptOthers || code == .insufficientPriority) {
                return true
            }

            if isAudioRelatedDomain {
                let message = nsError.localizedDescription.lowercased()
                if message.contains("interruption") || message.contains("cannot interrupt others") {
                    return true
                }
            }

            currentError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    public func endConversation(closeReason: AgentVoiceCloseReason = .normal) {
        endConversationForExit(closeReason: closeReason)
    }

    private func endConversationForExit(closeReason: AgentVoiceCloseReason = .normal) {
        guard !hasShutdownVoiceSession else { return }
        shutdownVoiceSessionIfNeeded(closeReason: closeReason)
        fireEndedIfNeeded()
    }

    private enum ExitCallbackFired {
        case none, ended, dismissed, switchedToChat
    }
    private var exitCallbackFired: ExitCallbackFired = .none

    private func fireEndedIfNeeded() {
        guard exitCallbackFired == .none else { return }
        exitCallbackFired = .ended
        voiceCallbacks?.onVoiceEnded()
    }

    private func fireDismissedIfNeeded() {
        guard exitCallbackFired == .none else { return }
        exitCallbackFired = .dismissed
        voiceCallbacks?.onVoiceDismissed()
    }

    private func fireSwitchedToChatIfNeeded(agentInitiated: Bool) {
        guard exitCallbackFired == .none else { return }
        exitCallbackFired = .switchedToChat
        options.onSwitchToChat?(agentInitiated)
    }

    private func dismissVoiceController() {
        if let navigationController, navigationController.topViewController === self {
            if navigationController.viewControllers.count > 1 {
                navigationController.popViewController(animated: true)
            } else if navigationController.presentingViewController != nil {
                navigationController.dismiss(animated: true)
            } else {
                dismiss(animated: true)
            }
            return
        }

        if presentingViewController != nil {
            dismiss(animated: true)
        } else {
            navigationController?.dismiss(animated: true)
        }
    }

    private func startWaveformAnimation() {
        // A customer-supplied waveform is rendered as-provided, so it is not animated.
        guard options.voiceWaveformIcon == nil else { return }
        guard !placeholderContainer.isHidden else { return }
        guard placeholderWaveformIcon.layer.animation(forKey: "pulse") == nil else { return }
        let anim = CABasicAnimation(keyPath: "transform.scale")
        anim.fromValue = 1.0
        anim.toValue = 1.06
        anim.duration = 0.9
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        placeholderWaveformIcon.layer.add(anim, forKey: "pulse")
    }

    private func stopWaveformAnimation() {
        placeholderWaveformIcon.layer.removeAnimation(forKey: "pulse")
    }

    private func markInitialGreetingReceivedIfNeeded() {
        guard !hasReceivedInitialGreeting else { return }
        hasReceivedInitialGreeting = true
        cancelInitialGreetingFallback()
        setLoadingStateVisible(false)
    }

    private func scheduleInitialGreetingFallbackIfNeeded() {
        guard !hasReceivedInitialGreeting, !hasReceivedInitialAudioMessage, initialGreetingFallbackWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.markInitialGreetingReceivedIfNeeded()
        }
        initialGreetingFallbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + initialGreetingFallbackDelay, execute: workItem)
    }

    private func cancelInitialGreetingFallback() {
        initialGreetingFallbackWorkItem?.cancel()
        initialGreetingFallbackWorkItem = nil
    }

    private func setLoadingStateVisible(_ visible: Bool) {
        loadingContainer.isHidden = !visible
        placeholderWaveformIcon.isHidden = visible
        placeholderLabel.isHidden = visible
        if visible {
            stopWaveformAnimation()
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
        }
    }

    @objc private func muteTapped() {
        isMuted.toggle()
        debugLog("AgentVoiceController: mute toggled -> \(isMuted ? "muted" : "unmuted")")
        if isMuted {
            voiceSession?.pauseListening()
            latestInputAudioLevel = 0
            muteLevelDisplay?.setInputLevel(0)
            compactMuteLevelDisplay?.setInputLevel(0)
        } else {
            voiceSession?.resumeListening()
        }
        updateMuteControl(isMuted: isMuted)
    }

    @objc private func endTapped() {
        if options.endRoutesToChat {
            switchToChatTapped()
            return
        }
        endConversation()
    }

    @objc private func switchToChatTapped() {
        shutdownVoiceSessionIfNeeded(closeReason: .continueInChat)
        fireSwitchedToChatIfNeeded(agentInitiated: false)
    }

    private func sendComposerText() {
        guard options.enableTextInput else { return }
        let text = (textComposerView?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard voiceSession?.sendTextClient(text) == true else {
            debugLog("AgentVoiceController: text_client send skipped; voice session is not connected")
            return
        }
        textComposerView?.text = ""
    }
}

/// Callbacks for voice session lifecycle events.
///
/// Inherits from `AgentEventListener` so that events emitted by the agent
/// runtime (e.g. `onSecretExpiry`, `onLinkClick`) can be implemented once and
/// satisfy both voice and chat surfaces.
public protocol VoiceCallbacks: AgentEventListener {
    /// Called when the user explicitly ends the voice session (e.g., taps the End button).
    /// Mutually exclusive with `onVoiceDismissed()` -- only one fires per controller lifetime.
    func onVoiceEnded()

    /// Called when the voice view is dismissed without an explicit End tap,
    /// e.g. the user navigates back, the controller is deallocated, or an error
    /// state is dismissed. Mutually exclusive with `onVoiceEnded()`.
    func onVoiceDismissed()

    func onVoiceError(error: Error)
    func didReceiveAgentAttachment(attachments: [AgentAttachment])
    func onSessionInfoReceived(conversationID: String, encryptionKey: String)
    func onResumeTokenReceived(token: String)
}

public extension VoiceCallbacks {
    func onVoiceDismissed() {}
    func didReceiveAgentAttachment(attachments: [AgentAttachment]) {}
    func onSessionInfoReceived(conversationID: String, encryptionKey: String) {}
    func onResumeTokenReceived(token: String) {}
}

private extension UIColor {
    func matches(_ other: UIColor, using traitCollection: UITraitCollection) -> Bool {
        guard
            let lhs = rgbaComponents(using: traitCollection),
            let rhs = other.rgbaComponents(using: traitCollection)
        else {
            return false
        }
        let tolerance: CGFloat = 0.001
        return abs(lhs.red - rhs.red) < tolerance &&
            abs(lhs.green - rhs.green) < tolerance &&
            abs(lhs.blue - rhs.blue) < tolerance &&
            abs(lhs.alpha - rhs.alpha) < tolerance
    }

    func contrastingBlackOrWhite(using traitCollection: UITraitCollection) -> UIColor {
        guard let components = rgbaComponents(using: traitCollection) else {
            return defaultMutePillIconColor
        }
        let luminance = relativeLuminance(red: components.red, green: components.green, blue: components.blue)
        let whiteContrast = (1.0 + 0.05) / (luminance + 0.05)
        let blackContrast = (luminance + 0.05) / 0.05
        return whiteContrast > blackContrast ? .white : defaultMutePillIconColor
    }

    private func rgbaComponents(using traitCollection: UITraitCollection) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard resolvedColor(with: traitCollection).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        return (red, green, blue, alpha)
    }

    private func relativeLuminance(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGFloat {
        func linearized(_ component: CGFloat) -> CGFloat {
            component <= 0.03928
                ? component / 12.92
                : CGFloat(pow(Double((component + 0.055) / 1.055), 2.4))
        }
        return 0.2126 * linearized(red) + 0.7152 * linearized(green) + 0.0722 * linearized(blue)
    }
}
