// Copyright Sierra

import Foundation
import UIKit

public struct AgentConfig {
    public let token: String
    public var apiBaseURL: String?

    public init(token: String) {
        self.token = token
    }
}

public class Agent {
    private let api: AgentAPI

    init(config: AgentConfig) {
        self.api = AgentAPI(config: config)
    }

    func newConversation(options: ConversationOptions?) -> Conversation {
        return Conversation(api: api, options: options)
    }
}

class AgentAPI {
    private static let API_COMPATIBILITY_DATE = "2023-10-26"

    private let token: String
    private let baseURL: String
    private let urlSession = {
        let config = URLSessionConfiguration.default
        let hostAppIdentifier = Bundle.main.bundleIdentifier ?? "unknown"
        let hostAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let iosModel = UIDevice.current.model
        let iosVersion = UIDevice.current.systemVersion
        config.httpAdditionalHeaders = [
            "User-Agent": "Sierra-iOS-SDK (\(hostAppIdentifier)/\(hostAppVersion) \(iosModel)/\(iosVersion))",
            "Sierra-API-Compatibility-Date": API_COMPATIBILITY_DATE,
        ]
        return URLSession(configuration: config)
    }()

    init(config: AgentConfig) {
        self.token = config.token
        self.baseURL = config.apiBaseURL ?? "https://api.sierra.chat"
    }

    func sendMessage(text: String, state: String?, options: ConversationOptions?) async throws -> AsyncThrowingStream<APIEvent, Error> {
        let locale = options?.locale ?? Locale.current
        let request = AgentChatRequest(
            token: token,
            message: text,
            state: state,
            variables: options?.variables,
            secrets: options?.secrets,
            locale: locale.identifier,
            customGreeting: options?.customGreeting,
            enableContactCenter: options?.enableContactCenter
        )
        var urlRequest = URLRequest(url: URL(string: "\(baseURL)/chat")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        return AsyncThrowingStream { continuation in
            let listener = AgentChatUpdateListener(urlSession: urlSession, urlRequest: urlRequest) { update in
                continuation.yield(update)
            } onComplete: { error in
                continuation.finish(throwing: error)
            }
            continuation.onTermination = { @Sendable _ in
                listener.cancel()
            }
        }
    }
}

// Matches the publicChatArguments type from public.go
struct AgentChatRequest: Codable {
    let token: String
    let message: String
    let state: String?
    let variables: [String: String]?
    let secrets: [String: String]?
    let locale: String
    let customGreeting: String?
    let enableContactCenter: Bool?
}

// Matches pubapi.Event and related (Go)
struct APIEvent: Codable {
    let type: String
    let state: String?
    struct Message: Codable {
        let role: String?
        let text: String?
        let isEndOfMessage: Bool?
        let preparingFollowup: Bool?
    }
    let message: Message?
    struct Transfer: Codable {
        let data: Dictionary<String, String>?
        let isSynchronous: Bool?
        let isContactCenter: Bool?
    }
    let transfer: Transfer?
    struct Error: Codable {
        let userVisibleMessage: String?
    }
    let error: Error?
}

enum AgentChatError: LocalizedError {
    case invalidChatUpdate
    case serverError(String)
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidChatUpdate:
            return "Invalid server message received"
        case .serverError(let message):
            return String(format: "A server error occurred: %@", message)
        case .httpError(let code):
            return String(format: "An HTTP error occurred (code: %d)", code)
        }
    }
}

class AgentChatUpdateListener: NSObject, URLSessionDataDelegate {
    private let task: URLSessionDataTask
    private let onUpdate: (APIEvent) -> Void
    private let onComplete: (Error?) -> Void
    private var buffer: String = ""

    init(urlSession: URLSession, urlRequest: URLRequest, onUpdate: @escaping ((APIEvent) -> Void), onComplete: @escaping ((Error?) -> Void)) {
        self.task = urlSession.dataTask(with: urlRequest)
        self.onUpdate = onUpdate
        self.onComplete = onComplete
        super.init()
        self.task.delegate = self
        self.task.resume()
    }

    func cancel() {
        task.cancel()
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let chunk = String(data: data, encoding: .utf8) {
            buffer.append(chunk)
            parseUpdates()
        } else {
            task.cancel()
            onComplete(AgentChatError.invalidChatUpdate)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        if httpResponse.statusCode != 200 {
            onComplete(AgentChatError.httpError(httpResponse.statusCode))
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onComplete(error)
    }

    private func parseUpdates() {
        while true {
            guard let updateEnd = buffer.range(of: "\n") else { break }

            let updateString = String(buffer[..<updateEnd.lowerBound])
            buffer.removeSubrange(..<updateEnd.upperBound)
            if updateString.isEmpty {
                continue
            }
            do {
                onUpdate(try parseUpdate(from: updateString))
            } catch {
                task.cancel()
                onComplete(error)
                break
            }
        }
    }

    private func parseUpdate(from jsonString: String) throws -> APIEvent {
        let jsonData = Data(jsonString.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let decoded = try? decoder.decode(APIEvent.self, from: jsonData) {
            return decoded
        }
        throw AgentChatError.invalidChatUpdate
    }
}
