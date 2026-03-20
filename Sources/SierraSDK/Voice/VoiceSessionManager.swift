// Copyright Sierra

import AVFoundation
import Foundation

/// Defines callbacks emitted by `VoiceSessionManager` during a voice session lifecycle.
///
/// Implementers are notified about:
/// - state transitions for the active voice session
/// - credentials/session metadata required by the host
/// - incoming attachment payloads from the server
/// - terminal events and surfaced errors
@_spi(ExperimentalVoice)
public protocol VoiceSessionDelegate: AnyObject {
    func voiceSession(_ session: VoiceSessionManager, didReceiveCredentials conversationID: String, encryptionKey: String)
    func voiceSession(_ session: VoiceSessionManager, didReceiveAttachments attachments: [[String: Any]])
    func voiceSession(_ session: VoiceSessionManager, didChangeState state: VoiceSessionManager.State)
    func voiceSession(_ session: VoiceSessionManager, didEncounterError error: Error)
    func voiceSessionDidEnd(_ session: VoiceSessionManager)
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
@_spi(ExperimentalVoice)
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
    private let disableInterruptions: Bool
    private let agentParameters: [String: String]
    private weak var delegate: VoiceSessionDelegate?

    private var transport: SVPTransport?
    private var audioCaptureSession: AudioCaptureSession?
    private var audioPlaybackQueue: AudioPlaybackQueue?
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var isSessionRunning = false
    private var hasDeliveredSessionInfo = false
    private var isUserListeningPaused = false
    private var interruptionInProgress = false
    private var audioSessionObservers: [NSObjectProtocol] = []
    private let sessionQueue = DispatchQueue(label: "com.sierra.sdk.voice.session")
    private let sessionQueueKey = DispatchSpecificKey<Void>()

    private let audioFormat = "linear16"
    private let sampleRate: Double = 24000
    private let compatibilityDate = "2025-10-20"
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
        disableInterruptions: Bool = false,
        agentParameters: [String: String] = [:],
        delegate: VoiceSessionDelegate
    ) {
        self.config = config
        self.conversationId = conversationId
        self.disableInterruptions = disableInterruptions
        self.agentParameters = agentParameters
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
            interruptionInProgress = false
        }
        setState(.connecting)
        transport?.connect()
    }

    public func disconnect(sendCloseMessage: Bool = true, closeReason: String = "normal") {
        sessionSync {
            isSessionRunning = false
            hasDeliveredSessionInfo = false
            isUserListeningPaused = false
            interruptionInProgress = false
        }
        audioCaptureSession?.resetListeningPauseState()
        stopAudio()
        transport?.disconnect(sendCloseMessage: sendCloseMessage, closeReason: closeReason)
        setState(.ended)
    }

    public func sendTextClient(_ text: String) {
        transport?.send(type: "text_client", subMsg: ["text": text])
    }

    public func sendAttachmentsClient(_ attachments: [[String: Any]]) {
        debugLog("SVP send: attachments_client")
        transport?.send(type: "attachments_client", subMsg: ["attachments": attachments])
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
        capture.start(inputNode: inputNode, inputFormat: inputFormat)
        capture.setSpeakingState(currentState() == .speaking)
        if disableInterruptions {
            let state = currentState()
            capture.setSpeakingMuted(state == .speaking, stateDescription: describeState(state))
        }
        audioCaptureSession = capture

        let playback = AudioPlaybackQueue(sampleRate: sampleRate)
        playback.onDidStartSpeaking = { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                if self.currentState() == .listening {
                    self.setState(.speaking)
                }
            }
        }
        playback.onDidStopSpeaking = { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                if self.currentState() == .speaking {
                    self.setState(.listening)
                }
            }
        }
        playback.onPlaybackMark = { [weak self] mark in
            self?.sendPlaybackProgress(mark: mark)
        }
        playback.configure(playerNode: player)
        audioPlaybackQueue = playback

        do {
            try engine.start()
            player.play()
        } catch {
            delegate?.voiceSession(self, didEncounterError: error)
            return false
        }

        self.audioEngine = engine
        self.playerNode = player
        debugLog("SVP: Audio setup complete")
        return true
    }

    private func stopAudio() {
        audioCaptureSession?.stop()
        audioCaptureSession = nil
        audioPlaybackQueue?.stop()
        audioPlaybackQueue = nil
        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        try? AVAudioSession.sharedInstance().setActive(false)
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
        let locale = Locale.current.identifier
        var subMsg: [String: Any] = [
            "compatibilityDate": compatibilityDate,
            "conversationId": conversationId,
            "audioFormat": audioFormat,
            "locale": locale,
        ]
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
        case "clear":
            audioPlaybackQueue?.clear()
        case "end_conversation":
            disconnect(sendCloseMessage: true)
            delegate?.voiceSessionDidEnd(self)
        case "transfer":
            disconnect(sendCloseMessage: true, closeReason: "transferred")
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
        disconnect(sendCloseMessage: true, closeReason: reason)
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
            guard self.isSessionRunning else { return }
            self.handleMessage(type: type, subMsg: subMsg, rawText: rawText)
        }
    }
}

private extension VoiceSessionManager {
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
