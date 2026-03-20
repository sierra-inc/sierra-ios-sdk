// Copyright Sierra

import UIKit
import AVFoundation

@_spi(ExperimentalVoice)
public struct AgentVoiceStyle {
    /// Background color for the native voice screen.
    public var backgroundColor: UIColor

    /// Background color for the native navigation bar.
    public var titleBarColor: UIColor

    /// Text/icon color for the native navigation bar.
    public var titleBarTextColor: UIColor

    /// Fill color for the mute/end controls.
    public var controlsColor: UIColor

    /// Optional override for the mobile renderer background color.
    /// When nil, the renderer falls back to `backgroundColor`.
    public var rendererBackgroundColor: UIColor?

    public init(
        backgroundColor: UIColor = .systemBackground,
        titleBarColor: UIColor = .systemBackground,
        titleBarTextColor: UIColor = .label,
        controlsColor: UIColor = UIColor(red: 16 / 255, green: 34 / 255, blue: 76 / 255, alpha: 1),
        rendererBackgroundColor: UIColor? = nil
    ) {
        self.backgroundColor = backgroundColor
        self.titleBarColor = titleBarColor
        self.titleBarTextColor = titleBarTextColor
        self.controlsColor = controlsColor
        self.rendererBackgroundColor = rendererBackgroundColor
    }
}

/// Configuration for `AgentVoiceController`.
@_spi(ExperimentalVoice)
public struct AgentVoiceControllerOptions {
    /// Name for this voice agent, displayed as the navigation item title.
    public let name: String

    /// Optional override for the navigation bar title.
    public var titleBarMessage: String?

    /// Customize the look and feel of native voice UI elements.
    public var voiceStyle: AgentVoiceStyle = AgentVoiceStyle()

    /// Text shown in the native voice waveform placeholder before the first
    /// renderable attachment is displayed.
    public var voicePlaceholderText: String = "How can I help you today?"

    /// Optional key/value pairs to include in SVP `open.subMsg.agentParameters`.
    /// These values are treated as secrets by the voice backend and should be
    /// used for sensitive runtime context needed at voice start.
    public var voiceAgentParameters: [String: String]?

    /// When true, mutes microphone capture while the agent is speaking.
    /// Prevents speaker audio from being picked up by the mic and
    /// misinterpreted as a user interruption.
    public var disableInterruptions: Bool = false

    public init(name: String) {
        self.name = name
        self.titleBarMessage = nil
    }

    @available(*, deprecated, message: "Use voiceAgentParameters instead.")
    public var voiceAgentSecrets: [String: String]? {
        get { voiceAgentParameters }
        set { voiceAgentParameters = newValue }
    }

}

/// Displays a native voice conversation with an embedded WebView for rendering
/// agent attachments. Voice audio is handled natively via VoiceSessionManager
/// (SVP WebSocket), while attachments are rendered by a MobileRendererView
/// that loads the agent's web bundle directly -- no conversation state, no
/// credential seeding, no refresh polling.
@_spi(ExperimentalVoice)
public class AgentVoiceController: UIViewController, VoiceSessionDelegate, MobileRendererDelegate {
    private let agent: Agent
    private var options: AgentVoiceControllerOptions
    private var voiceSession: VoiceSessionManager?
    private var renderer: MobileRendererView?
    private var hasShownFirstAttachment = false
    private var rendererFailed = false
    private var hasAttemptedRendererLoad = false
    private var pendingRenderableAttachmentBatches: [[[String: Any]]] = []
    private var lastRenderableAttachmentsSignature: String?
    private var isMuted = false

    private let placeholderContainer = UIView()
    private let placeholderWaveformIcon = UIImageView()
    private let placeholderLabel = UILabel()
    private let loadingContainer = UIView()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let errorBannerView = UIView()
    private let errorBannerLabel = UILabel()

    private let muteButton = UIButton(type: .system)
    private let endButton = UIButton(type: .system)
    private let controlsContainer = UIView()
    private var hasShutdownVoiceSession = false
    private var hasReceivedInitialGreeting = false

    public weak var voiceCallbacks: VoiceCallbacks?

    public init(agent: Agent, options: AgentVoiceControllerOptions = AgentVoiceControllerOptions(name: "Voice Agent")) {
        self.agent = agent
        self.options = options
        let trimmedTitleBarMessage = options.titleBarMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (trimmedTitleBarMessage?.isEmpty == false) ? trimmedTitleBarMessage! : options.name
        super.init(nibName: nil, bundle: nil)
        navigationItem.title = title
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

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        voiceSession?.resumeListening()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if shouldShutdownVoiceSessionOnDisappear {
            shutdownVoiceSessionIfNeeded()
        }
    }

    deinit {
        shutdownVoiceSessionIfNeeded()
    }

    // MARK: - Voice Session

    private func startVoiceSession() {
        let voiceAgentParameters = options.voiceAgentParameters ?? [:]
        let session = VoiceSessionManager(
            config: agent.config,
            disableInterruptions: options.disableInterruptions,
            agentParameters: voiceAgentParameters,
            delegate: self
        )
        self.voiceSession = session
        session.connect()
        updateUI(for: .connecting)
    }

    private func shutdownVoiceSessionIfNeeded() {
        guard !hasShutdownVoiceSession else { return }
        hasShutdownVoiceSession = true
        voiceSession?.disconnect()
        voiceSession = nil
    }

    private var shouldShutdownVoiceSessionOnDisappear: Bool {
        isBeingDismissed || isMovingFromParent || navigationController?.isBeingDismissed == true
    }

    // MARK: - VoiceSessionDelegate

    public func voiceSession(_ session: VoiceSessionManager, didReceiveCredentials conversationID: String, encryptionKey: String) {
        debugLog("Voice session received credentials: conversationID=\(conversationID)")
    }

    public func voiceSession(_ session: VoiceSessionManager, didChangeState state: VoiceSessionManager.State) {
        DispatchQueue.main.async {
            self.updateUI(for: state)
        }
    }

    public func voiceSession(_ session: VoiceSessionManager, didReceiveAttachments attachments: [[String: Any]]) {
        if !attachments.isEmpty {
            DispatchQueue.main.async {
                self.markInitialGreetingReceivedIfNeeded()
            }
        }

        let attachmentTypes = attachments.compactMap { $0["type"] as? String }
        debugLog(
            "AgentVoiceController: received \(attachments.count) attachment(s) from SVP, types=\(attachmentTypes), renderer=\(renderer != nil ? "ready" : "nil")"
        )

        var renderableAttachments: [[String: Any]] = []

        for attachment in attachments {
            let attType = attachment["type"] as? String ?? ""

            if attType == "message",
               let data = attachment["data"] as? [String: Any],
               let text = data["text"] as? String,
               !text.isEmpty {
                debugLog("AgentVoiceController: message attachment -> text_client: \(text.prefix(80))")
                voiceSession?.sendTextClient(text)
            } else if attType == "custom",
                      let data = attachment["data"] as? [String: Any],
                      let dataType = data["type"] as? String,
                      dataType == "send-client-message",
                      let message = data["message"] as? String,
                      !message.isEmpty {
                debugLog("AgentVoiceController: send-client-message -> text_client: \(message.prefix(80))")
                voiceSession?.sendTextClient(message)
            } else {
                renderableAttachments.append(attachment)
            }
        }

        if !renderableAttachments.isEmpty {
            let signature = renderableBatchSignature(renderableAttachments)
            if let signature, signature == lastRenderableAttachmentsSignature {
                debugLog("AgentVoiceController: dropping duplicate renderable attachment batch")
                return
            }
            lastRenderableAttachmentsSignature = signature

            DispatchQueue.main.async {
                if self.rendererFailed {
                    return
                }

                // Lazily load the renderer so voice startup/UI presentation is never blocked by WebView load.
                self.ensureMobileRendererLoaded()
                if self.rendererFailed {
                    return
                }

                if !self.hasShownFirstAttachment {
                    self.hasShownFirstAttachment = true
                    self.placeholderContainer.isHidden = true
                    self.renderer?.isHidden = false
                }

                if let renderer = self.renderer {
                    renderer.pushAttachments(renderableAttachments)
                } else {
                    self.pendingRenderableAttachmentBatches.append(renderableAttachments)
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
            self.voiceCallbacks?.onVoiceEnded()
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

        var forwardAttachments: [[String: Any]] = []
        for attachment in attachments {
            let attType = attachment["type"] as? String ?? ""
            if attType == "custom",
               let data = attachment["data"] as? [String: Any],
               let dataType = data["type"] as? String,
               dataType == "send-client-message",
               let message = data["message"] as? String,
               !message.isEmpty {
                debugLog("MobileRendererDelegate: send-client-message -> text_client: \(message.prefix(80))")
                voiceSession?.sendTextClient(message)
            } else {
                forwardAttachments.append(attachment)
            }
        }

        if !forwardAttachments.isEmpty {
            debugLog("MobileRendererDelegate: sending attachments_client with \(forwardAttachments.count) attachment(s)")
            voiceSession?.sendAttachmentsClient(forwardAttachments)
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
        placeholderWaveformIcon.image = UIImage(systemName: "waveform")
        placeholderWaveformIcon.tintColor = UIColor.systemBlue
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
            loadingContainer.centerYAnchor.constraint(equalTo: placeholderContainer.centerYAnchor),
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

    private let controlButtonSize: CGFloat = 56

    private func setupBottomControls() {
        controlsContainer.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.backgroundColor = .clear
        view.addSubview(controlsContainer)

        let controlsColor = options.voiceStyle.controlsColor

        muteButton.translatesAutoresizingMaskIntoConstraints = false
        muteButton.setImage(UIImage(systemName: "mic.fill"), for: .normal)
        muteButton.tintColor = .white
        muteButton.backgroundColor = controlsColor
        muteButton.layer.cornerRadius = controlButtonSize / 2
        muteButton.clipsToBounds = true
        muteButton.addTarget(self, action: #selector(muteTapped), for: .touchUpInside)
        controlsContainer.addSubview(muteButton)

        endButton.translatesAutoresizingMaskIntoConstraints = false
        endButton.setImage(UIImage(systemName: "phone.down.fill"), for: .normal)
        endButton.tintColor = .white
        endButton.backgroundColor = controlsColor
        endButton.layer.cornerRadius = controlButtonSize / 2
        endButton.clipsToBounds = true
        endButton.addTarget(self, action: #selector(endTapped), for: .touchUpInside)
        controlsContainer.addSubview(endButton)

        NSLayoutConstraint.activate([
            controlsContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlsContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            controlsContainer.heightAnchor.constraint(equalToConstant: controlButtonSize + 32),

            muteButton.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor),
            muteButton.trailingAnchor.constraint(equalTo: controlsContainer.centerXAnchor, constant: -14),
            muteButton.widthAnchor.constraint(equalToConstant: controlButtonSize),
            muteButton.heightAnchor.constraint(equalToConstant: controlButtonSize),

            endButton.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor),
            endButton.leadingAnchor.constraint(equalTo: controlsContainer.centerXAnchor, constant: 14),
            endButton.widthAnchor.constraint(equalToConstant: controlButtonSize),
            endButton.heightAnchor.constraint(equalToConstant: controlButtonSize),
        ])
    }

    private func updateUI(for state: VoiceSessionManager.State) {
        switch state {
        case .connecting:
            muteButton.isEnabled = true
            muteButton.alpha = 1.0
            endButton.isEnabled = true
            endButton.alpha = 1.0
            setLoadingStateVisible(!hasReceivedInitialGreeting)
            stopWaveformAnimation()
        case .listening:
            markInitialGreetingReceivedIfNeeded()
            muteButton.isEnabled = true
            muteButton.alpha = 1.0
            endButton.isEnabled = true
            endButton.alpha = 1.0
            stopWaveformAnimation()
        case .speaking:
            markInitialGreetingReceivedIfNeeded()
            muteButton.isEnabled = true
            muteButton.alpha = 1.0
            endButton.isEnabled = true
            endButton.alpha = 1.0
            startWaveformAnimation()
        case .ended:
            markInitialGreetingReceivedIfNeeded()
            stopWaveformAnimation()
            muteButton.isEnabled = false
            muteButton.alpha = 0.5
            endButton.isEnabled = false
            endButton.alpha = 0.5
        }
    }

    private func showErrorState(message: String) {
        DispatchQueue.main.async {
            self.stopWaveformAnimation()
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

            self.loadingIndicator.stopAnimating()

            self.muteButton.isEnabled = false
            self.muteButton.alpha = 0.5
            self.endButton.isEnabled = false
            self.endButton.alpha = 0.5
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

    private func endConversationForExit() {
        guard !hasShutdownVoiceSession else { return }
        shutdownVoiceSessionIfNeeded()
        voiceCallbacks?.onVoiceEnded()
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
        setLoadingStateVisible(false)
    }

    private func setLoadingStateVisible(_ visible: Bool) {
        loadingContainer.isHidden = !visible
        placeholderWaveformIcon.isHidden = visible
        placeholderLabel.isHidden = visible
        if visible {
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
            muteButton.setImage(UIImage(systemName: "mic.slash.fill"), for: .normal)
        } else {
            voiceSession?.resumeListening()
            muteButton.setImage(UIImage(systemName: "mic.fill"), for: .normal)
        }
    }

    @objc private func endTapped() {
        endConversationForExit()
    }
}

/// Callbacks for voice session lifecycle events.
@_spi(ExperimentalVoice)
public protocol VoiceCallbacks: AnyObject {
    func onVoiceEnded()
    func onVoiceError(error: Error)
}
