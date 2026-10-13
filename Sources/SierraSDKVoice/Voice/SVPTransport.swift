// Copyright Sierra

import Foundation
import SierraSDK

/// Defines callbacks emitted by `SVPTransport`.
///
/// This protocol reports transport lifecycle transitions and decoded inbound
/// SVP messages so higher-level coordinators can handle protocol semantics.
/// Each transport reports at most one of `didCloseWith` or `didLoseConnection`.
protocol SVPTransportDelegate: AnyObject {
    func svpTransportDidOpen(_ transport: SVPTransport)
    func svpTransport(_ transport: SVPTransport, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode)
    /// The socket failed without a close frame: a receive error, a task error, an invalid URL,
    /// or a missed keepalive pong. `httpStatusCode` is set when the server rejected the handshake.
    func svpTransportDidLoseConnection(_ transport: SVPTransport, error: Error, httpStatusCode: Int?)
    func svpTransport(
        _ transport: SVPTransport,
        didReceiveMessageType type: String,
        subMsg: [String: Any],
        rawText: String
    )
}

/// Encapsulates SVP websocket transport behavior.
///
/// Responsibilities include:
/// - establishing and closing the websocket connection
/// - serializing outbound SVP messages with monotonically increasing `msgNum`
/// - running the receive loop and decoding message envelopes
/// - enforcing idempotent transport shutdown semantics
final class SVPTransport: NSObject, URLSessionDelegate, URLSessionWebSocketDelegate {
    private let config: AgentConfig
    weak var delegate: SVPTransportDelegate?

    /// Guarded by `stateLock`: the URLSession delegate queue, the keepalive queue, the session
    /// manager's queue, and audio threads all read these.
    private var _webSocketTask: URLSessionWebSocketTask?
    private var _urlSession: URLSession?
    private var _isRunning = false
    private let stateLock = NSLock()

    private var webSocketTask: URLSessionWebSocketTask? {
        get { withStateLock { _webSocketTask } }
        set { withStateLock { _webSocketTask = newValue } }
    }

    private var urlSession: URLSession? {
        get { withStateLock { _urlSession } }
        set { withStateLock { _urlSession = newValue } }
    }

    private var isRunning: Bool {
        get { withStateLock { _isRunning } }
        set { withStateLock { _isRunning = newValue } }
    }

    private var msgNum: Int = 0
    private let msgNumQueue = DispatchQueue(label: "com.sierra.sdk.voice.msgnum")
    private let transportShutdownQueue = DispatchQueue(label: "com.sierra.sdk.voice.transportshutdown")
    private var hasShutdownTransport = false
    /// Guarded by `transportShutdownQueue`.
    private var hasReportedTermination = false

    private let keepaliveQueue = DispatchQueue(label: "com.sierra.sdk.voice.keepalive")
    /// Confined to `keepaliveQueue`.
    private var keepaliveTimer: DispatchSourceTimer?
    /// Confined to `keepaliveQueue`. Incremented for every ping so a late pong cannot satisfy a newer one.
    private var pingSequence = 0
    /// Confined to `keepaliveQueue`.
    private var answeredPingSequence = 0
    static let pingInterval: TimeInterval = 10
    static let pongTimeout: TimeInterval = 5

    init(config: AgentConfig) {
        self.config = config
        super.init()
    }

    func connect() {
        var svpPath = "\(config.apiHost.voiceBaseURL)/chat/voice/svp/\(config.token)"
        if let target = config.target, !target.isEmpty {
            svpPath += "/release/\(target)"
        }
        let svpURL = svpPath
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")

        guard let url = URL(string: svpURL) else {
            delegate?.svpTransportDidLoseConnection(self, error: VoiceError.invalidURL, httpStatusCode: nil)
            return
        }

        isRunning = true
        let delegateQueue = OperationQueue()
        delegateQueue.name = "com.sierra.sdk.voice.svp"
        delegateQueue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: delegateQueue)
        self.urlSession = session

        let request = makeWebSocketRequest(url: url)

        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        transportShutdownQueue.sync {
            hasShutdownTransport = false
        }
        task.resume()
        debugLog("SVP: WebSocket task resumed, URL: \(url)")
        receiveMessages()
    }

    func makeWebSocketRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(getUserAgent(isWebView: false), forHTTPHeaderField: "User-Agent")
        if let oauthAccessToken = config.oauthAccessToken, !oauthAccessToken.isEmpty {
            request.setValue("Bearer \(oauthAccessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("2", forHTTPHeaderField: "X-Sierra-Token-Version")
        } else if let apiToken = config.svpHeadlessAPIToken, !apiToken.isEmpty {
            debugLog("SierraSDK: headlessAPIToken is deprecated. If you use a Headless API token, fetch it from your backend at runtime instead of shipping it in the app binary. Prefer oauthAccessToken.")
            request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    func disconnect(sendCloseMessage: Bool = true, closeReason: String = AgentVoiceCloseReason.normal.rawValue) {
        isRunning = false
        if sendCloseMessage {
            sendClose(reason: closeReason) { [weak self] in
                self?.shutdownTransportIfNeeded()
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.shutdownTransportIfNeeded()
            }
        } else {
            shutdownTransportIfNeeded()
        }
    }

    @discardableResult
    func send(type: String, subMsg: [String: Any]) -> Bool {
        sendJSON([
            "type": type,
            "msgNum": nextMsgNum(),
            "subMsg": subMsg,
        ])
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        guard isRunning else { return }
        startKeepalive()
        delegate?.svpTransportDidOpen(self)
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        if closeCode == .abnormalClosure {
            reportConnectionLoss(URLError(.networkConnectionLost))
        } else {
            reportClose(closeCode)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        reportConnectionLoss(error)
    }

    // MARK: - Internal

    private func nextMsgNum() -> Int {
        msgNumQueue.sync {
            msgNum += 1
            return msgNum
        }
    }

    private func sendClose(reason: String = AgentVoiceCloseReason.normal.rawValue, completion: (() -> Void)? = nil) {
        let msg: [String: Any] = [
            "type": "close",
            "msgNum": nextMsgNum(),
            "subMsg": ["reason": reason],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: msg),
              let str = String(data: data, encoding: .utf8) else {
            debugLog("SVP: Failed to serialize close message")
            completion?()
            return
        }
        guard let task = webSocketTask else {
            completion?()
            return
        }
        task.send(.string(str)) { error in
            if let error {
                debugLog("SVP close send error: \(error)")
            }
            completion?()
        }
    }

    @discardableResult
    private func sendJSON(_ dict: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else {
            debugLog("SVP: Failed to serialize message")
            return false
        }
        let type = dict["type"] as? String ?? "unknown"
        if type == "attachments_client" {
            debugLog("SVP send: \(type)")
        }
        guard let webSocketTask else {
            debugLog("SVP: Cannot send \(type), websocket is not connected")
            return false
        }
        // A failed send drops the message. Connection loss is reported by the receive loop, the
        // task completion, or the keepalive ping, so a send failure is not treated as fatal.
        webSocketTask.send(.string(str)) { error in
            if let error {
                debugLog("SVP send error for \(type): \(error)")
            }
        }
        return true
    }

    private func receiveMessages() {
        guard isRunning else { return }
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                guard self.isRunning else { return }
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data:
                    break
                @unknown default:
                    break
                }
                if self.isRunning {
                    self.receiveMessages()
                }
            case .failure(let error):
                debugLog("SVP recv error: \(error)")
                // A receive failure after a close frame is the close, not a lost connection. 1006
                // (abnormal closure) is never sent in a close frame; it means the socket died.
                if let closeCode = self.webSocketTask?.closeCode, closeCode != .invalid, closeCode != .abnormalClosure {
                    self.reportClose(closeCode)
                } else {
                    self.reportConnectionLoss(error)
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            debugLog("SVP: Failed to parse message: \(text.prefix(200))")
            return
        }
        let subMsg = json["subMsg"] as? [String: Any] ?? [:]
        delegate?.svpTransport(self, didReceiveMessageType: type, subMsg: subMsg, rawText: text)
    }

    private func reportClose(_ closeCode: URLSessionWebSocketTask.CloseCode) {
        guard markTerminationReportedIfRunning() else { return }
        stopKeepalive()
        delegate?.svpTransport(self, didCloseWith: closeCode)
    }

    private func reportConnectionLoss(_ error: Error) {
        guard markTerminationReportedIfRunning() else { return }
        stopKeepalive()
        let statusCode = (webSocketTask?.response as? HTTPURLResponse)?.statusCode
        debugLog("SVP: Connection lost (httpStatusCode=\(statusCode.map { "\($0)" } ?? "none")): \(error)")
        delegate?.svpTransportDidLoseConnection(self, error: error, httpStatusCode: statusCode)
    }

    private func markTerminationReportedIfRunning() -> Bool {
        guard isRunning else { return false }
        return transportShutdownQueue.sync {
            if hasReportedTermination {
                return false
            }
            hasReportedTermination = true
            return true
        }
    }

    private func startKeepalive() {
        keepaliveQueue.async {
            self.keepaliveTimer?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: self.keepaliveQueue)
            timer.schedule(deadline: .now() + Self.pingInterval, repeating: Self.pingInterval)
            timer.setEventHandler { [weak self] in
                self?.sendKeepalivePing()
            }
            self.keepaliveTimer = timer
            timer.resume()
        }
    }

    private func stopKeepalive() {
        keepaliveQueue.async {
            self.keepaliveTimer?.cancel()
            self.keepaliveTimer = nil
        }
    }

    /// Runs on `keepaliveQueue`.
    private func sendKeepalivePing() {
        guard isRunning, keepaliveTimer != nil, let task = webSocketTask else { return }
        pingSequence += 1
        let sequence = pingSequence
        task.sendPing { [weak self] error in
            guard let self else { return }
            self.keepaliveQueue.async {
                self.answeredPingSequence = max(self.answeredPingSequence, sequence)
                if let error {
                    debugLog("SVP: Keepalive ping failed: \(error)")
                    self.reportConnectionLoss(error)
                }
            }
        }
        keepaliveQueue.asyncAfter(deadline: .now() + Self.pongTimeout) { [weak self] in
            guard let self, self.answeredPingSequence < sequence, self.keepaliveTimer != nil else { return }
            debugLog("SVP: No keepalive pong within \(Self.pongTimeout)s")
            self.reportConnectionLoss(URLError(.timedOut))
        }
    }

    private func shutdownTransportIfNeeded() {
        let shouldShutdown = transportShutdownQueue.sync { () -> Bool in
            if hasShutdownTransport {
                return false
            }
            hasShutdownTransport = true
            return true
        }
        guard shouldShutdown else { return }
        stopKeepalive()
        let (task, session) = withStateLock { () -> (URLSessionWebSocketTask?, URLSession?) in
            defer {
                _webSocketTask = nil
                _urlSession = nil
            }
            return (_webSocketTask, _urlSession)
        }
        task?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()
    }

    private func withStateLock<T>(_ block: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return block()
    }
}
