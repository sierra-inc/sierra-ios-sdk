// Copyright Sierra

import SierraSDK
import UIKit
import WebKit

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

/// Callbacks for interactive content events (e.g., user taps a flight card).
public protocol MobileRendererDelegate: AnyObject {
    /// Called when a rendered component sends a message via the web bundle's
    /// sendMessage callback (e.g., user selects a flight option).
    func mobileRenderer(_ renderer: MobileRendererView, didSendMessage text: String, attachments: [[String: Any]])

    /// Called when the rendered content size changes, allowing the host to
    /// adjust layout constraints.
    func mobileRenderer(_ renderer: MobileRendererView, didChangeContentHeight height: CGFloat)

    /// Called when the renderer encounters a fatal loading/rendering error.
    func mobileRenderer(_ renderer: MobileRendererView, didEncounterError error: Error)

    /// Called when the user taps a link in a rendered attachment that would otherwise be opened
    /// externally. The host may route the URL in-app or fall back to the system handler.
    func mobileRenderer(_ renderer: MobileRendererView, didClickLink url: URL)
}

public extension MobileRendererDelegate {
    func mobileRenderer(_ renderer: MobileRendererView, didEncounterError error: Error) {}
    func mobileRenderer(_ renderer: MobileRendererView, didClickLink url: URL) {}
}

/// A UIView that renders agent web bundle content pushed from SVP.
///
/// Hosts a lightweight WKWebView that loads the conversation renderer page,
/// which fetches the agent's web bundle and renders attachments (flight cards,
/// booking confirmations, etc.) by pushing JSON data directly via SVP -- no
/// conversation state, no chat infrastructure.
///
/// Usage:
/// ```swift
/// let renderer = MobileRendererView(agent: agent)
/// renderer.delegate = self
/// view.addSubview(renderer)
///
/// // When SVP delivers attachment JSON:
/// renderer.pushAttachments(attachmentDicts)
/// ```
public class MobileRendererView: UIView, WKNavigationDelegate, WKScriptMessageHandler {
    private var webView: WKWebView!
    private var isReady = false
    private var pendingAttachments: [String] = []
    private var pendingConversationEvents: [String] = []
    private var queuedConversationEvents: [String] = []
    private var isConversationEventFlushScheduled = false
    private var isConversationEventEvaluationInFlight = false
    private let agent: Agent
    private let options: AgentVoiceControllerOptions
    private var scriptMessageHandler: WeakScriptMessageHandler?

    public weak var delegate: MobileRendererDelegate?

    public init(agent: Agent, options: AgentVoiceControllerOptions = AgentVoiceControllerOptions(name: "Conversation")) {
        self.agent = agent
        self.options = options
        super.init(frame: .zero)
        setupWebView()
    }

    required init?(coder: NSCoder) {
        fatalError("Unreachable")
    }

    // MARK: - Setup

    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        let contentController = configuration.userContentController
        let handler = WeakScriptMessageHandler(delegate: self)
        scriptMessageHandler = handler
        contentController.add(handler, name: "chatHandler")

        applyAppBoundDomainsConfig(configuration)
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.backgroundColor = options.voiceStyle.backgroundColor
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.keyboardDismissMode = .interactive
        webView.navigationDelegate = self
        webView.customUserAgent = getUserAgent(isWebView: true)

#if targetEnvironment(simulator)
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
#endif

        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        loadRendererPage()
    }

    private func loadRendererPage() {
        guard var urlComponents = URLComponents(string: agent.config.conversationRendererURL) else {
            let error = NSError(
                domain: "ai.sierra.MobileRenderer",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "invalid-renderer-url"]
            )
            debugLog("MobileRenderer: Invalid URL: \(agent.config.conversationRendererURL)")
            delegate?.mobileRenderer(self, didEncounterError: error)
            return
        }

        var queryItems: [URLQueryItem] = []
        if let target = agent.config.target, !target.isEmpty {
            queryItems.append(URLQueryItem(name: "target", value: target))
        }
        let backgroundColorHex =
            options.voiceStyle.rendererBackgroundColor?.toHex() ??
            options.voiceStyle.backgroundColor.toHex()
        queryItems.append(URLQueryItem(name: "supportsLinkClick", value: "true"))
        debugLog(
            "MobileRenderer: Preparing renderer URL base=\(agent.config.conversationRendererURL), target=\(agent.config.target ?? "nil"), backgroundColor=\(backgroundColorHex ?? "nil")"
        )
        if let backgroundColorHex {
            queryItems.append(URLQueryItem(name: "backgroundColor", value: backgroundColorHex))
        }
        let messageStyleJSON = options.voiceStyle.messageStyleJSONString()
        if !messageStyleJSON.isEmpty {
            queryItems.append(URLQueryItem(name: "messageStyle", value: messageStyleJSON))
        }

        if !queryItems.isEmpty {
            urlComponents.queryItems = queryItems
            urlComponents.percentEncodedQuery = urlComponents.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
        }

        if let url = urlComponents.url {
            debugLog("MobileRenderer: Loading \(url)")
            webView.load(URLRequest(url: url))
        } else {
            debugLog("MobileRenderer: Failed to resolve renderer URL from components: \(urlComponents)")
        }
    }

    // MARK: - Public API

    /// Push attachment JSON directly for rendering via the agent's web bundle.
    ///
    /// - Parameter attachments: Array of attachment dictionaries matching the
    ///   SVP `attachments_server` format (each with "type" and "data" keys).
    public func pushAttachments(_ attachments: [[String: Any]]) {
        debugLog("MobileRenderer: pushAttachments called with \(attachments.count) attachment(s), isReady=\(isReady)")
        guard let data = try? JSONSerialization.data(withJSONObject: attachments),
              let json = String(data: data, encoding: .utf8) else {
            debugLog("MobileRenderer: Failed to serialize attachments")
            return
        }
        debugLog("MobileRenderer: serialized JSON length=\(json.count)")

        if isReady {
            evaluatePushAttachments(json)
        } else {
            debugLog("MobileRenderer: Page not ready, queuing \(attachments.count) attachment(s) (pending=\(pendingAttachments.count + 1))")
            pendingAttachments.append(json)
        }
    }

    /// Push an ordered conversation event for transcript rendering.
    public func pushConversationEvent(_ event: AgentVoiceConversationEvent) {
        let raw: [String: Any] = [
            "messageId": event.messageId,
            "eventType": event.eventType,
            "role": event.role,
            "text": event.text,
            "attachments": event.attachments,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: raw),
              let json = String(data: data, encoding: .utf8) else {
            debugLog("MobileRenderer: Failed to serialize conversation event")
            return
        }

        if isReady {
            enqueueConversationEvent(json)
        } else {
            debugLog("MobileRenderer: Page not ready, queuing conversation event (pending=\(pendingConversationEvents.count + 1))")
            pendingConversationEvents.append(json)
        }
    }

    /// Clear all rendered content.
    @available(*, deprecated, message: "The mobile renderer no longer supports native clear-conversation control messages.")
    public func clearConversation() {
        debugLog("MobileRenderer: clearConversation is deprecated and ignored")
    }

    // MARK: - JS Bridge

    private func evaluatePushAttachments(_ json: String) {
        debugLog("MobileRenderer: calling pushAttachments JS (json length=\(json.count))")
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await webView.callAsyncJavaScript(
                    """
                    const fn = window.sierraMobile?.pushAttachments;
                    if (typeof fn === 'function') {
                      return fn(json);
                    }
                    throw new Error('pushAttachments is not available');
                    """,
                    arguments: ["json": json],
                    in: nil,
                    in: .page
                )
                debugLog("MobileRenderer: pushAttachments JS executed successfully")
            } catch {
                debugLog("MobileRenderer: pushAttachments JS error: \(error)")
                self.delegate?.mobileRenderer(self, didEncounterError: error)
            }
        }
    }

    private func enqueueConversationEvent(_ json: String) {
        queuedConversationEvents.append(json)
        scheduleConversationEventFlush()
    }

    private func scheduleConversationEventFlush() {
        guard !isConversationEventFlushScheduled else { return }
        isConversationEventFlushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in
            self?.flushQueuedConversationEvents()
        }
    }

    private func flushQueuedConversationEvents() {
        isConversationEventFlushScheduled = false
        guard isReady, !isConversationEventEvaluationInFlight, !queuedConversationEvents.isEmpty else { return }
        let events = queuedConversationEvents
        guard let data = try? JSONSerialization.data(withJSONObject: events),
              let json = String(data: data, encoding: .utf8) else {
            debugLog("MobileRenderer: Failed to serialize queued conversation events")
            return
        }
        queuedConversationEvents.removeAll()
        evaluatePushConversationEvents(events, json: json)
    }

    private func evaluatePushConversationEvents(_ events: [String], json: String) {
        debugLog("MobileRenderer: calling pushConversationEvents JS (count=\(events.count), json length=\(json.count))")
        isConversationEventEvaluationInFlight = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            var didSucceed = false
            defer {
                self.isConversationEventEvaluationInFlight = false
                if didSucceed {
                    self.flushQueuedConversationEvents()
                }
            }
            do {
                try await webView.callAsyncJavaScript(
                    """
                    const fn = window.sierraMobile?.pushConversationEvents;
                    if (typeof fn === 'function') {
                      return fn(json);
                    }
                    throw new Error('pushConversationEvents is not available');
                    """,
                    arguments: ["json": json],
                    in: nil,
                    in: .page
                )
                debugLog("MobileRenderer: pushConversationEvents JS executed successfully")
                didSucceed = true
            } catch {
                debugLog("MobileRenderer: pushConversationEvents JS error: \(error)")
                self.queuedConversationEvents = events + self.queuedConversationEvents
                self.delegate?.mobileRenderer(self, didEncounterError: error)
            }
        }
    }

    private func flushPendingAttachments() {
        let pending = pendingAttachments
        pendingAttachments.removeAll()
        debugLog("MobileRenderer: flushing \(pending.count) pending attachment batch(es)")
        for json in pending {
            evaluatePushAttachments(json)
        }
    }

    private func flushPendingConversationEvents() {
        let pending = pendingConversationEvents
        pendingConversationEvents.removeAll()
        debugLog("MobileRenderer: flushing \(pending.count) pending conversation event(s)")
        for json in pending {
            enqueueConversationEvent(json)
        }
    }

    /// Shapes posted by the mobile renderer web bundle use `attachments` (array). Older bundles may send a single `attachment` with `data`.
    private func svpClientEventAttachments(from body: [String: Any]) -> [[String: Any]] {
        if let attachments = body["attachments"] as? [[String: Any]] {
            return attachments
        }
        if let attachment = body["attachment"] as? [String: Any],
           let data = attachment["data"] as? [String: Any] {
            return [["type": "custom", "data": data]]
        }
        return []
    }

    // MARK: - WKScriptMessageHandler

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "onOpen":
            debugLog("MobileRenderer: WebView ready")
            isReady = true
            flushPendingConversationEvents()
            flushPendingAttachments()

        case "onSVPClientEvent":
            let text = body["text"] as? String ?? ""
            let attachments = svpClientEventAttachments(from: body)
            guard !text.isEmpty || !attachments.isEmpty else { break }
            delegate?.mobileRenderer(self, didSendMessage: text, attachments: attachments)

        case "onAttachmentRendered":
            if let height = body["height"] as? CGFloat {
                delegate?.mobileRenderer(self, didChangeContentHeight: height)
            }

        case "onError":
            let reason = body["reason"] as? String ?? "unknown-renderer-error"
            let error = NSError(
                domain: "ai.sierra.MobileRenderer",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: reason]
            )
            debugLog("MobileRenderer: JS bridge reported error: \(reason)")
            delegate?.mobileRenderer(self, didEncounterError: error)

        case "onLinkClick":
            if let urlString = body["url"] as? String, let url = URL(string: urlString) {
                delegate?.mobileRenderer(self, didClickLink: url)
            }

        default:
            break
        }
    }

    // MARK: - WKNavigationDelegate

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        debugLog("MobileRenderer: Navigation failed: \(error)")
        delegate?.mobileRenderer(self, didEncounterError: error)
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        debugLog("MobileRenderer: Provisional navigation failed: \(error)")
        delegate?.mobileRenderer(self, didEncounterError: error)
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "chatHandler")
        scriptMessageHandler = nil
    }
}
