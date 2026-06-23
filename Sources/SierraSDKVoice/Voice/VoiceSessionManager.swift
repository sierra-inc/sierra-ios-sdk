// Copyright Sierra

import AVFoundation
import Foundation
import SierraSDK

/// Ordered transcript event projected by SVP conversation events.
public struct AgentVoiceConversationEvent {
    public let messageId: String
    public let eventType: String
    public let role: String
    public let text: String
    public let attachments: [[String: Any]]

    public init(messageId: String, eventType: String, role: String, text: String = "", attachments: [[String: Any]] = []) {
        self.messageId = messageId
        self.eventType = eventType
        self.role = role
        self.text = text
        self.attachments = attachments
    }

    fileprivate init?(raw: [String: Any]) {
        guard
            let messageId = raw["messageId"] as? String,
            let eventType = raw["eventType"] as? String,
            let role = raw["role"] as? String
        else {
            return nil
        }
        self.init(
            messageId: messageId,
            eventType: eventType,
            role: role,
            text: raw["text"] as? String ?? "",
            attachments: raw["attachments"] as? [[String: Any]] ?? []
        )
    }
}

/// Defines callbacks emitted by `VoiceSessionManager` during a voice session lifecycle.
///
/// Implementers are notified about:
/// - state transitions for the active voice session
/// - credentials/session metadata required by the host
/// - incoming attachment payloads from the server
/// - terminal events and surfaced errors
public protocol VoiceSessionDelegate: AnyObject {
    func voiceSession(_ session: VoiceSessionManager, didReceiveCredentials conversationID: String, encryptionKey: String)
    func voiceSession(_ session: VoiceSessionManager, didReceiveAttachments attachments: [[String: Any]])
    func voiceSession(_ session: VoiceSessionManager, didReceiveConversationEvent event: AgentVoiceConversationEvent)
    func voiceSessionDidReceiveInitialAudio(_ session: VoiceSessionManager)
    func voiceSessionDidStartInitialAudioPlayback(_ session: VoiceSessionManager)
    func voiceSession(_ session: VoiceSessionManager, didChangeState state: VoiceSessionManager.State)
    func voiceSession(_ session: VoiceSessionManager, didEncounterError error: Error)
    func voiceSessionDidEnd(_ session: VoiceSessionManager)
    func voiceSessionDidRequestContinueInChat(_ session: VoiceSessionManager)
    func voiceSession(_ session: VoiceSessionManager, didReceiveResumeToken token: String)
    func voiceSession(_ session: VoiceSessionManager, didUpdateInputAudioLevel level: Float)
    func voiceSession(_ session: VoiceSessionManager, didUpdateOutputAudioLevel level: Float)
}

public extension VoiceSessionDelegate {
    func voiceSession(_ session: VoiceSessionManager, didReceiveConversationEvent event: AgentVoiceConversationEvent) {}
    func voiceSessionDidReceiveInitialAudio(_ session: VoiceSessionManager) {}
    func voiceSessionDidStartInitialAudioPlayback(_ session: VoiceSessionManager) {}
    func voiceSessionDidRequestContinueInChat(_ session: VoiceSessionManager) {}
    func voiceSession(_ session: VoiceSessionManager, didReceiveResumeToken token: String) {}
    func voiceSession(_ session: VoiceSessionManager, didUpdateInputAudioLevel level: Float) {}
    func voiceSession(_ session: VoiceSessionManager, didUpdateOutputAudioLevel level: Float) {}
}

/// Canonical SVP close reasons understood by the Sierra Voice Protocol server.
///
/// The `rawValue` is the wire string sent on the SVP `close` message.
public enum AgentVoiceCloseReason: String {
    case error = "error"
    case normal = "normal"
    case transferred = "transferred"
    case continueInChat = "continue_in_chat"
}

/// Optional hint sent on the SVP `open` message to describe *why* the client
/// is resuming an existing conversation. Absence means a plain resume (e.g. a
/// network-reconnect during an active voice session) and produces no side
/// effects beyond rehydration.
///
/// The `rawValue` is the wire string sent on the SVP `open` message's
/// `resumeReason` field.
public enum AgentVoiceResumeReason: String {
    /// The client is resuming after a prior voice→chat handoff (the previous
    /// voice session closed with `AgentVoiceCloseReason.continueInChat`).
    /// The server will emit a `continue-in-voice` client event on the first
    /// agent turn so the agent can greet the user.
    case continueInVoice = "continue_in_voice"
}

/// Coordinates an end-to-end voice session.
///
/// `VoiceSessionManager` composes and orchestrates:
/// - `SVPTransport` for websocket protocol messaging
/// - `AudioCaptureSession` for microphone capture and preprocessing
/// - `AudioPlaybackQueue` for server audio playback and mark progress
///
/// The manager owns session lifecycle and coordination state, and forwards
/// relevant events to `VoiceSessionDelegate`.
public class VoiceSessionManager: NSObject {
    public enum State {
        case connecting
        case listening
        case speaking
        case ended
    }

    public private(set) var state: State = .connecting {
        didSet {
            if oldValue != state {
                debugLog("\(stateChangeTimestamp()) SVP state change: \(describeState(oldValue)) -> \(describeState(state))")
                audioCaptureSession?.setSpeakingState(state == .speaking)
                if disableInterruptions {
                    audioCaptureSession?.setSpeakingMuted(state == .speaking, stateDescription: describeState(state))
                }
                delegate?.voiceSession(self, didChangeState: state)
            }
        }
    }

    private let config: AgentConfig
    private let conversationId: String
    private let resumeConversation: Bool
    private let resumeReason: AgentVoiceResumeReason?
    private let disableInterruptions: Bool
    private let locale: Locale
    private let agentParameters: [String: String]
    private let enableText: Bool
    private let forwardAgentAttachments: Bool
    private let enableConversationEvents: Bool
    private var resumeToken: String?
    private weak var delegate: VoiceSessionDelegate?

    private var transport: SVPTransport?
    private var audioCaptureSession: AudioCaptureSession?
    private var audioPlaybackQueue: AudioPlaybackQueue?
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var isSessionRunning = false
    private var hasDeliveredSessionInfo = false
    private var hasDeliveredInitialAudioMessage = false
    private var hasDeliveredInitialAudioPlayback = false
    private var isUserListeningPaused = false
    private var interruptionInProgress = false
    private var audioSessionObservers: [NSObjectProtocol] = []
    private let sessionQueue = DispatchQueue(label: "com.sierra.sdk.voice.session")
    private let sessionQueueKey = DispatchSpecificKey<Void>()

    private let audioFormat = "linear16"
    private let sampleRate: Double = 24000
    private let compatibilityDate = "2026-05-07"
    private let preferredIOBufferDuration: Double = 0.02
    private let inputTapDuration: Double = 0.02

    private static let stateTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public init(
        config: AgentConfig,
        conversationId: String = UUID().uuidString,
        resumeConversation: Bool = false,
        resumeReason: AgentVoiceResumeReason? = nil,
        resumeToken: String? = nil,
        disableInterruptions: Bool = false,
        locale: Locale = .current,
        agentParameters: [String: String] = [:],
        enableText: Bool = true,
        forwardAgentAttachments: Bool = true,
        enableConversationEvents: Bool = false,
        delegate: VoiceSessionDelegate
    ) {
        self.config = config
        self.conversationId = conversationId
        self.resumeConversation = resumeConversation
        self.resumeReason = resumeReason
        self.resumeToken = resumeToken
        self.disableInterruptions = disableInterruptions
        self.locale = locale
        self.agentParameters = agentParameters
        self.enableText = enableText
        self.forwardAgentAttachments = forwardAgentAttachments
        self.enableConversationEvents = enableConversationEvents
        self.delegate = delegate
        super.init()
        sessionQueue.setSpecific(key: sessionQueueKey, value: ())
        configureComponents()
        setupAudioSessionObservers()
    }

    deinit {
        for observer in audioSessionObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        audioSessionObservers.removeAll()
    }

    public func connect() {
        sessionSync {
            isSessionRunning = true
            hasDeliveredSessionInfo = false
            hasDeliveredInitialAudioMessage = false
            hasDeliveredInitialAudioPlayback = false
            interruptionInProgress = false
        }
        setState(.connecting)
        transport?.connect()
    }

    public func disconnect(sendCloseMessage: Bool = true, closeReason: AgentVoiceCloseReason = .normal) {
        disconnect(sendCloseMessage: sendCloseMessage, rawCloseReason: closeReason.rawValue)
    }

    @available(*, deprecated, message: "Use disconnect(sendCloseMessage:closeReason:) with AgentVoiceCloseReason instead")
    public func disconnect(sendCloseMessage: Bool = true, closeReason: String) {
        disconnect(sendCloseMessage: sendCloseMessage, rawCloseReason: closeReason)
    }

    private func disconnect(sendCloseMessage: Bool, rawCloseReason: String) {
        sessionSync {
            isSessionRunning = false
            hasDeliveredSessionInfo = false
            hasDeliveredInitialAudioMessage = false
            hasDeliveredInitialAudioPlayback = false
            isUserListeningPaused = false
            interruptionInProgress = false
        }
        audioCaptureSession?.resetListeningPauseState()
        stopAudio()
        transport?.disconnect(sendCloseMessage: sendCloseMessage, closeReason: rawCloseReason)
        setState(.ended)
    }

    @discardableResult
    public func sendTextClient(_ text: String) -> Bool {
        transport?.send(type: "text_client", subMsg: ["text": text]) ?? false
    }

    @discardableResult
    public func sendAttachmentsClient(_ attachments: [[String: Any]]) -> Bool {
        debugLog("SVP send: attachments_client")
        return transport?.send(type: "attachments_client", subMsg: ["attachments": attachments]) ?? false
    }

    /// Pushes fresh values into conversation memory mid-call via the SVP
    /// `memory_update_client` message. The server applies the update via
    /// `api.UpdateMemory` out-of-band of the voice loop so the current agent
    /// turn is not interrupted; the agent picks up the new values on its next
    /// loop iteration.
    ///
    /// Pass `nil` (or an empty dictionary) for either map to omit it from the
    /// wire payload. `secret` values are sensitive: do not log them.
    public func sendMemoryUpdateClient(secrets: [String: String]? = nil, variables: [String: String]? = nil) {
        var subMsg: [String: Any] = [:]
        if let secrets, !secrets.isEmpty {
            subMsg["secrets"] = secrets
        }
        if let variables, !variables.isEmpty {
            subMsg["variables"] = variables
        }
        if subMsg.isEmpty {
            debugLog("SVP send: memory_update_client skipped (no variables or secrets)")
            return
        }
        // Log keys only, never values.
        let secretKeys = (secrets ?? [:]).keys.sorted().joined(separator: ", ")
        let variableKeys = (variables ?? [:]).keys.sorted().joined(separator: ", ")
        debugLog("SVP send: memory_update_client variableKeys=[\(variableKeys)] secretKeys=[\(secretKeys)]")
        transport?.send(type: "memory_update_client", subMsg: subMsg)
    }

    @discardableResult
    private func setupAudio() -> Bool {
        debugLog("SVP: Setting up audio")
        if audioEngine != nil, playerNode != nil, audioCaptureSession != nil, audioPlaybackQueue != nil {
            return reactivateAudioSessionIfNeeded()
        }
        if !hasBackgroundAudioModeEnabled() {
            debugLog("SVP warning: UIBackgroundModes does not include 'audio'; background playback/capture may stop when app is backgrounded")
        }
        do {
            try activateAudioSession()
        } catch {
            debugLog("SVP: Audio session setup failed: \(error)")
            delegate?.voiceSession(self, didEncounterError: error)
            return false
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        engine.connect(player, to: engine.mainMixerNode, format: outputFormat)

        let inputNode = engine.inputNode
        do {
            try inputNode.setVoiceProcessingEnabled(true)
        } catch {
            debugLog("Could not enable voice processing: \(error)")
        }

        let inputFormat = inputNode.outputFormat(forBus: 0)
        let capture = AudioCaptureSession(disableInterruptions: disableInterruptions, sampleRate: sampleRate, inputTapDuration: inputTapDuration)
        capture.onAudioData = { [weak self] data in
            self?.sendAudioClient(data)
        }
        capture.onInputLevel = { [weak self] level in
            guard let self else { return }
            DispatchQueue.main.async {
                self.delegate?.voiceSession(self, didUpdateInputAudioLevel: level)
            }
        }
        capture.start(inputNode: inputNode, inputFormat: inputFormat)
        installPlayerLevelTap(player: player, format: outputFormat)
        capture.setSpeakingState(currentState() == .speaking)
        if disableInterruptions {
            let state = currentState()
            capture.setSpeakingMuted(state == .speaking, stateDescription: describeState(state))
        }
        audioCaptureSession = capture
        if sessionSync({ isUserListeningPaused }) {
            capture.pauseListening()
        }

        let playback = AudioPlaybackQueue(sampleRate: sampleRate)
        playback.onDidStartSpeaking = { [weak self] in
            guard let self else { return }
            let shouldDeliverInitialAudioPlayback = self.markInitialAudioPlaybackDeliveredIfNeeded()
            if shouldDeliverInitialAudioPlayback {
                self.delegate?.voiceSessionDidStartInitialAudioPlayback(self)
            }
            if self.currentState() == .listening {
                self.setState(.speaking)
            }
        }
        playback.onDidStopSpeaking = { [weak self] in
            guard let self else { return }
            self.delegate?.voiceSession(self, didUpdateOutputAudioLevel: 0)
            if self.currentState() == .speaking {
                self.setState(.listening)
            }
        }
        playback.onPlaybackMark = { [weak self] mark in
            self?.sendPlaybackProgress(mark: mark)
        }
        playback.configure(playerNode: player)
        audioPlaybackQueue = playback

        self.audioEngine = engine
        self.playerNode = player

        do {
            try engine.start()
            player.play()
        } catch {
            stopAudio()
            delegate?.voiceSession(self, didEncounterError: error)
            return false
        }

        debugLog("SVP: Audio setup complete")
        return true
    }

    private func stopAudio() {
        audioCaptureSession?.stop()
        audioCaptureSession = nil
        audioPlaybackQueue?.stop()
        audioPlaybackQueue = nil
        playerNode?.removeTap(onBus: 0)
        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func installPlayerLevelTap(player: AVAudioPlayerNode, format: AVAudioFormat) {
        let bufferSize: AVAudioFrameCount = 1024
        var lastDispatchedLevel: Float = 0
        player.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let level = AudioLevelMeter.computeRMS(buffer: buffer)
            if level == 0, lastDispatchedLevel == 0 { return }
            lastDispatchedLevel = level
            DispatchQueue.main.async {
                let state = self.currentState()
                guard state == .speaking || (state == .listening && level > 0) else { return }
                self.delegate?.voiceSession(self, didUpdateOutputAudioLevel: level)
            }
        }
    }

    @discardableResult
    private func reactivateAudioSessionIfNeeded() -> Bool {
        do {
            try activateAudioSession()
            if let engine = audioEngine, !engine.isRunning {
                try engine.start()
            }
            if let playerNode, !playerNode.isPlaying {
                playerNode.play()
            }
            return true
        } catch {
            debugLog("SVP: Failed to reactivate audio session: \(error)")
            delegate?.voiceSession(self, didEncounterError: error)
            return false
        }
    }

    private func hasBackgroundAudioModeEnabled() -> Bool {
        guard let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] else {
            return false
        }
        return modes.contains("audio")
    }

    private func sendOpen() {
        let localeIdentifier = locale.identifier
        var subMsg: [String: Any] = [
            "compatibilityDate": compatibilityDate,
            "conversationId": conversationId,
            "audioFormat": audioFormat,
            "locale": localeIdentifier,
            "enableText": enableText,
            "forwardAgentAttachments": forwardAgentAttachments,
            "enableSessionInfo": true,
            "enableConversationEvents": enableConversationEvents,
        ]
        if resumeConversation {
            subMsg["resumeConversation"] = true
        }
        if let resumeReason {
            subMsg["resumeReason"] = resumeReason.rawValue
        }
        if let resumeToken {
            subMsg["resumeToken"] = resumeToken
        }
        if !agentParameters.isEmpty {
            subMsg["agentParameters"] = agentParameters
            let sortedKeys = agentParameters.sorted { $0.key < $1.key }.map(\.key).joined(separator: ", ")
            debugLog("SVP open: sending agentParameters keys=[\(sortedKeys)]")
        }
        transport?.send(type: "open", subMsg: subMsg)
    }

    private func sendAudioClient(_ audioData: Data) {
        transport?.send(type: "audio_client", subMsg: ["audioData": audioData.base64EncodedString()])
    }

    private func sendPlaybackProgress(mark: String) {
        transport?.send(type: "playback_progress", subMsg: ["mark": mark])
    }

    private func handleMessage(type: String, subMsg: [String: Any], rawText: String) {
        switch type {
        case "opened":
            if let token = subMsg["resumeToken"] as? String, !token.isEmpty {
                resumeToken = token
                delegate?.voiceSession(self, didReceiveResumeToken: token)
            }
            if setupAudio() {
                setState(.listening)
            }
        case "session_info":
            if let convID = subMsg["conversationId"] as? String, let key = subMsg["encryptionKey"] as? String {
                if hasDeliveredSessionInfo {
                    debugLog("SVP duplicate session_info ignored for conversationId=\(convID)")
                    return
                }
                hasDeliveredSessionInfo = true
                debugLog("SVP session_info: conversationId=\(convID), encryptionKey=[omitted]")
                delegate?.voiceSession(self, didReceiveCredentials: convID, encryptionKey: key)
            }
        case "audio_server":
            if let audioDataB64 = subMsg["audioData"] as? String,
               let audioData = Data(base64Encoded: audioDataB64) {
                if !hasDeliveredInitialAudioMessage {
                    hasDeliveredInitialAudioMessage = true
                    delegate?.voiceSessionDidReceiveInitialAudio(self)
                }
                audioPlaybackQueue?.enqueue(audioData, mark: subMsg["mark"] as? String)
            }
        case "attachments_server":
            debugLog("SVP recv: \(type)")
            if let attachments = subMsg["attachments"] as? [[String: Any]] {
                debugLog("SVP attachments_server received: \(attachments.count) attachment(s)")
                delegate?.voiceSession(self, didReceiveAttachments: attachments)
            } else {
                debugLog("SVP attachments_server received but could not parse subMsg.attachments")
            }
        case "conversation_event_server":
            guard enableConversationEvents else { return }
            if let event = AgentVoiceConversationEvent(raw: subMsg) {
                delegate?.voiceSession(self, didReceiveConversationEvent: event)
            } else {
                debugLog("SVP conversation_event_server received but could not parse subMsg")
            }
        case "clear":
            audioPlaybackQueue?.clear()
        case "end_conversation":
            // A server-initiated voice→chat handoff ends the call with the continue_in_chat custom
            // reason. Surface it distinctly so the host can continue the same conversation in chat;
            // any other end is a normal session end.
            if subMsg["customReason"] as? String == AgentVoiceCloseReason.continueInChat.rawValue {
                disconnect(sendCloseMessage: true, closeReason: .continueInChat)
                delegate?.voiceSessionDidRequestContinueInChat(self)
            } else {
                disconnect(sendCloseMessage: true)
                delegate?.voiceSessionDidEnd(self)
            }
        case "transfer":
            disconnect(sendCloseMessage: true, closeReason: .transferred)
            delegate?.voiceSessionDidEnd(self)
        default:
            if type.isEmpty {
                debugLog("SVP: Failed to parse message: \(rawText.prefix(200))")
            }
        }
    }

    public func interrupt() {
        audioPlaybackQueue?.clear()
    }

    public func pauseListening() {
        sessionSync { isUserListeningPaused = true }
        debugLog("SVP: Listening paused by user")
        audioCaptureSession?.pauseListening()
    }

    public func resumeListening() {
        sessionSync { isUserListeningPaused = false }
        debugLog("SVP: Listening resumed by user")
        audioCaptureSession?.resumeListening()
    }

    private func configureComponents() {
        let transport = SVPTransport(config: config)
        transport.delegate = self
        self.transport = transport
    }

    private func setupAudioSessionObservers() {
        let interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            self.sessionQueue.async {
                guard self.isSessionRunning else { return }
                self.handleAudioSessionInterruption(notification)
            }
        }

        let mediaResetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.sessionQueue.async {
                guard self.isSessionRunning else { return }
                self.stopAudio()
                _ = self.setupAudio()
                if !self.isUserListeningPaused {
                    self.audioCaptureSession?.resumeListening()
                }
            }
        }

        audioSessionObservers = [interruptionObserver, mediaResetObserver]
    }

    private func handleAudioSessionInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
            return
        }

        switch type {
        case .began:
            debugLog("SVP: Audio session interruption began")
            interruptionInProgress = true
            debugLog("SVP: Listening paused due to audio session interruption")
            audioCaptureSession?.pauseListening()
            audioPlaybackQueue?.clear()
        case .ended:
            let shouldResume = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? false
            debugLog("SVP: Audio session interruption ended (shouldResume=\(shouldResume))")
            guard interruptionInProgress else { return }
            interruptionInProgress = false
            if shouldResume {
                if reactivateAudioSessionIfNeeded(), !isUserListeningPaused {
                    debugLog("SVP: Listening resumed after interruption")
                    audioCaptureSession?.resumeListening()
                }
                return
            }
            endSessionForExternalAudioInterruption(reason: "audio_session_interruption_no_resume")
        @unknown default:
            break
        }
    }

    private func endSessionForExternalAudioInterruption(reason: String) {
        guard sessionSync({ isSessionRunning }) else { return }
        debugLog("SVP: Ending session due to external audio interruption (\(reason))")
        disconnect(sendCloseMessage: true, rawCloseReason: reason)
        delegate?.voiceSessionDidEnd(self)
    }

    private func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setPreferredIOBufferDuration(preferredIOBufferDuration)
        try session.setActive(true)
    }

    private func describeState(_ state: State) -> String {
        switch state {
        case .connecting: return "connecting"
        case .listening: return "listening"
        case .speaking: return "speaking"
        case .ended: return "ended"
        }
    }

    private func stateChangeTimestamp() -> String {
        VoiceSessionManager.stateTimestampFormatter.string(from: Date())
    }
}

extension VoiceSessionManager: SVPTransportDelegate {
    func svpTransportDidOpen(_ transport: SVPTransport) {
        debugLog("SVP: WebSocket opened, sending open message")
        sendOpen()
    }

    func svpTransport(_ transport: SVPTransport, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode) {
        debugLog("SVP: WebSocket closed with code: \(closeCode.rawValue)")
        sessionSync {
            isSessionRunning = false
        }
        setState(.ended)
    }

    func svpTransport(_ transport: SVPTransport, didEncounterError error: Error) {
        debugLog("SVP transport error: \(error)")
        if sessionSync({ isSessionRunning }) {
            delegate?.voiceSession(self, didEncounterError: error)
        }
        sessionSync {
            isSessionRunning = false
        }
        setState(.ended)
    }

    func svpTransport(_ transport: SVPTransport, didReceiveMessageType type: String, subMsg: [String: Any], rawText: String) {
        sessionQueue.async {
            // `end_conversation` and `transfer` are the server's terminal control messages: each
            // ends the session, and `end_conversation` may carry a server-initiated voice→chat
            // handoff (`customReason == continue_in_chat`). The server can send a terminal message
            // right before the socket closes, and URLSession delivers the message and the close on
            // separate main-queue callbacks with no ordering guarantee. If the close wins the race
            // it flips `isSessionRunning` to false, so honor terminal messages regardless to avoid
            // dropping them. (Today only `end_conversation` is server-closed; `transfer` is included
            // defensively in case that changes.) Other messages are ignored once the session is no
            // longer running.
            let isTerminalControlMessage = type == "end_conversation" || type == "transfer"
            guard self.isSessionRunning || isTerminalControlMessage else { return }
            self.handleMessage(type: type, subMsg: subMsg, rawText: rawText)
        }
    }
}

private extension VoiceSessionManager {
    func markInitialAudioPlaybackDeliveredIfNeeded() -> Bool {
        sessionSync {
            guard !hasDeliveredInitialAudioPlayback else { return false }
            hasDeliveredInitialAudioPlayback = true
            return true
        }
    }

    func setState(_ newState: State) {
        sessionSync {
            state = newState
        }
    }

    func currentState() -> State {
        sessionSync { state }
    }

    func sessionSync<T>(_ block: () -> T) -> T {
        if DispatchQueue.getSpecific(key: sessionQueueKey) != nil {
            return block()
        }
        return sessionQueue.sync(execute: block)
    }
}

enum VoiceError: LocalizedError {
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid SVP WebSocket URL"
        }
    }
}
