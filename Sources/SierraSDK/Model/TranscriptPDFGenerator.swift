// Copyright Sierra

import Foundation
import WebKit

@MainActor
class TranscriptPDFGenerator: NSObject, WKNavigationDelegate {
    private let request: URLRequest
    private var continuation: CheckedContinuation<Void, Error>?

    init(request: URLRequest) {
        self.request = request
    }

    private lazy var webView: WKWebView = {
        let webView = WKWebView(frame: CGRect(origin: .zero, size: CGSize(width: 600, height: 200)))
        webView.navigationDelegate = self
        return webView
    }()

    func generate() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.webView.load(request)
        }

        let config = WKPDFConfiguration()
        config.rect = CGRect(origin: .zero, size: webView.scrollView.contentSize)
        return try await webView.pdf()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume(returning: ())
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
    }
}
