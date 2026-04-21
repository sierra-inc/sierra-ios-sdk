// Copyright Sierra

import SierraSDK

/// Voice-only URL derivations. Live in the voice target so the chat-only SDK
/// doesn't expose voice-specific surface. Pair with the Android layout where
/// `conversationRendererURL` and `voiceBaseURL` are extensions in `:lib-voice`.

extension AgentConfig {
    var conversationRendererURL: String {
        return "\(apiHost.embedBaseURL)/agent/\(token)/mobile-renderer"
    }
}

extension AgentAPIHost {
    /// Voice/SVP endpoints are served on a separate port in local dev.
    /// In production, voice shares the same host as the API.
    var voiceBaseURL: String {
        switch self {
        case .local:
            return "https://sierra.codes:8084"
        default:
            return apiBaseURL
        }
    }
}
