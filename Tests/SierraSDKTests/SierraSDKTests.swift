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

    func testAgentVoiceChatCoordinatorForwardsAgentAttachments() {
        let config = AgentConfig(token: "test-token")
        let agent = Agent(config: config)
        let coordinator = AgentVoiceChatCoordinator(
            agent: agent,
            options: .init(
                voiceOptions: AgentVoiceControllerOptions(name: "Voice"),
                chatOptions: AgentChatControllerOptions(name: "Chat")
            )
        )
        let delegate = CapturingVoiceCoordinatorDelegate()
        coordinator.delegate = delegate

        coordinator.didReceiveAgentAttachment(
            attachments: [
                AgentAttachment(type: "custom", data: ["deeplink": "sierra-test://order/123"]),
            ]
        )

        XCTAssertTrue(delegate.coordinator === coordinator)
        XCTAssertEqual(delegate.attachments?.first?.type, "custom")
        XCTAssertEqual(delegate.attachments?.first?.data["deeplink"] as? String, "sierra-test://order/123")
    }

    func testAgentVoiceChatCoordinatorEndRoutesToChatByDefault() {
        let config = AgentConfig(token: "test-token")
        let agent = Agent(config: config)
        let coordinator = AgentVoiceChatCoordinator(
            agent: agent,
            options: .init(
                voiceOptions: AgentVoiceControllerOptions(name: "Voice"),
                chatOptions: AgentChatControllerOptions(name: "Chat")
            )
        )
        let delegate = CapturingVoiceCoordinatorDelegate()
        coordinator.delegate = delegate

        coordinator.onVoiceEnded()

        XCTAssertEqual(delegate.showChatRequestCount, 1)
        XCTAssertEqual(delegate.voiceDidEndCount, 0)
    }

    func testAgentVoiceChatCoordinatorAutoShowChatCanBeDisabled() {
        let config = AgentConfig(token: "test-token")
        let agent = Agent(config: config)
        let coordinator = AgentVoiceChatCoordinator(
            agent: agent,
            options: .init(
                voiceOptions: AgentVoiceControllerOptions(name: "Voice"),
                chatOptions: AgentChatControllerOptions(name: "Chat"),
                autoShowChatOnEnd: false
            )
        )
        let delegate = CapturingVoiceCoordinatorDelegate()
        coordinator.delegate = delegate

        coordinator.onVoiceEnded()

        XCTAssertEqual(delegate.voiceDidEndCount, 1)
        XCTAssertEqual(delegate.showChatRequestCount, 0)
    }

    func testAgentVoiceChatCoordinatorAutoShowChatRequiresCanSwitchToChat() {
        let config = AgentConfig(token: "test-token")
        let agent = Agent(config: config)
        let coordinator = AgentVoiceChatCoordinator(
            agent: agent,
            options: .init(
                voiceOptions: AgentVoiceControllerOptions(name: "Voice"),
                chatOptions: AgentChatControllerOptions(name: "Chat"),
                canSwitchToChat: false,
                autoShowChatOnEnd: true
            )
        )
        let delegate = CapturingVoiceCoordinatorDelegate()
        coordinator.delegate = delegate

        coordinator.onVoiceEnded()

        XCTAssertEqual(delegate.voiceDidEndCount, 1)
        XCTAssertEqual(delegate.showChatRequestCount, 0)
    }

    func testConversationStateForwardedAsStateQueryItem() {
        let options = AgentChatControllerOptions(name: "Test")
        let queryItems = options.toQueryItems(conversationState: "abc123")
        let stateItems = queryItems.filter { $0.name == "state" }

        XCTAssertEqual(stateItems.count, 1)
        XCTAssertEqual(stateItems.first?.value, "abc123")
    }

    func testConversationStateOmittedWhenNilOrEmpty() {
        let options = AgentChatControllerOptions(name: "Test")
        XCTAssertFalse(options.toQueryItems().contains { $0.name == "state" })
        XCTAssertFalse(options.toQueryItems(conversationState: nil).contains { $0.name == "state" })
        XCTAssertFalse(options.toQueryItems(conversationState: "").contains { $0.name == "state" })
    }

    func testUpdateVariablesAndSecretsOnSessionResumeForwardedAsQueryItem() {
        var options = AgentChatControllerOptions(name: "Test")
        options.updateVariablesAndSecretsOnSessionResume = true
        let queryItems = options.toQueryItems()
        let items = queryItems.filter { $0.name == "updateVariablesAndSecretsOnSessionResume" }

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.value, "true")
    }

    func testUpdateVariablesAndSecretsOnSessionResumeOmittedByDefault() {
        let options = AgentChatControllerOptions(name: "Test")
        XCTAssertFalse(
            options.toQueryItems().contains { $0.name == "updateVariablesAndSecretsOnSessionResume" }
        )
    }

    func testVariablesAndSecretsAreNotAddedToQueryItems() {
        var conversationOptions = ConversationOptions()
        conversationOptions.variables = ["userId": "12345"]
        conversationOptions.secrets = ["authToken": "abc123"]
        var options = AgentChatControllerOptions(name: "Test")
        options.conversationOptions = conversationOptions

        // Variables and secrets are delivered via the window.__sierraInitialMemory bridge global,
        // never as URL query parameters, so they cannot leak into logs.
        let queryItems = options.toQueryItems()
        XCTAssertFalse(queryItems.contains { $0.name == "variable" })
        XCTAssertFalse(queryItems.contains { $0.name == "secret" })
    }

    @MainActor
    func testAgentChatControllerDeallocatesAfterRelease() {
        let agent = Agent(config: AgentConfig(token: "test-token"))
        weak var weakController: AgentChatController?
        autoreleasepool {
            let controller = AgentChatController(agent: agent, options: AgentChatControllerOptions(name: "Test"))
            weakController = controller
            XCTAssertNotNil(weakController)
        }
        XCTAssertNil(weakController, "AgentChatController must deallocate; a WKScriptMessageHandler retain cycle is leaking it")
    }
}

private final class CapturingVoiceCoordinatorDelegate: AgentVoiceChatCoordinatorDelegate {
    weak var coordinator: AgentVoiceChatCoordinator?
    var attachments: [AgentAttachment]?
    var showChatRequestCount = 0
    var voiceDidEndCount = 0

    func coordinatorDidRequestShowingChat(_ coordinator: AgentVoiceChatCoordinator) {
        showChatRequestCount += 1
    }

    func coordinatorDidRequestVoiceReconnect(_ coordinator: AgentVoiceChatCoordinator) {}

    func coordinatorVoiceDidEnd(_ coordinator: AgentVoiceChatCoordinator) {
        voiceDidEndCount += 1
    }

    func coordinator(
        _ coordinator: AgentVoiceChatCoordinator,
        didReceiveAgentAttachment attachments: [AgentAttachment]
    ) {
        self.coordinator = coordinator
        self.attachments = attachments
    }
}
