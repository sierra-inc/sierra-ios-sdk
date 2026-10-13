// Copyright Sierra

import AVFoundation
import Foundation
import Network
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
    /// Per-band microphone levels for the voice waveform, each normalized to `0...1`.
    func voiceSession(_ session: VoiceSessionManager, didUpdateInputAudioBands bands: [Float])
    /// Per-band agent-speech levels for the voice waveform, each normalized to `0...1`.
    func voiceSession(_ session: VoiceSessionManager, didUpdateOutputAudioBands bands: [Float])
    /// The connection dropped and the session is retrying. Followed by `voiceSessionDidReconnect(_:)`
    /// on success, or by `voiceSession(_:didEncounterError:)` when the retries run out.
    func voiceSessionDidStartReconnecting(_ session: VoiceSessionManager)
    /// A reconnect reached `opened` and the session continues.
    func voiceSessionDidReconnect(_ session: VoiceSessionManager)
}

public extension VoiceSessionDelegate {
    func voiceSession(_ session: VoiceSessionManager, didReceiveConversationEvent event: AgentVoiceConversationEvent) {}
    func voiceSessionDidReceiveInitialAudio(_ session: VoiceSessionManager) {}
    func voiceSessionDidStartInitialAudioPlayback(_ session: VoiceSessionManager) {}
    func voiceSessionDidRequestContinueInChat(_ session: VoiceSessionManager) {}
    func voiceSession(_ session: VoiceSessionManager, didReceiveResumeToken token: String) {}
    func voiceSession(_ session: VoiceSessionManager, didUpdateInputAudioLevel level: Float) {}
    func voiceSession(_ session: VoiceSessionManager, didUpdateOutputAudioLevel level: Float) {}
    func voiceSession(_ session: VoiceSessionManager, didUpdateInputAudioBands bands: [Float]) {}
    func voiceSession(_ session: VoiceSessionManager, didUpdateOutputAudioBands bands: [Float]) {}
    func voiceSessionDidStartReconnecting(_ session: VoiceSessionManager) {}
    func voiceSessionDidReconnect(_ session: VoiceSessionManager) {}
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
    private let userIdentityToken: String?
    private let enableText: Bool
    private let forwardAgentAttachments: Bool
    private let enableConversationEvents: Bool
    private var resumeToken: String?
    /// True when this session continues a saved conversation, so even a reconnect before
    /// `session_info` must resume rather than open fresh. At this SDK's compatibility date the
    /// server resumes only when `open` carries a token, so a session without a host token is fresh
    /// even when `resumeConversation` is set.
    private let startedAsResume: Bool
    /// Whether the current connection's `open` resumed. The server keeps the token from the
    /// connection that created the conversation, so a resumed `opened` token must not replace it.
    private var isCurrentOpenResume = false
    private weak var delegate: VoiceSessionDelegate?

    /// Guarded by `connectionLock`: audio capture, playback marks, and host sends read these off
    /// `sessionQueue`. Every outgoing message other than `open` waits for `opened` on the current
    /// transport, because the server ends the session on any other message before `opened`.
    private var transport: SVPTransport?
    private var isConnectionOpen = false
    private let connectionLock = NSLock()

    /// Confined to `sessionQueue`.
    private var reconnectAttempt = 0
    private var pendingReconnect: DispatchWorkItem?
    /// Cancels a connection attempt that has not reached `opened` within its time limit.
    private var pendingAttemptTimeout: DispatchWorkItem?
    /// Reports whether the system has a network path. While it has none, a failed attempt does not
    /// count toward `reconnectDelays`: the session waits for the path and reconnects at once.
    private var pathMonitor: NWPathMonitor?
    private var isNetworkAvailable = true
    private var isWaitingForNetwork = false
    /// Ends the session when the network is not back within `networkWaitLimit` of the drop.
    private var pendingNetworkWaitLimit: DispatchWorkItem?
    /// System uptime when the connection dropped, cleared when a connection reaches `opened`.
    private var connectionLostAt: TimeInterval?
    private var isReconnecting = false
    /// System uptime when the current connection reached `opened`.
    private var connectionOpenedAt: TimeInterval?
    /// True from a reconnect's `open` until it receives a server message other than `opened`. The
    /// server reports a reconnect it cannot set up (for example a resume of a conversation it no
    /// longer has) with an error `end_conversation` right after `opened`.
    private var isAwaitingReconnectTraffic = false
    /// SVP `end_conversation` reason for a server-side failure.
    static let serverEndReasonError = "error"
    /// Wait before each reconnect attempt after a lost connection, with ±`reconnectJitter` applied
    /// (about 7 s in total).
    static let reconnectDelays: [TimeInterval] = [1, 2, 4]
    static let reconnectJitter = 0.2
    /// A reconnect attempt that has not received `opened` this long after it starts counts as
    /// failed. Without it a stalled attempt waits for the default URLSession timeout of 60 s.
    static let reconnectAttemptTimeout: TimeInterval = 5
    /// The first connection counts as a failed attempt and is retried if it has not received
    /// `opened` this long after it starts.
    static let firstConnectionTimeout: TimeInterval = 10
    /// How long after a drop the session waits for the system to report a network path again.
    static let networkWaitLimit: TimeInterval = 20
    /// A connection that stayed open this long resets the attempt count when it drops. Resetting
    /// on every `opened` would retry forever when each connection is cut seconds after it opens.
    static let stableConnectionDuration: TimeInterval = 10

    /// HTTP status of a rejected handshake that ended the session. Set before `didEncounterError`
    /// so the controller can tell a credentials failure from a lost connection.
    private(set) var handshakeRejectionStatusCode: Int?
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
    private let compatibilityDate = "2026-08-27"
    private let preferredIOBufferDuration: Double = 0.02
    private let waveformAnalysisInterval: Double = 0.02

    /// Requests 50 Hz analyser targets. CADisplayLink applies the Web SDK's smoothing at the actual
    /// display cadence, just as requestAnimationFrame does in the browser.
    static func waveformTapBufferSize(sampleRate: Double, interval: Double) -> AVAudioFrameCount {
        AVAudioFrameCount(max(64, Int((sampleRate * interval).rounded())))
    }

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
        userIdentityToken: String? = nil,
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
        self.startedAsResume = resumeToken?.isEmpty == false
        self.disableInterruptions = disableInterruptions
        self.locale = locale
        self.agentParameters = agentParameters
        self.userIdentityToken = userIdentityToken
        self.enableText = enableText
        self.forwardAgentAttachments = forwardAgentAttachments
        self.enableConversationEvents = enableConversationEvents
        self.delegate = delegate
        super.init()
        sessionQueue.setSpecific(key: sessionQueueKey, value: ())
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
            reconnectAttempt = 0
            connectionOpenedAt = nil
            connectionLostAt = nil
            handshakeRejectionStatusCode = nil
            cancelAttemptTimeout()
        }
        setState(.connecting)
        // Set up audio before the socket opens so the audio route change and the first-run mic
        // permission prompt do not overlap the start of the connection. Captured audio is dropped
        // until `opened`.
        sessionQueue.async {
            guard self.isSessionRunning else { return }
            self.startPathMonitor()
            do {
                try self.setupAudio()
            } catch {
                self.failSession(error: error)
                return
            }
            self.openTransport()
            self.scheduleAttemptTimeout(isFirstConnection: true)
        }
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
            pendingReconnect?.cancel()
            pendingReconnect = nil
            cancelAttemptTimeout()
            stopPathMonitor()
            isReconnecting = false
        }
        audioCaptureSession?.resetListeningPauseState()
        stopAudio()
        let transport = withConnectionLock { () -> SVPTransport? in
            isConnectionOpen = false
            return self.transport
        }
        transport?.disconnect(sendCloseMessage: sendCloseMessage, closeReason: rawCloseReason)
        setState(.ended)
    }

    /// The server rejects `text_client` and `attachments_client` before `opened` by ending the
    /// call. The session reaches `.listening` only after `opened`.
    var isMessageSendReady: Bool {
        let state = currentState()
        return state == .listening || state == .speaking
    }

    @discardableResult
    public func sendTextClient(_ text: String) -> Bool {
        sendWhenOpen(type: "text_client", subMsg: ["text": text])
    }

    @discardableResult
    public func sendAttachmentsClient(_ attachments: [[String: Any]]) -> Bool {
        debugLog("SVP send: attachments_client")
        return sendWhenOpen(type: "attachments_client", subMsg: ["attachments": attachments])
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
        sendWhenOpen(type: "memory_update_client", subMsg: subMsg)
    }

    private func setupAudio() throws {
        debugLog("SVP: Setting up audio")
        if audioEngine != nil, playerNode != nil, audioCaptureSession != nil, audioPlaybackQueue != nil {
            try reactivateAudioSession()
            return
        }
        if !hasBackgroundAudioModeEnabled() {
            debugLog("SVP warning: UIBackgroundModes does not include 'audio'; background playback/capture may stop when app is backgrounded")
        }
        do {
            try activateAudioSession()
        } catch {
            debugLog("SVP: Audio session setup failed: \(error)")
            throw error
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
        let capture = AudioCaptureSession(
            disableInterruptions: disableInterruptions,
            sampleRate: sampleRate,
            inputTapDuration: waveformAnalysisInterval
        )
        capture.onAudioData = { [weak self] data in
            self?.sendAudioClient(data)
        }
        capture.onInputLevel = { [weak self] level in
            guard let self else { return }
            DispatchQueue.main.async {
                self.delegate?.voiceSession(self, didUpdateInputAudioLevel: level)
            }
        }
        capture.onInputBands = { [weak self] bands in
            guard let self else { return }
            DispatchQueue.main.async {
                self.delegate?.voiceSession(self, didUpdateInputAudioBands: bands)
            }
        }
        capture.start(inputNode: inputNode, inputFormat: inputFormat)
        let outputSpectrumAnalyser = AudioSpectrumAnalyser()
        installPlayerLevelTap(player: player, format: outputFormat, spectrumAnalyser: outputSpectrumAnalyser)
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
            // Web Audio keeps rendering silence after playback ends. AVAudioPlayerNode may stop tap
            // callbacks with the final scheduled buffer, so iOS explicitly resets the analyser and
            // targets zero; VoiceWaveformView still applies the same visible release coefficient.
            outputSpectrumAnalyser.reset()
            self.delegate?.voiceSession(self, didUpdateOutputAudioLevel: 0)
            self.delegate?.voiceSession(self, didUpdateOutputAudioBands: AudioSpectrumAnalyser.restingLevels())
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
            throw error
        }

        debugLog("SVP: Audio setup complete")
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

    private func installPlayerLevelTap(
        player: AVAudioPlayerNode,
        format: AVAudioFormat,
        spectrumAnalyser: AudioSpectrumAnalyser
    ) {
        let bufferSize = Self.waveformTapBufferSize(
            sampleRate: format.sampleRate,
            interval: waveformAnalysisInterval
        )
        var lastDispatchedLevel: Float = 0
        player.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let level = AudioLevelMeter.computeRMS(buffer: buffer)
            if level == 0, lastDispatchedLevel == 0 { return }
            lastDispatchedLevel = level
            let bands: [Float]
            if level == 0 {
                // Playback just went quiet, so drop the smoothing rather than letting the next
                // utterance ramp out of stale bands.
                spectrumAnalyser.reset()
                bands = AudioSpectrumAnalyser.restingLevels()
            } else {
                bands = spectrumAnalyser.analyse(buffer: buffer)
            }
            DispatchQueue.main.async {
                let state = self.currentState()
                guard state == .speaking || (state == .listening && level > 0) else { return }
                self.delegate?.voiceSession(self, didUpdateOutputAudioLevel: level)
                self.delegate?.voiceSession(self, didUpdateOutputAudioBands: bands)
            }
        }
    }

    @discardableResult
    private func reactivateAudioSession() throws {
        do {
            try activateAudioSession()
            if let engine = audioEngine, !engine.isRunning {
                try engine.start()
            }
            if let playerNode, !playerNode.isPlaying {
                playerNode.play()
            }
        } catch {
            debugLog("SVP: Failed to reactivate audio session: \(error)")
            throw error
        }
    }

    /// Reports an audio failure that does not end the session, on main like other session errors.
    private func reportAudioError(_ error: Error) {
        DispatchQueue.main.async {
            self.delegate?.voiceSession(self, didEncounterError: error)
        }
    }

    private func hasBackgroundAudioModeEnabled() -> Bool {
        guard let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] else {
            return false
        }
        return modes.contains("audio")
    }

    /// Resume after `session_info` (or when the session started as a resume); before that there is
    /// no saved conversation to resume, and sending a resume token makes the server fail the open.
    private var shouldResumeOnOpen: Bool {
        resumeToken != nil && (hasDeliveredSessionInfo || startedAsResume)
    }

    func makeOpenSubMessage() -> [String: Any] {
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
        // After `session_info` the server has already applied the reason; resending it on a
        // reconnect would emit `continue-in-voice` a second time.
        if let resumeReason, !hasDeliveredSessionInfo {
            subMsg["resumeReason"] = resumeReason.rawValue
        }
        if let resumeToken, shouldResumeOnOpen {
            subMsg["resumeToken"] = resumeToken
        }
        if !agentParameters.isEmpty {
            subMsg["agentParameters"] = agentParameters
            let sortedKeys = agentParameters.sorted { $0.key < $1.key }.map(\.key).joined(separator: ", ")
            debugLog("SVP open: sending agentParameters keys=[\(sortedKeys)]")
        }
        if let userIdentityToken, !userIdentityToken.isEmpty {
            subMsg["userIdentityToken"] = userIdentityToken
        }
        return subMsg
    }

    private func sendAudioClient(_ audioData: Data) {
        guard let transport = withConnectionLock({ isConnectionOpen ? self.transport : nil }) else { return }
        transport.send(type: "audio_client", subMsg: ["audioData": audioData.base64EncodedString()])
    }

    private func sendPlaybackProgress(mark: String) {
        sendWhenOpen(type: "playback_progress", subMsg: ["mark": mark])
    }

    @discardableResult
    private func sendWhenOpen(type: String, subMsg: [String: Any]) -> Bool {
        guard let transport = withConnectionLock({ isConnectionOpen ? self.transport : nil }) else {
            debugLog("SVP: Dropping \(type), connection is not open")
            return false
        }
        return transport.send(type: type, subMsg: subMsg)
    }

    func handleMessage(type: String, subMsg: [String: Any], rawText: String) {
        let isRejectedReconnect = isAwaitingReconnectTraffic && type == "end_conversation" &&
            subMsg["reason"] as? String == Self.serverEndReasonError
        if type != "opened" {
            isAwaitingReconnectTraffic = false
        }
        switch type {
        case "opened":
            if let token = subMsg["resumeToken"] as? String, !token.isEmpty, !isCurrentOpenResume {
                resumeToken = token
                delegate?.voiceSession(self, didReceiveResumeToken: token)
            }
            cancelAttemptTimeout()
            connectionOpenedAt = ProcessInfo.processInfo.systemUptime
            connectionLostAt = nil
            withConnectionLock { isConnectionOpen = true }
            setState(.listening)
            if isReconnecting {
                isReconnecting = false
                DispatchQueue.main.async {
                    self.delegate?.voiceSessionDidReconnect(self)
                }
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
            if isRejectedReconnect {
                debugLog("SVP: Voice reconnect rejected by the server")
                let transport = withConnectionLock { () -> SVPTransport? in
                    isConnectionOpen = false
                    return self.transport
                }
                transport?.disconnect(sendCloseMessage: true, closeReason: AgentVoiceCloseReason.error.rawValue)
                failSession(error: URLError(.networkConnectionLost))
            } else if subMsg["customReason"] as? String == AgentVoiceCloseReason.continueInChat.rawValue {
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

    /// Runs on `sessionQueue`. Each connection, including a reconnect, uses a new transport.
    private func openTransport() {
        let transport = SVPTransport(config: config)
        transport.delegate = self
        let previous = withConnectionLock { () -> SVPTransport? in
            let previous = self.transport
            self.transport = transport
            isConnectionOpen = false
            return previous
        }
        previous?.delegate = nil
        previous?.disconnect(sendCloseMessage: false)
        transport.connect()
    }

    /// Runs on `sessionQueue`. Detaches the current transport, so late callbacks from it are ignored.
    private func detachTransport() {
        let lostTransport = withConnectionLock { () -> SVPTransport? in
            isConnectionOpen = false
            let lostTransport = transport
            transport = nil
            return lostTransport
        }
        lostTransport?.delegate = nil
        lostTransport?.disconnect(sendCloseMessage: false)
    }

    /// Runs on `sessionQueue`.
    private func handleConnectionLoss(error: Error, httpStatusCode: Int?) {
        detachTransport()
        cancelAttemptTimeout()
        guard isSessionRunning else { return }
        let wasUnopenedReconnectAttempt = isReconnecting && connectionOpenedAt == nil
        if let openedAt = connectionOpenedAt,
           ProcessInfo.processInfo.systemUptime - openedAt >= Self.stableConnectionDuration {
            reconnectAttempt = 0
        }
        connectionOpenedAt = nil
        if connectionLostAt == nil {
            connectionLostAt = ProcessInfo.processInfo.systemUptime
        }

        let isRejected = (error as? VoiceError) == .invalidURL || (400..<500).contains(httpStatusCode ?? 0)
        if !isRejected, !isNetworkAvailable {
            // An attempt made without a network fails at once and says nothing about the server.
            if wasUnopenedReconnectAttempt {
                reconnectAttempt = max(0, reconnectAttempt - 1)
            }
            debugLog("SVP: Connection lost with no network, waiting for the network: \(error)")
            beginReconnecting()
            waitForNetwork()
            return
        }
        guard !isRejected, reconnectAttempt < Self.reconnectDelays.count else {
            debugLog("SVP: Not reconnecting (rejected=\(isRejected), attempts=\(reconnectAttempt)): \(error)")
            if isRejected {
                handshakeRejectionStatusCode = httpStatusCode
            }
            failSession(error: error)
            return
        }

        let delay = Self.reconnectDelays[reconnectAttempt] * Double.random(in: (1 - Self.reconnectJitter)...(1 + Self.reconnectJitter))
        reconnectAttempt += 1
        let resume = shouldResumeOnOpen
        debugLog("SVP: Connection lost, reconnecting in \(String(format: "%.2f", delay))s (attempt \(reconnectAttempt), resume=\(resume))")
        beginReconnecting()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isSessionRunning else { return }
            self.pendingReconnect = nil
            self.openTransport()
            self.scheduleAttemptTimeout()
        }
        pendingReconnect?.cancel()
        pendingReconnect = workItem
        sessionQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// Runs on `sessionQueue`.
    private func beginReconnecting() {
        // Playback marks from the lost connection mean nothing to the next one.
        audioPlaybackQueue?.clear()
        setState(.connecting)
        if !isReconnecting {
            isReconnecting = true
            DispatchQueue.main.async {
                self.delegate?.voiceSessionDidStartReconnecting(self)
            }
        }
    }

    /// Runs on `sessionQueue`. A timed-out attempt, including the first connection, goes through
    /// `handleConnectionLoss`, which detaches its transport, so a late `opened` or close from it is
    /// ignored.
    private func scheduleAttemptTimeout(isFirstConnection: Bool = false) {
        cancelAttemptTimeout()
        let timeout = isFirstConnection ? Self.firstConnectionTimeout : Self.reconnectAttemptTimeout
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isSessionRunning else { return }
            self.pendingAttemptTimeout = nil
            debugLog("SVP: Connection attempt did not open within \(timeout)s")
            self.handleConnectionLoss(error: URLError(.timedOut), httpStatusCode: nil)
        }
        pendingAttemptTimeout = workItem
        sessionQueue.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    /// Runs on `sessionQueue`.
    private func cancelAttemptTimeout() {
        pendingAttemptTimeout?.cancel()
        pendingAttemptTimeout = nil
    }

    /// Runs on `sessionQueue`.
    private func startPathMonitor() {
        stopPathMonitor()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self, weak monitor] path in
            // Delivered on `sessionQueue`. An update from a stopped monitor is ignored.
            guard let self, let monitor, monitor === self.pathMonitor, self.isSessionRunning else { return }
            // `.requiresConnection` (for example VPN On Demand) can come up when a connection is made.
            self.handleNetworkPathUpdate(isAvailable: path.status != .unsatisfied)
        }
        pathMonitor = monitor
        monitor.start(queue: sessionQueue)
    }

    /// Runs on `sessionQueue`.
    private func stopPathMonitor() {
        pathMonitor?.cancel()
        pathMonitor = nil
        isNetworkAvailable = true
        endNetworkWait()
    }

    /// Runs on `sessionQueue`.
    private func handleNetworkPathUpdate(isAvailable: Bool) {
        isNetworkAvailable = isAvailable
        guard isAvailable, isWaitingForNetwork else { return }
        endNetworkWait()
        reconnectAttempt += 1
        debugLog("SVP: Network is back, reconnecting (attempt \(reconnectAttempt), resume=\(shouldResumeOnOpen))")
        openTransport()
        scheduleAttemptTimeout()
    }

    /// Runs on `sessionQueue`.
    private func waitForNetwork() {
        isWaitingForNetwork = true
        pendingNetworkWaitLimit?.cancel()
        let lostAt = connectionLostAt ?? ProcessInfo.processInfo.systemUptime
        let remaining = max(0, lostAt + Self.networkWaitLimit - ProcessInfo.processInfo.systemUptime)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isSessionRunning, self.isWaitingForNetwork else { return }
            debugLog("SVP: Network not back within \(Self.networkWaitLimit)s of the drop")
            self.endNetworkWait()
            self.failSession(error: URLError(.notConnectedToInternet))
        }
        pendingNetworkWaitLimit = workItem
        sessionQueue.asyncAfter(deadline: .now() + remaining, execute: workItem)
    }

    /// Runs on `sessionQueue`.
    private func endNetworkWait() {
        isWaitingForNetwork = false
        pendingNetworkWaitLimit?.cancel()
        pendingNetworkWaitLimit = nil
    }

    /// Runs on `sessionQueue`. Ends a session the manager can no longer continue and reports why.
    private func failSession(error: Error) {
        DispatchQueue.main.async {
            self.delegate?.voiceSession(self, didEncounterError: error)
        }
        isReconnecting = false
        isSessionRunning = false
        cancelAttemptTimeout()
        stopPathMonitor()
        stopAudio()
        setState(.ended)
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
                do {
                    try self.setupAudio()
                } catch {
                    self.reportAudioError(error)
                }
                if !self.isUserListeningPaused {
                    self.audioCaptureSession?.resumeFromInterruption()
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
            audioCaptureSession?.pauseForInterruption()
            audioPlaybackQueue?.clear()
        case .ended:
            let shouldResume = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? false
            debugLog("SVP: Audio session interruption ended (shouldResume=\(shouldResume))")
            guard interruptionInProgress else { return }
            interruptionInProgress = false
            if shouldResume {
                // Always clear the interruption pause once the session reactivates, even if the
                // user is muted: resumeFromInterruption() only clears the interruption flag (never
                // the user-mute flag), and while muted the engine must keep running so the capture
                // tap can emit silence. Gating this on !isUserListeningPaused left
                // _isInterruptionPaused stuck true, so capturePolicy kept dropping forever. See CH-633.
                do {
                    try reactivateAudioSession()
                    debugLog("SVP: Listening resumed after interruption")
                    audioCaptureSession?.resumeFromInterruption()
                } catch {
                    reportAudioError(error)
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
        sessionQueue.async {
            guard self.isCurrentTransport(transport), self.isSessionRunning else { return }
            debugLog("SVP: WebSocket opened, sending open message")
            self.isCurrentOpenResume = self.shouldResumeOnOpen
            self.isAwaitingReconnectTraffic = self.isReconnecting
            transport.send(type: "open", subMsg: self.makeOpenSubMessage())
        }
    }

    func svpTransport(_ transport: SVPTransport, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode) {
        sessionQueue.async {
            guard self.isCurrentTransport(transport) else { return }
            debugLog("SVP: WebSocket closed with code: \(closeCode.rawValue)")
            let wasOpen = self.withConnectionLock { self.isConnectionOpen }
            self.detachTransport()
            guard self.isSessionRunning else { return }
            // The server closes a connection whose `open` it cannot process, such as a resume of a
            // conversation it no longer has. Retrying would fail the same way.
            if !wasOpen {
                self.failSession(error: URLError(.networkConnectionLost))
                return
            }
            self.isSessionRunning = false
            self.cancelAttemptTimeout()
            self.stopPathMonitor()
            self.stopAudio()
            self.setState(.ended)
        }
    }

    func svpTransportDidLoseConnection(_ transport: SVPTransport, error: Error, httpStatusCode: Int?) {
        sessionQueue.async {
            guard self.isCurrentTransport(transport) else { return }
            self.handleConnectionLoss(error: error, httpStatusCode: httpStatusCode)
        }
    }

    func svpTransport(_ transport: SVPTransport, didReceiveMessageType type: String, subMsg: [String: Any], rawText: String) {
        sessionQueue.async {
            guard self.isCurrentTransport(transport) else { return }
            // `end_conversation` and `transfer` are the server's terminal control messages: each
            // ends the session, and `end_conversation` may carry a server-initiated voice→chat
            // handoff (`customReason == continue_in_chat`). The server can send a terminal message
            // right before the socket closes, and URLSession delivers the message and the close on
            // separate delegate-queue callbacks with no ordering guarantee. If the close wins the race
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

    /// Callbacks from a transport that was replaced by a reconnect are ignored.
    func isCurrentTransport(_ candidate: SVPTransport) -> Bool {
        withConnectionLock { transport === candidate }
    }

    func withConnectionLock<T>(_ block: () -> T) -> T {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        return block()
    }

    func sessionSync<T>(_ block: () -> T) -> T {
        if DispatchQueue.getSpecific(key: sessionQueueKey) != nil {
            return block()
        }
        return sessionQueue.sync(execute: block)
    }
}

enum VoiceError: LocalizedError, Equatable {
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid SVP WebSocket URL"
        }
    }
}
