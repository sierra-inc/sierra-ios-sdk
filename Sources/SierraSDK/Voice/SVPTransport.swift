// Copyright Sierra

import Foundation

/// Defines callbacks emitted by `SVPTransport`.
///
/// This protocol reports transport lifecycle transitions and decoded inbound
/// SVP messages so higher-level coordinators can handle protocol semantics.
protocol SVPTransportDelegate: AnyObject {
    func svpTransportDidOpen(_ transport: SVPTransport)
    func svpTransport(_ transport: SVPTransport, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode)
    func svpTransport(_ transport: SVPTransport, didEncounterError error: Error)
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

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isRunning = false

    private var msgNum: Int = 0
    private let msgNumQueue = DispatchQueue(label: "com.sierra.sdk.voice.msgnum")
    private let transportShutdownQueue = DispatchQueue(label: "com.sierra.sdk.voice.transportshutdown")
    private var hasShutdownTransport = false

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
            delegate?.svpTransport(self, didEncounterError: VoiceError.invalidURL)
            return
        }

        isRunning = true
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        self.urlSession = session

        var request = URLRequest(url: url)
        request.setValue(getUserAgent(isWebView: false), forHTTPHeaderField: "User-Agent")
        if let apiToken = config.headlessAPIToken {
            request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        }

        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        transportShutdownQueue.sync {
            hasShutdownTransport = false
        }
        task.resume()
        debugLog("SVP: WebSocket task resumed, URL: \(url)")
        receiveMessages()
    }

    func disconnect(sendCloseMessage: Bool = true, closeReason: String = "normal") {
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

    func send(type: String, subMsg: [String: Any]) {
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
        delegate?.svpTransportDidOpen(self)
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        delegate?.svpTransport(self, didCloseWith: closeCode)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, isRunning {
            delegate?.svpTransport(self, didEncounterError: error)
        }
    }

    // MARK: - URLSessionDelegate

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if config.apiHost == .local,
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }

    // MARK: - Internal

    private func nextMsgNum() -> Int {
        msgNumQueue.sync {
            msgNum += 1
            return msgNum
        }
    }

    private func sendClose(reason: String = "normal", completion: (() -> Void)? = nil) {
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
        task.send(.string(str)) { [weak self] error in
            if let error {
                debugLog("SVP send error: \(error)")
                if let self {
                    self.delegate?.svpTransport(self, didEncounterError: error)
                }
            }
            completion?()
        }
    }

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else {
            debugLog("SVP: Failed to serialize message")
            return
        }
        let type = dict["type"] as? String ?? "unknown"
        if type == "attachments_client" {
            debugLog("SVP send: \(type)")
        }
        webSocketTask?.send(.string(str)) { [weak self] error in
            if let error {
                debugLog("SVP send error: \(error)")
                guard let self else { return }
                self.delegate?.svpTransport(self, didEncounterError: error)
            }
        }
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
                guard self.isRunning else { return }
                debugLog("SVP recv error: \(error)")
                self.delegate?.svpTransport(self, didEncounterError: error)
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

    private func shutdownTransportIfNeeded() {
        let shouldShutdown = transportShutdownQueue.sync { () -> Bool in
            if hasShutdownTransport {
                return false
            }
            hasShutdownTransport = true
            return true
        }
        guard shouldShutdown else { return }
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }
}
