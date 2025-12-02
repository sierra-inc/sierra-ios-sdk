// Copyright Sierra

import Foundation
import UIKit

public struct AgentConfig {
    public let token: String
    public let target: String?
    public var apiHost: AgentAPIHost = .prod

    public init(token: String, target: String? = nil) {
        self.token = token
        self.target = target
    }

    var url: String {
        return "\(apiHost.embedBaseURL)/agent/\(token)/mobile"
    }
}

public enum AgentAPIHost: String {
    case prod = "prod"
    case eu = "eu"
    case sg = "sg"
    case staging = "staging"
    case local = "local"

    var apiBaseURL: String {
        switch self {
        case .prod:
            return "https://api.sierra.chat"
        case .eu:
            return "https://eu.api.sierra.chat"
        case .sg:
            return "https://sg.api.sierra.chat"
        case .staging:
            return "https://api-staging.sierra.chat"
        case .local:
            return "https://api.sierra.codes:8083"
        }
    }

    var embedBaseURL: String {
        switch self {
        case .prod:
            return "https://sierra.chat"
        case .eu:
            return "https://eu.sierra.chat"
        case .sg:
            return "https://sg.sierra.chat"
        case .staging:
            return "https://staging.sierra.chat"
        case .local:
            return "https://chat.sierra.codes:8083"
        }
    }
}

public class Agent {
    private let api: AgentAPI
    let config: AgentConfig

    init(config: AgentConfig) {
        self.config = config
        self.api = AgentAPI(config: config)
    }

    @available(*, deprecated)
    func newConversation(options: ConversationOptions?) -> Conversation {
        return Conversation(api: api, options: options)
    }
}

func getUserAgent(isWebView: Bool) -> String {
    let hostAppIdentifier = Bundle.main.bundleIdentifier ?? "unknown"
    let hostAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    let iosModel = UIDevice.current.model
    let iosVersion = UIDevice.current.systemVersion
    var userAgent = "Sierra-iOS-SDK (\(hostAppIdentifier)/\(hostAppVersion) \(iosModel)/\(iosVersion))"
    if isWebView {
        userAgent += " WebView"
    }
    return userAgent
}

@available(*, deprecated)
class AgentAPI {
    private static let API_COMPATIBILITY_DATE = "2024-04-17"

    private let token: String
    private let apiHost: AgentAPIHost

    private static func urlSessionConfig() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": getUserAgent(isWebView: false),
            "Sierra-API-Compatibility-Date": API_COMPATIBILITY_DATE,
        ]
        return config
    }
    private let sendURLSession = URLSession(configuration: urlSessionConfig())
    private let pollURLSession = URLSession(configuration: urlSessionConfig())

    init(config: AgentConfig) {
        self.token = config.token
        self.apiHost = config.apiHost
    }

    func sendMessage(text: String, state: String?, options: ConversationOptions?, polling: Bool = false, isConversationEnd: Bool = false) async throws -> AsyncThrowingStream<APIEvent, Error> {
        let locale = options?.locale ?? Locale.current
        let request = AgentChatRequest(
            token: token,
            message: text,
            state: state,
            variables: options?.variables,
            secrets: options?.secrets,
            locale: locale.identifier,
            customGreeting: options?.customGreeting,
            enableContactCenter: options?.enableContactCenter,
            polling: polling,
            isConversationEnd: isConversationEnd
        )
        var urlRequest = URLRequest(url: URL(string: "\(apiHost.apiBaseURL)/chat")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        return AsyncThrowingStream { continuation in
            let listener = AgentChatUpdateListener(urlSession: sendURLSession, urlRequest: urlRequest) { update in
                continuation.yield(update)
            } onComplete: { error in
                continuation.finish(throwing: error)
            }
            continuation.onTermination = { @Sendable _ in
                listener.cancel()
            }
        }
    }

    func poll(state: String?, cursor: String?, options: ConversationOptions?) async throws -> AsyncThrowingStream<APIEvent, Error> {
        let locale = options?.locale ?? Locale.current
        let request = AgentPollRequest(
            token: token,
            state: state,
            variables: options?.variables,
            secrets: options?.secrets,
            cursor: cursor
        )
        var urlRequest = URLRequest(url: URL(string: "\(apiHost.apiBaseURL)/chat/live/poll")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        return AsyncThrowingStream { continuation in
            let listener = AgentChatUpdateListener(urlSession: pollURLSession, urlRequest: urlRequest) { update in
                continuation.yield(update)
            } onComplete: { error in
                continuation.finish(throwing: error)
            }
            continuation.onTermination = { @Sendable termination in
                listener.cancel()
                switch termination {
                case .cancelled:
                    continuation.finish(throwing: CancellationError())
                case .finished(let error):
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    @MainActor
    func saveTranscript(state: String, options: ConversationOptions?) async throws -> Data {
        var request = URLRequest(url: URL(string: "\(apiHost.embedBaseURL)/agent/\(token)/transcript")!)
        request.httpMethod = "POST"

        var formParams = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "state", value: state),
        ]
        if let customGreeting = options?.customGreeting {
            formParams.append(URLQueryItem(name: "greeting", value: customGreeting))
        }
        var formData = URLComponents()
        formData.queryItems = formParams
        request.httpBody = formData.query?.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let generator = TranscriptPDFGenerator(request: request)
        let pdfData = try await generator.generate()
        return pdfData
    }
}

// Matches the publicChatArguments type from public.go
struct AgentChatRequest: Encodable {
    let token: String
    let message: String
    let state: String?
    let variables: [String: String]?
    let secrets: [String: String]?
    let locale: String
    let customGreeting: String?
    let enableContactCenter: Bool?
    let polling: Bool?
    let isConversationEnd: Bool?
}

// Matches the livePollArguments type from live.go
struct AgentPollRequest: Encodable {
    let token: String
    let state: String?
    let variables: [String: String]?
    let secrets: [String: String]?
    let cursor: String?
}

// Matches pubapi.Event and related (Go)
struct APIEvent: Decodable {
    let type: String

    let state: String?

    struct Message: Decodable {
        let role: String?
        let text: String?
        let isEndOfMessage: Bool?
        let preparingFollowup: Bool?
        let attachments: [Attachment]?

        struct Attachment: Decodable {
            let type: String
            let buttonData: ButtonData?

            enum CodingKeys: String, CodingKey {
                case type
                case data
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                type = try container.decode(String.self, forKey: .type)
                if let decodedButtonData = try? container.decode(ButtonData.self, forKey: .data), decodedButtonData.type == "button" {
                    buttonData = decodedButtonData
                } else {
                    buttonData = nil
                }
            }

            public struct ButtonData: Decodable {
                let type: String
                let url: String
                let text: String
            }
        }
    }
    let message: Message?

    struct Transfer: Decodable {
        let data: Dictionary<String, String>?
        let isSynchronous: Bool?
        let isContactCenter: Bool?
    }
    let transfer: Transfer?

    let livePollCursor: String?

    struct HumanAgentInfo: Decodable {
        let queueSize: Int?
        let displayName: String?
        let joined: Bool?
        let left: Bool?
        let typing: Bool?
    }
    let humanAgentInfo: HumanAgentInfo?

    struct EndConversation: Decodable {
        let reason: String?
    }
    let endConversation: EndConversation?

    struct Error: Decodable {
        let userVisibleMessage: String?
    }
    let error: Error?
}

enum AgentChatError: LocalizedError {
    case invalidChatUpdate
    case serverError(String)
    case httpError(Int)
    case invalidAttachments(String)

    /// Logged message for the error
    var errorDescription: String? {
        switch self {
        case .invalidChatUpdate:
            return "Invalid server message received"
        case .serverError(let message):
            return String(format: "A server error occurred: %@", message)
        case .httpError(let code):
            return String(format: "An HTTP error occurred (code: %d)", code)
        case .invalidAttachments(let message):
            return message
        }
    }

    /// User-visible message shown for any errors that should override the standard error string.
    var errorMessage: String? {
        switch self {
        case .httpError(let code):
            switch code {
            case 410: return "This conversation cannot be continued. Please start a new one."
            case 413: "The message you sent was too long. Please send something shorter.";
            case 429: return "You've reached our message limit. Please try again later."
            default: return nil
            }
            default: return nil
        }
        return nil
    }
}

@available(*, deprecated)
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
        if httpResponse.statusCode >= 400 {
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

        do {
            return try decoder.decode(APIEvent.self, from: jsonData)
        } catch {
            debugLog("could not decode: error=\(error)")
            throw AgentChatError.invalidChatUpdate
        }
    }
}
