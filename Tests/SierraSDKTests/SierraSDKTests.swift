// Copyright Sierra

import XCTest
@testable import SierraSDK
import SierraSDKVoice

final class SierraSDKTests: XCTestCase {
    func testAgentConfigDefaults() {
        let config = AgentConfig(token: "test-token")

        XCTAssertEqual(config.token, "test-token")
        XCTAssertNil(config.target)
        XCTAssertEqual(config.persistence, .memory)
        XCTAssertNil(config.headlessAPIToken)
    }

    func testAgentVoiceChatCoordinatorRestoresPersistedConversationState() throws {
        let config = AgentConfig(token: "test-token")
        let agent = Agent(config: config)

        let storedState: [String: String] = [
            "conversationID": "chat-123",
            "encryptionKey": "enc-123",
            "voiceConversationID": "voice-123",
        ]
        let data = try JSONSerialization.data(withJSONObject: storedState)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        agent.getStorage().setItem("embed-chat-test-token", json)

        let coordinator = AgentVoiceChatCoordinator(
            agent: agent,
            options: .init(
                voiceOptions: AgentVoiceControllerOptions(name: "Voice"),
                chatOptions: AgentChatControllerOptions(name: "Chat")
            )
        )

        XCTAssertEqual(coordinator.conversationID, "chat-123")
        XCTAssertEqual(coordinator.encryptionKey, "enc-123")
        XCTAssertEqual(coordinator.voiceConversationID, "voice-123")
    }
}
