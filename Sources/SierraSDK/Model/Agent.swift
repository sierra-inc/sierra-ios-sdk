// Copyright Sierra

import Foundation

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
    private let token: String
    private let baseURL: String
    private let urlSession = URLSession(configuration: URLSessionConfiguration.default)

    init(config: AgentConfig) {
        self.token = config.token
        self.baseURL = config.apiBaseURL ?? "https://sierra.chat"
    }

    func sendMessage(text: String, conversationID: String?, encryptionKey: String?, options: ConversationOptions?) async throws -> AsyncThrowingStream<AgentChatUpdate, Error> {
        var memory: AgentInitialMemory?
        if let options {
            memory = AgentInitialMemory(variables: options.variables, secrets: options.secrets)
        }
        let request = AgentChatRequest(token: token, userMessageText: text, conversationID: conversationID, encryptionKey: encryptionKey, streamTransferEvents: true, memory: memory)
        var urlRequest = URLRequest(url: URL(string: "\(baseURL)/-/api/chat")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        return AsyncThrowingStream { continuation in
            let listener = AgentChatUpdateListener(urlSession: URLSession.shared, urlRequest: urlRequest) { update in
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

// Matches nested arguments type from EmbedChatHandler (Go)
struct AgentChatRequest: Codable {
    let token: String
    let userMessageText: String
    let conversationID: String?
    let encryptionKey: String?
    let streamTransferEvents: Bool?
    let memory: AgentInitialMemory?
}

// Matches agent.AgentMemory (Go)
struct AgentInitialMemory: Codable {
    let variables: [String: String]?
    let secrets: [String: String]?
}

// Matches agent.AgentTransfer (protobuf type)
struct AgentTransfer: Codable {
    struct Data: Codable {
        let key: String
        let value: String
    }
    let data: [Data]?
    let isSynchronous: Bool?

    enum CodingKeys: String, CodingKey {
        case data = "data"
        case isSynchronous = "is_synchronous"
    }
}

// Matches agent.StreamEvent (Go)
enum AgentStreamEvent {
    case message(text: String?, isEndOfMessage: Bool?, preparingFollowup: Bool?)
    case state
    case transfer(transfer: AgentTransfer)
    case error(error: String)
}

extension AgentStreamEvent: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.type) {
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "message":
                let text = try container.decodeIfPresent(String.self, forKey: .text)
                let isEndOfMessage = try container.decodeIfPresent(Bool.self, forKey: .isEndOfMessage)
                let preparingFollowup = try container.decodeIfPresent(Bool.self, forKey: .preparingFollowup)
                self = .message(text: text, isEndOfMessage: isEndOfMessage, preparingFollowup: preparingFollowup)
            case "state":
                self = .state
            case "transfer":
                let transfer = try container.decode(AgentTransfer.self, forKey: .transfer)
                self = .transfer(transfer: transfer)
            case "error":
                let error = try container.decode(String.self, forKey: .error)
                self = .error(error: error)
            default:
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type value: \(type)")
            }
        } else {
            throw DecodingError.keyNotFound(CodingKeys.type, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Type key not found"))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, text, isEndOfMessage, preparingFollowup, state, transfer, error
    }
}

// Matches api.setConversationIDChunk (Go)
struct SetConversationIDChunk: Codable {
    let conversationID: String
}

// Matches api.setEncryptionKeyChunk (Go)
struct SetEncryptionKeyChunk: Codable {
    let encryptionKey: String
}

enum AgentChatUpdate {
    case event(AgentStreamEvent)
    case setConversationID(SetConversationIDChunk)
    case setEncryptionKey(SetEncryptionKeyChunk)
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
    private let onUpdate: (AgentChatUpdate) -> Void
    private let onComplete: (Error?) -> Void
    private var buffer: String = ""

    init(urlSession: URLSession, urlRequest: URLRequest, onUpdate: @escaping ((AgentChatUpdate) -> Void), onComplete: @escaping ((Error?) -> Void)) {
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

    // Matches constants from server/api/chat.go
    static private let EVENT_BEGIN_MARKER = "BOT_CHAT_EVENT_BEGIN"
    static private let EVENT_END_MARKER = "BOT_CHAT_EVENT_END"

    private func parseUpdates() {
        while true {
            guard let updateStart = buffer.range(of: AgentChatUpdateListener.EVENT_BEGIN_MARKER) else { break }
            guard let updateEnd = buffer.range(of: AgentChatUpdateListener.EVENT_END_MARKER) else { break }

            let updateString = String(buffer[updateStart.upperBound..<updateEnd.lowerBound])
            buffer.removeSubrange(..<updateEnd.upperBound)
            do {
                onUpdate(try parseUpdate(from: updateString))
            } catch {
                task.cancel()
                onComplete(error)
                break
            }
        }
    }

    private func parseUpdate(from jsonString: String) throws -> AgentChatUpdate {
        let jsonData = Data(jsonString.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let decoded = try? decoder.decode(SetConversationIDChunk.self, from: jsonData) {
            return .setConversationID(decoded)
        } else if let decoded = try? decoder.decode(SetEncryptionKeyChunk.self, from: jsonData) {
            return .setEncryptionKey(decoded)
        } else if let decoded = try? decoder.decode(AgentStreamEvent.self, from: jsonData) {
            return .event(decoded)
        }
        throw AgentChatError.invalidChatUpdate
    }
}

