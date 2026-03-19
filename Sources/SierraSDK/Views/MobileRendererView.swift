// Copyright Sierra

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
@_spi(ExperimentalVoice)
public protocol MobileRendererDelegate: AnyObject {
    /// Called when a rendered component sends a message via the web bundle's
    /// sendMessage callback (e.g., user selects a flight option).
    func mobileRenderer(_ renderer: MobileRendererView, didSendMessage text: String, attachments: [[String: Any]])

    /// Called when the rendered content size changes, allowing the host to
    /// adjust layout constraints.
    func mobileRenderer(_ renderer: MobileRendererView, didChangeContentHeight height: CGFloat)

    /// Called when the renderer encounters a fatal loading/rendering error.
    func mobileRenderer(_ renderer: MobileRendererView, didEncounterError error: Error)
}

@_spi(ExperimentalVoice)
public extension MobileRendererDelegate {
    func mobileRenderer(_ renderer: MobileRendererView, didEncounterError error: Error) {}
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
@_spi(ExperimentalVoice)
public class MobileRendererView: UIView, WKNavigationDelegate, WKScriptMessageHandler {
    private var webView: WKWebView!
    private var isReady = false
    private var pendingAttachments: [String] = []
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

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.backgroundColor = options.voiceStyle.backgroundColor
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = true
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
        debugLog(
            "MobileRenderer: Preparing renderer URL base=\(agent.config.conversationRendererURL), target=\(agent.config.target ?? "nil"), backgroundColor=\(backgroundColorHex ?? "nil")"
        )
        if let backgroundColorHex {
            queryItems.append(URLQueryItem(name: "backgroundColor", value: backgroundColorHex))
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

    /// Clear all rendered content.
    public func clearAttachments() {
        webView.evaluateJavaScript(
            "if (window.sierraMobile?.clearPushedAttachments) { window.sierraMobile.clearPushedAttachments(); }",
            completionHandler: nil
        )
    }

    // MARK: - JS Bridge

    private func evaluatePushAttachments(_ json: String) {
        debugLog("MobileRenderer: calling pushAttachments JS (json length=\(json.count))")
        webView.callAsyncJavaScript(
            "if (window.sierraMobile?.pushAttachments) { window.sierraMobile.pushAttachments(json); }",
            arguments: ["json": json],
            in: nil,
            in: .page
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                debugLog("MobileRenderer: pushAttachments JS executed successfully")
            case let .failure(error):
                debugLog("MobileRenderer: pushAttachments JS error: \(error)")
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

    // MARK: - WKScriptMessageHandler

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "onOpen":
            debugLog("MobileRenderer: WebView ready")
            isReady = true
            flushPendingAttachments()

        case "onSVPClientEvent":
            let text = body["text"] as? String ?? ""
            if let attachments = body["attachments"] as? [[String: Any]] {
                delegate?.mobileRenderer(self, didSendMessage: text, attachments: attachments)
            } else if let attachment = body["attachment"] as? [String: Any],
                      let data = attachment["data"] as? [String: Any] {
                delegate?.mobileRenderer(self, didSendMessage: text, attachments: [[
                    "type": "custom",
                    "data": data,
                ]])
            }

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
