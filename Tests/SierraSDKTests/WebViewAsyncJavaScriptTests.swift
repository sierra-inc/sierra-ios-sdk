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
    private func makeController(script: String) async throws -> (AgentChatController, WKWebView) {
        let agent = Agent(config: AgentConfig(token: "test-token"))
        let controller = AgentChatController(
            agent: agent,
            options: AgentChatControllerOptions(name: "Test")
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

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ html: String, in webView: WKWebView) async throws {
        let previousDelegate = webView.navigationDelegate
        webView.navigationDelegate = self
        defer { webView.navigationDelegate = previousDelegate }

        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        resume(with: .success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        resume(with: .failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        resume(with: .failure(error))
    }

    private func resume(with result: Result<Void, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
