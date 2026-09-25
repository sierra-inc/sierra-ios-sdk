// Copyright Sierra

import WebKit
import XCTest
@testable import SierraSDK

final class WebViewAsyncJavaScriptTests: XCTestCase {
    @MainActor
    func testAddAgentTagsReturnsJavaScriptBoolean() async throws {
        let (controller, _) = try await makeController(
            script: """
            window.sierraMobile = {
              addAgentTags: async () => true
            };
            """
        )

        let result = try await controller.addAgentTags(["priority"])

        XCTAssertTrue(result)
    }

    @MainActor
    func testSendUserMessageWaitsForJavaScriptCompletion() async throws {
        let (controller, webView) = try await makeController(
            script: """
            window.sierraMobile = {
              sendUserMessage: async () => {
                await new Promise(resolve => setTimeout(resolve, 250));
                window.messageFinished = true;
              }
            };
            """
        )

        try await controller.sendUserMessage("hello")

        let didFinish = try await evaluateJavaScript("window.messageFinished === true", in: webView) as? Bool
        XCTAssertEqual(didFinish, true)
    }

    @MainActor
    func testSendUserAttachmentPropagatesJavaScriptError() async throws {
        let (controller, _) = try await makeController(
            script: """
            window.sierraMobile = {
              sendUserAttachment: async () => {
                throw new Error('attachment failed');
              }
            };
            """
        )

        do {
            try await controller.sendUserAttachment([.custom(data: ["id": "attachment-1"])])
            XCTFail("Expected the JavaScript error to propagate")
        } catch AgentChatError.invalidAttachments {
        } catch {
            XCTFail("Expected AgentChatError.invalidAttachments, got \(error)")
        }
    }

    @MainActor
    func testRefreshedIdentityIsReinjectedAfterAppearanceReload() async throws {
        let callbacks = RefreshingIdentityCallbacks()
        var options = AgentChatControllerOptions(name: "Test")
        options.userIdentityToken = "expired-identity-token"
        options.conversationCallbacks = callbacks
        let (controller, webView) = try await makeController(script: "", options: options)

        let refreshedToken = try await webView.callAsyncJavaScript(
            """
            return await window.webkit.messageHandlers.chatReplyHandler.postMessage({
              type: "onUserIdentityTokenExpiry"
            });
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? String

        XCTAssertEqual(refreshedToken, RefreshingIdentityCallbacks.token)
        XCTAssertEqual(controller.options.userIdentityToken, RefreshingIdentityCallbacks.token)

        webView.configuration.userContentController.removeAllUserScripts()
        controller.overrideUserInterfaceStyle = .dark
        controller.traitCollectionDidChange(UITraitCollection(userInterfaceStyle: .light))

        let payload = try injectedInitialConversation(in: webView)
        XCTAssertEqual(payload["userIdentityToken"] as? String, RefreshingIdentityCallbacks.token)
    }

    @MainActor
    func testIdentifiedReloadResumesTheLiveConversationAfterTargetResolves() async throws {
        let callbacks = RecordingConversationCallbacks()
        var options = AgentChatControllerOptions(name: "Test")
        options.userIdentityToken = "identity-token"
        options.conversationCallbacks = callbacks
        let (controller, webView) = try await makeController(
            script: "",
            options: options,
            conversationState: "opaque-state"
        )

        try await reportConversationStart("conv-live", callbacks: callbacks, in: webView)
        try reloadForAppearanceChange(controller, webView: webView)

        // The embed keeps resolved credentials in memory, not native storage, so the reload must
        // resume the live conversation through the bridge rather than start over.
        XCTAssertEqual(
            try injectedInitialTarget(in: webView),
            ["kind": "conversationID", "conversationID": "conv-live"]
        )
    }

    @MainActor
    func testAnonymousReloadKeepsReplayingStateUntilTheConversationIsLeft() async throws {
        let callbacks = RecordingConversationCallbacks()
        var options = AgentChatControllerOptions(name: "Test")
        options.conversationCallbacks = callbacks
        let agent = Agent(config: AgentConfig(token: "test-token"))
        let (controller, webView) = try await makeController(
            script: "",
            options: options,
            conversationState: "opaque-state",
            agent: agent
        )

        try await reportConversationStart("conv-live", callbacks: callbacks, in: webView)
        try reloadForAppearanceChange(controller, webView: webView)
        // Without an identity the state is the only durable way back into the conversation.
        XCTAssertEqual(try injectedInitialTarget(in: webView), ["kind": "state", "state": "opaque-state"])
        try await loadStableFixture(in: webView)

        // New chat: the embed persists a record without a conversation ID.
        _ = try await evaluateJavaScript(
            """
            window.webkit.messageHandlers.chatHandler.postMessage({
              type: "storeValue", key: "embed-chat-test-token", value: '{"conversationEnded":false}'
            }); true
            """,
            in: webView
        )
        try await awaitBridgeDelivery(callbacks: callbacks, in: webView)
        XCTAssertNotNil(agent.getStorage().getItem("embed-chat-test-token"))
        try reloadForAppearanceChange(controller, webView: webView)
        XCTAssertEqual(try injectedInitialTarget(in: webView), ["kind": "none"])
    }

    @MainActor
    func testReloadWhileConversationListIsShownRestoresTheList() async throws {
        let callbacks = RecordingConversationCallbacks()
        var options = AgentChatControllerOptions(name: "Test")
        options.userIdentityToken = "identity-token"
        options.conversationCallbacks = callbacks
        let (controller, webView) = try await makeController(
            script: "",
            options: options,
            conversationState: "opaque-state",
            conversationID: "external-123"
        )

        // A reload before the embed resolves the target (e.g. Retry after a failed load) must
        // still carry it.
        XCTAssertEqual(
            try injectedInitialTarget(in: webView)["kind"],
            "state"
        )

        try await reportConversationStart("conv-a", callbacks: callbacks, in: webView)
        let shown = expectation(description: "conversation list shown")
        callbacks.onShow = { shown.fulfill() }
        _ = try await evaluateJavaScript(
            """
            window.webkit.messageHandlers.chatHandler.postMessage({ type: "onShowConversationList" }); true
            """,
            in: webView
        )
        await fulfillment(of: [shown], timeout: 5)

        try reloadForAppearanceChange(controller, webView: webView)

        // The embed renders a new conversation for a `none` target unless the URL asks for the
        // list, so the reload must both drop the original target and request the list.
        XCTAssertEqual(try injectedInitialTarget(in: webView), ["kind": "none"])
        XCTAssertEqual(try injectedInitialConversation(in: webView)["userIdentityToken"] as? String, "identity-token")
        XCTAssertEqual(try loadedChatURLQueryValue("showConversationListByDefault", in: webView), "true")
        try await loadStableFixture(in: webView)

        let hidden = expectation(description: "conversation list hidden")
        callbacks.onHide = { hidden.fulfill() }
        _ = try await evaluateJavaScript(
            """
            window.webkit.messageHandlers.chatHandler.postMessage({ type: "onHideConversationList" }); true
            """,
            in: webView
        )
        await fulfillment(of: [hidden], timeout: 5)
        try reloadForAppearanceChange(controller, webView: webView)

        XCTAssertNil(try loadedChatURLQueryValue("showConversationListByDefault", in: webView))
    }

    @MainActor
    func testNewChatStartedFromTheListIsNotReloadedOntoTheList() async throws {
        let callbacks = RecordingConversationCallbacks()
        var options = AgentChatControllerOptions(name: "Test")
        options.userIdentityToken = "identity-token"
        options.conversationCallbacks = callbacks
        let (controller, webView) = try await makeController(script: "", options: options)

        // Opening the list clears the store first and then reports the list.
        let shown = expectation(description: "conversation list shown")
        callbacks.onShow = { shown.fulfill() }
        _ = try await evaluateJavaScript(
            """
            window.webkit.messageHandlers.chatHandler.postMessage({ type: "clearStorage" });
            window.webkit.messageHandlers.chatHandler.postMessage({ type: "onShowConversationList" }); true
            """,
            in: webView
        )
        await fulfillment(of: [shown], timeout: 5)

        // Starting a new chat from the list clears the store before the list reports hiding.
        _ = try await evaluateJavaScript(
            """
            window.webkit.messageHandlers.chatHandler.postMessage({ type: "clearStorage" }); true
            """,
            in: webView
        )
        try await awaitBridgeDelivery(callbacks: callbacks, in: webView)
        try reloadForAppearanceChange(controller, webView: webView)

        XCTAssertEqual(try injectedInitialTarget(in: webView), ["kind": "none"])
        XCTAssertNil(try loadedChatURLQueryValue("showConversationListByDefault", in: webView))
    }

    @MainActor
    private func reportConversationStart(
        _ conversationID: String,
        callbacks: RecordingConversationCallbacks,
        in webView: WKWebView
    ) async throws {
        let started = expectation(description: "conversation started")
        callbacks.onStart = { id in
            XCTAssertEqual(id, conversationID)
            started.fulfill()
        }
        _ = try await evaluateJavaScript(
            """
            window.webkit.messageHandlers.chatHandler.postMessage({
              type: "onConversationIDAvailable", unprefixedConversationID: "\(conversationID)"
            }); true
            """,
            in: webView
        )
        await fulfillment(of: [started], timeout: 5)
    }

    /// Script messages are delivered to the controller in order, so a callback-bearing message
    /// posted afterwards proves that earlier fire-and-forget messages have been handled.
    @MainActor
    private func awaitBridgeDelivery(callbacks: RecordingConversationCallbacks, in webView: WKWebView) async throws {
        let delivered = expectation(description: "bridge messages delivered")
        callbacks.onMessageEnd = { delivered.fulfill() }
        _ = try await evaluateJavaScript(
            """
            window.webkit.messageHandlers.chatHandler.postMessage({ type: "onAgentMessageEnd" }); true
            """,
            in: webView
        )
        await fulfillment(of: [delivered], timeout: 5)
    }

    @MainActor
    private func reloadForAppearanceChange(_ controller: AgentChatController, webView: WKWebView) throws {
        webView.configuration.userContentController.removeAllUserScripts()
        controller.overrideUserInterfaceStyle =
            controller.overrideUserInterfaceStyle == .dark ? .light : .dark
        controller.traitCollectionDidChange(
            UITraitCollection(userInterfaceStyle: controller.overrideUserInterfaceStyle == .dark ? .light : .dark)
        )
    }

    @MainActor
    private func injectedInitialConversation(in webView: WKWebView) throws -> [String: Any] {
        let prefix = "window.__sierraInitialConversation = "
        let script = try XCTUnwrap(webView.configuration.userContentController.userScripts.first {
            $0.source.hasPrefix(prefix)
        })
        let json = String(script.source.dropFirst(prefix.count).dropLast())
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    @MainActor
    private func injectedInitialTarget(in webView: WKWebView) throws -> [String: String] {
        try XCTUnwrap(injectedInitialConversation(in: webView)["target"] as? [String: String])
    }

    /// A reload starts a navigation to the real chat URL. Replace it with a blank document before
    /// posting further bridge messages so they cannot race that navigation.
    @MainActor
    private func loadStableFixture(in webView: WKWebView) async throws {
        try await NavigationWaiter().load("<html><body></body></html>", in: webView)
    }

    /// `WKWebView.url` reports the pending request as soon as `load(_:)` is called, so the chat
    /// URL a reload requested can be inspected without the page ever loading.
    @MainActor
    private func loadedChatURLQueryValue(_ name: String, in webView: WKWebView) throws -> String? {
        let url = try XCTUnwrap(webView.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return components.queryItems?.first { $0.name == name }?.value
    }

    @MainActor
    private func makeController(
        script: String,
        options: AgentChatControllerOptions = AgentChatControllerOptions(name: "Test"),
        conversationState: String? = nil,
        conversationID: String? = nil,
        agent: Agent = Agent(config: AgentConfig(token: "test-token"))
    ) async throws -> (AgentChatController, WKWebView) {
        let controller = AgentChatController(
            agent: agent,
            options: options,
            conversationState: conversationState,
            conversationID: conversationID
        )
        controller.loadViewIfNeeded()
        let webView = try XCTUnwrap(findWebView(in: controller.view))
        let navigationWaiter = NavigationWaiter()
        try await navigationWaiter.load(
            "<html><body><script>\(script)</script></body></html>",
            in: webView
        )

        return (controller, webView)
    }

    private func findWebView(in view: UIView) -> WKWebView? {
        if let webView = view as? WKWebView {
            return webView
        }
        return view.subviews.lazy.compactMap(findWebView).first
    }

    @MainActor
    private func evaluateJavaScript(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }
}

private final class RecordingConversationCallbacks: ConversationCallbacks {
    var onShow: (() -> Void)?
    var onHide: (() -> Void)?
    var onStart: ((String) -> Void)?
    var onMessageEnd: (() -> Void)?

    func onShowConversationList() {
        onShow?()
    }

    func onHideConversationList() {
        onHide?()
    }

    func onConversationStart(conversationID: String) {
        onStart?(conversationID)
    }

    func onAgentMessageEnd() {
        onMessageEnd?()
    }
}

private final class RefreshingIdentityCallbacks: ConversationCallbacks {
    static let token = "refreshed-identity-token"

    func onUserIdentityTokenExpiry(
        replyHandler: @escaping (Result<String?, any Error>) -> Void
    ) {
        replyHandler(.success(Self.token))
    }
}

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    /// Starting this load cancels any navigation already in flight, and WebKit reports that
    /// cancellation to the delegate too, so only callbacks for this navigation may resume.
    private var navigation: WKNavigation?

    func load(_ html: String, in webView: WKWebView) async throws {
        let previousDelegate = webView.navigationDelegate
        webView.navigationDelegate = self
        defer { webView.navigationDelegate = previousDelegate }

        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            navigation = webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        resume(navigation, with: .success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        resume(navigation, with: .failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        resume(navigation, with: .failure(error))
    }

    private func resume(_ finished: WKNavigation?, with result: Result<Void, Error>) {
        guard finished == navigation else { return }
        continuation?.resume(with: result)
        continuation = nil
    }
}
