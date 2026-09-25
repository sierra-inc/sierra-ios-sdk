// Copyright Sierra

import UIKit
import WebKit
import XCTest
@testable import SierraSDK
@testable import SierraSDKVoice

final class SierraSDKTests: XCTestCase {
    private func brandJSON(_ options: AgentChatControllerOptions) throws -> [String: Any] {
        let value = try XCTUnwrap(options.toQueryItems().first { $0.name == "brand" }?.value)
        let data = try XCTUnwrap(value.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testAgentVoiceControllerOptionsCompactControlsAreOptIn() {
        var options = AgentVoiceControllerOptions(name: "Voice")

        XCTAssertFalse(options.useCompactControls)
        options.useCompactControls = true
        XCTAssertTrue(options.useCompactControls)
    }

    func testAgentConfigDefaults() {
        let config = AgentConfig(token: "test-token")

        XCTAssertEqual(config.token, "test-token")
        XCTAssertNil(config.target)
        XCTAssertEqual(config.persistence, .memory)
        XCTAssertNil(config.svpHeadlessAPIToken)
        XCTAssertNil(config.oauthAccessToken)
    }

    func testRegionalAgentAPIHosts() {
        XCTAssertEqual(AgentAPIHost.jp.apiBaseURL, "https://jp.api.sierra.chat")
        XCTAssertEqual(AgentAPIHost.jp.embedBaseURL, "https://jp.sierra.chat")
        XCTAssertEqual(AgentAPIHost.au.apiBaseURL, "https://au.api.sierra.chat")
        XCTAssertEqual(AgentAPIHost.au.embedBaseURL, "https://au.sierra.chat")
    }

    @MainActor
    func testMobileRendererAdvertisesFullscreenOnlyForSupportedHost() {
        let agent = Agent(config: AgentConfig(token: "test-token"))
        let options = AgentVoiceControllerOptions(name: "Voice")

        let standaloneItems = MobileRendererView.rendererQueryItems(
            agent: agent,
            options: options,
            supportsFullscreen: false
        )
        let hostedItems = MobileRendererView.rendererQueryItems(
            agent: agent,
            options: options,
            supportsFullscreen: true
        )

        XCTAssertFalse(standaloneItems.contains { $0.name == "supportsFullscreen" })
        XCTAssertEqual(hostedItems.first { $0.name == "supportsFullscreen" }?.value, "true")
    }

    // Exercises the deprecated headlessAPIToken path that shipped apps still use.
    @available(*, deprecated)
    func testSVPTransportUsesOAuthAuthorizationHeadersBeforeHeadlessToken() throws {
        let config = AgentConfig(
            token: "test-token",
            headlessAPIToken: "headless-token",
            oauthAccessToken: "oauth-token"
        )
        let transport = SVPTransport(config: config)

        let request = transport.makeWebSocketRequest(url: try XCTUnwrap(URL(string: "wss://example.com")))

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer oauth-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Sierra-Token-Version"), "2")
        XCTAssertNil(request.value(forHTTPHeaderField: "Sec-WebSocket-Protocol"))
    }

    // Exercises the deprecated headlessAPIToken path that shipped apps still use.
    @available(*, deprecated)
    func testSVPTransportFallsBackToHeadlessToken() throws {
        let config = AgentConfig(token: "test-token", headlessAPIToken: "headless-token")
        let transport = SVPTransport(config: config)

        let request = transport.makeWebSocketRequest(url: try XCTUnwrap(URL(string: "wss://example.com")))

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer headless-token")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Sierra-Token-Version"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Sec-WebSocket-Protocol"))
    }

    func testVoiceSessionOpenIncludesUserIdentityToken() {
        let agent = Agent(config: AgentConfig(token: "test-token"))
        let controller = AgentVoiceController(agent: agent)
        let authenticatedSession = VoiceSessionManager(
            config: agent.config,
            userIdentityToken: "user-identity-token",
            delegate: controller
        )
        let anonymousSession = VoiceSessionManager(
            config: agent.config,
            userIdentityToken: "",
            delegate: controller
        )

        XCTAssertEqual(
            authenticatedSession.makeOpenSubMessage()["userIdentityToken"] as? String,
            "user-identity-token"
        )
        XCTAssertEqual(
            authenticatedSession.makeOpenSubMessage()["compatibilityDate"] as? String,
            "2026-08-27"
        )
        XCTAssertNil(anonymousSession.makeOpenSubMessage()["userIdentityToken"])
    }

    func testAgentVoiceChatCoordinatorSharesChatUserIdentityTokenWithVoice() {
        let agent = Agent(config: AgentConfig(token: "test-token"))
        var voiceOptions = AgentVoiceControllerOptions(name: "Voice")
        voiceOptions.userIdentityToken = ""
        var chatOptions = AgentChatControllerOptions(name: "Chat")
        chatOptions.userIdentityToken = "user-identity-token"
        let coordinator = AgentVoiceChatCoordinator(
            agent: agent,
            options: .init(
                voiceOptions: voiceOptions,
                chatOptions: chatOptions
            )
        )

        XCTAssertEqual(
            coordinator.makeVoiceController().options.userIdentityToken,
            "user-identity-token"
        )
    }

    func testAgentVoiceChatCoordinatorSharesVoiceUserIdentityTokenWithChat() {
        let agent = Agent(config: AgentConfig(token: "test-token"))
        var voiceOptions = AgentVoiceControllerOptions(name: "Voice")
        voiceOptions.userIdentityToken = "user-identity-token"
        var chatOptions = AgentChatControllerOptions(name: "Chat")
        chatOptions.userIdentityToken = ""
        let coordinator = AgentVoiceChatCoordinator(
            agent: agent,
            options: .init(
                voiceOptions: voiceOptions,
                chatOptions: chatOptions
            )
        )

        XCTAssertEqual(
            coordinator.makeChatController().options.userIdentityToken,
            "user-identity-token"
        )
    }

    func testAgentVoiceChatCoordinatorDoesNotShareEmptyUserIdentityToken() {
        let agent = Agent(config: AgentConfig(token: "test-token"))
        var voiceOptions = AgentVoiceControllerOptions(name: "Voice")
        voiceOptions.userIdentityToken = ""
        let coordinator = AgentVoiceChatCoordinator(
            agent: agent,
            options: .init(
                voiceOptions: voiceOptions,
                chatOptions: AgentChatControllerOptions(name: "Chat")
            )
        )

        XCTAssertNil(coordinator.makeVoiceController().options.userIdentityToken)
        XCTAssertNil(coordinator.makeChatController().options.userIdentityToken)
    }

    func testAgentVoiceChatCoordinatorRestoresPersistedConversationState() throws {
        let config = AgentConfig(token: "test-token")
        let agent = Agent(config: config)
        try persistConversationState(
            agent: agent,
            voiceConversationID: "voice-123",
            voiceResumeToken: "resume-123"
        )
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
        XCTAssertEqual(coordinator.voiceResumeToken, "resume-123")
    }

    func testAgentVoiceChatCoordinatorVoiceLaunchWithoutReconnectStartsFreshKeepingPersistedChatState() throws {
        let config = AgentConfig(token: "test-token")
        let agent = Agent(config: config)
        try persistConversationState(
            agent: agent,
            voiceConversationID: "voice-123",
            voiceResumeToken: "resume-123"
        )
        let coordinator = AgentVoiceChatCoordinator(
            agent: agent,
            options: .init(
                voiceOptions: AgentVoiceControllerOptions(name: "Voice"),
                chatOptions: AgentChatControllerOptions(name: "Chat")
            )
        )

        let voiceController = coordinator.makeVoiceController()

        withExtendedLifetime(voiceController) {
            XCTAssertFalse(voiceController.options.resumeConversation)
            XCTAssertNil(voiceController.options.resumeToken)
            XCTAssertTrue(voiceController.options.continueInChatOnDismiss)
            XCTAssertNotNil(coordinator.voiceConversationID)
            XCTAssertNotEqual(coordinator.voiceConversationID, "voice-123")
            XCTAssertNil(coordinator.voiceResumeToken)
            // In-memory chat credentials are cleared so an early dismissal can't seed the prior
            // conversation against the new voice ID; persisted storage keeps it resumable in chat.
            XCTAssertNil(coordinator.conversationID)
            XCTAssertNil(coordinator.encryptionKey)
            XCTAssertNotNil(agent.getStorage().getItem("embed-chat-test-token"))
        }
    }

    func testAgentVoiceChatCoordinatorPrepareVoiceReconnectResumesOnce() throws {
        let config = AgentConfig(token: "test-token")
        let agent = Agent(config: config)
        try persistConversationState(
            agent: agent,
            voiceConversationID: "voice-123",
            voiceResumeToken: "resume-123"
        )
        let coordinator = AgentVoiceChatCoordinator(
            agent: agent,
            options: .init(
                voiceOptions: AgentVoiceControllerOptions(name: "Voice"),
                chatOptions: AgentChatControllerOptions(name: "Chat")
            )
        )

        coordinator.prepareVoiceReconnect()
        let reconnectController = coordinator.makeVoiceController()

        withExtendedLifetime(reconnectController) {
            XCTAssertTrue(reconnectController.options.resumeConversation)
            XCTAssertEqual(reconnectController.options.resumeToken, "resume-123")
            XCTAssertEqual(reconnectController.options.resumeReason, .continueInVoice)
            XCTAssertEqual(reconnectController.options.voiceConversationID, "voice-123")
        }

        // The latch is one-shot: the next launch starts fresh.
        let freshController = coordinator.makeVoiceController()

        withExtendedLifetime(freshController) {
            XCTAssertFalse(freshController.options.resumeConversation)
            XCTAssertNil(freshController.options.resumeToken)
            XCTAssertNotEqual(freshController.options.voiceConversationID, "voice-123")
        }
    }

    func testAgentVoiceChatCoordinatorDifferentConfiguredVoiceConversationIDStartsFresh() throws {
        let config = AgentConfig(token: "test-token")
        let agent = Agent(config: config)
        try persistConversationState(
            agent: agent,
            voiceConversationID: "voice-123",
            voiceResumeToken: "resume-123"
        )

        var voiceOptions = AgentVoiceControllerOptions(name: "Voice")
        voiceOptions.voiceConversationID = "voice-456"
        let coordinator = AgentVoiceChatCoordinator(
            agent: agent,
            options: .init(
                voiceOptions: voiceOptions,
                chatOptions: AgentChatControllerOptions(name: "Chat")
            )
        )

        XCTAssertEqual(coordinator.conversationID, "chat-123")
        XCTAssertEqual(coordinator.voiceConversationID, "voice-123")
        XCTAssertNotNil(agent.getStorage().getItem("embed-chat-test-token"))

        let voiceController = coordinator.makeVoiceController()

        withExtendedLifetime(voiceController) {
            XCTAssertNil(coordinator.conversationID)
            XCTAssertNil(coordinator.encryptionKey)
            XCTAssertEqual(coordinator.voiceConversationID, "voice-456")
            XCTAssertNil(coordinator.voiceResumeToken)
            XCTAssertNil(agent.getStorage().getItem("embed-chat-test-token"))
        }
    }

    func testAgentVoiceChatCoordinatorKeepsChatOnlyStateUntilVoiceStarts() throws {
        let config = AgentConfig(token: "test-token")
        let agent = Agent(config: config)
        try persistConversationState(
            agent: agent,
            voiceConversationID: nil,
            voiceResumeToken: nil
        )

        var voiceOptions = AgentVoiceControllerOptions(name: "Voice")
        voiceOptions.voiceConversationID = "voice-456"
        let coordinator = AgentVoiceChatCoordinator(
            agent: agent,
            options: .init(
                voiceOptions: voiceOptions,
                chatOptions: AgentChatControllerOptions(name: "Chat")
            )
        )

        let chatController = coordinator.makeChatController()
        withExtendedLifetime(chatController) {
            XCTAssertEqual(coordinator.conversationID, "chat-123")
            XCTAssertEqual(coordinator.encryptionKey, "enc-123")
            XCTAssertNotNil(agent.getStorage().getItem("embed-chat-test-token"))
        }

        let voiceController = coordinator.makeVoiceController()
        withExtendedLifetime(voiceController) {
            XCTAssertNil(coordinator.conversationID)
            XCTAssertNil(coordinator.encryptionKey)
            XCTAssertEqual(coordinator.voiceConversationID, "voice-456")
            XCTAssertNil(coordinator.voiceResumeToken)
            XCTAssertNil(agent.getStorage().getItem("embed-chat-test-token"))
        }
    }

    func testAgentVoiceChatCoordinatorRepeatedVoiceLaunchesStartFreshConversations() {
        let coordinator = AgentVoiceChatCoordinator(
            agent: Agent(config: AgentConfig(token: "test-token")),
            options: .init(
                voiceOptions: AgentVoiceControllerOptions(name: "Voice"),
                chatOptions: AgentChatControllerOptions(name: "Chat")
            )
        )

        let firstVoiceController = coordinator.makeVoiceController()
        let firstVoiceConversationID = coordinator.voiceConversationID
        let secondVoiceController = coordinator.makeVoiceController()

        withExtendedLifetime((firstVoiceController, secondVoiceController)) {
            XCTAssertNotNil(firstVoiceConversationID)
            XCTAssertNotNil(coordinator.voiceConversationID)
            XCTAssertNotEqual(coordinator.voiceConversationID, firstVoiceConversationID)
            XCTAssertNil(coordinator.voiceResumeToken)
        }
    }

    func testAgentVoiceChatCoordinatorDismissalSeedsChatContinuationState() throws {
        let agent = Agent(config: AgentConfig(token: "test-token"))
        let coordinator = AgentVoiceChatCoordinator(
            agent: agent,
            options: .init(
                voiceOptions: AgentVoiceControllerOptions(name: "Voice"),
                chatOptions: AgentChatControllerOptions(name: "Chat")
            )
        )

        let voiceController = coordinator.makeVoiceController()
        try withExtendedLifetime(voiceController) {
            coordinator.onSessionInfoReceived(conversationID: "chat-1", encryptionKey: "enc-1")
            coordinator.onResumeTokenReceived(token: "resume-1")

            coordinator.onVoiceDismissed()

            let state = try XCTUnwrap(loadSeededConversationState(agent: agent))
            XCTAssertEqual(state["conversationID"] as? String, "chat-1")
            XCTAssertEqual(state["encryptionKey"] as? String, "enc-1")
            XCTAssertEqual(state["continueInChatOnResume"] as? Bool, true)
            XCTAssertNil(state["agentHandoffOnResume"])
            XCTAssertEqual(state["voiceResumeToken"] as? String, "resume-1")
            XCTAssertEqual(coordinator.conversationID, "chat-1")
            XCTAssertEqual(coordinator.encryptionKey, "enc-1")
        }
    }

    @MainActor
    func testAgentVoiceChatCoordinatorDismissalOverridesConversationListDefaultOnce() {
        var chatOptions = AgentChatControllerOptions(name: "Chat")
        chatOptions.userIdentityToken = "user-identity-token"
        chatOptions.enableConversationList = true
        chatOptions.showConversationListByDefault = true
        let coordinator = AgentVoiceChatCoordinator(
            agent: Agent(config: AgentConfig(token: "test-token")),
            options: .init(
                voiceOptions: AgentVoiceControllerOptions(name: "Voice"),
                chatOptions: chatOptions
            )
        )

        let voiceController = coordinator.makeVoiceController()
        withExtendedLifetime(voiceController) {
            coordinator.onSessionInfoReceived(conversationID: "chat-1", encryptionKey: "enc-1")
            coordinator.onVoiceDismissed()

            let continuationController = coordinator.makeChatController()
            let ordinaryController = coordinator.makeChatController()

            if #available(iOS 16.0, *) {
                XCTAssertNotNil(continuationController.navigationItem.backAction)
                XCTAssertNil(ordinaryController.navigationItem.backAction)
            } else {
                XCTAssertNotNil(continuationController.navigationItem.leftBarButtonItem)
                XCTAssertNil(ordinaryController.navigationItem.leftBarButtonItem)
            }
        }
    }

    @MainActor
    func testAgentVoiceChatCoordinatorRestoredDismissalContinuationSuppressesConversationList() {
        let agent = Agent(config: AgentConfig(token: "test-token"))
        var chatOptions = AgentChatControllerOptions(name: "Chat")
        chatOptions.userIdentityToken = "user-identity-token"
        chatOptions.enableConversationList = true
        chatOptions.showConversationListByDefault = true
        let firstCoordinator = AgentVoiceChatCoordinator(
            agent: agent,
            options: .init(
                voiceOptions: AgentVoiceControllerOptions(name: "Voice"),
                chatOptions: chatOptions
            )
        )
        let voiceController = firstCoordinator.makeVoiceController()
        withExtendedLifetime(voiceController) {
            firstCoordinator.onSessionInfoReceived(conversationID: "chat-1", encryptionKey: "enc-1")
            firstCoordinator.onVoiceDismissed()
        }

        // Simulates an app restart before chat is opened.
        let recreatedCoordinator = AgentVoiceChatCoordinator(
            agent: agent,
            options: .init(
                voiceOptions: AgentVoiceControllerOptions(name: "Voice"),
                chatOptions: chatOptions
            )
        )
        let continuationController = recreatedCoordinator.makeChatController()

        if #available(iOS 16.0, *) {
            XCTAssertNotNil(continuationController.navigationItem.backAction)
        } else {
            XCTAssertNotNil(continuationController.navigationItem.leftBarButtonItem)
        }
    }

    func testAgentVoiceChatCoordinatorDismissalAfterVoiceErrorResets() {
        let agent = Agent(config: AgentConfig(token: "test-token"))
        let coordinator = AgentVoiceChatCoordinator(
            agent: agent,
            options: .init(
                voiceOptions: AgentVoiceControllerOptions(name: "Voice"),
                chatOptions: AgentChatControllerOptions(name: "Chat")
            )
        )

        let voiceController = coordinator.makeVoiceController()
        withExtendedLifetime(voiceController) {
            coordinator.onSessionInfoReceived(conversationID: "chat-1", encryptionKey: "enc-1")
            coordinator.onResumeTokenReceived(token: "resume-1")
            coordinator.onVoiceError(error: TestVoiceError.connectionFailed)

            coordinator.onVoiceDismissed()

            XCTAssertNil(coordinator.conversationID)
            XCTAssertNil(coordinator.encryptionKey)
            XCTAssertNil(coordinator.voiceConversationID)
            XCTAssertNil(coordinator.voiceResumeToken)
            XCTAssertNil(agent.getStorage().getItem("embed-chat-test-token"))
        }
    }

    func testAgentVoiceChatCoordinatorDismissalWithoutCredentialsLeavesNoState() {
        let agent = Agent(config: AgentConfig(token: "test-token"))
        let coordinator = AgentVoiceChatCoordinator(
            agent: agent,
            options: .init(
                voiceOptions: AgentVoiceControllerOptions(name: "Voice"),
                chatOptions: AgentChatControllerOptions(name: "Chat")
            )
        )

        let voiceController = coordinator.makeVoiceController()
        withExtendedLifetime(voiceController) {
            coordinator.onVoiceDismissed()

            XCTAssertNil(coordinator.conversationID)
            XCTAssertNil(coordinator.voiceConversationID)
            XCTAssertNil(agent.getStorage().getItem("embed-chat-test-token"))
        }
    }

    func testAgentVoiceChatCoordinatorDismissalBeforeSessionInfoPreservesPriorConversation() throws {
        let agent = Agent(config: AgentConfig(token: "test-token"))
        try persistConversationState(
            agent: agent,
            voiceConversationID: "voice-123",
            voiceResumeToken: "resume-123"
        )
        let coordinator = AgentVoiceChatCoordinator(
            agent: agent,
            options: .init(
                voiceOptions: AgentVoiceControllerOptions(name: "Voice"),
                chatOptions: AgentChatControllerOptions(name: "Chat")
            )
        )

        let voiceController = coordinator.makeVoiceController()
        try withExtendedLifetime(voiceController) {
            coordinator.onVoiceDismissed()

            // The abandoned launch leaves the persisted conversation untouched and re-syncs memory
            // to it, so the prior conversation keeps working -- including explicit voice reconnect.
            XCTAssertEqual(coordinator.conversationID, "chat-123")
            XCTAssertEqual(coordinator.encryptionKey, "enc-123")
            XCTAssertEqual(coordinator.voiceConversationID, "voice-123")
            XCTAssertEqual(coordinator.voiceResumeToken, "resume-123")
            let state = try XCTUnwrap(loadSeededConversationState(agent: agent))
            XCTAssertEqual(state["voiceConversationID"] as? String, "voice-123")
            XCTAssertEqual(state["voiceResumeToken"] as? String, "resume-123")
        }

        coordinator.prepareVoiceReconnect()
        let reconnectController = coordinator.makeVoiceController()
        withExtendedLifetime(reconnectController) {
            XCTAssertTrue(reconnectController.options.resumeConversation)
            XCTAssertEqual(reconnectController.options.resumeToken, "resume-123")
            XCTAssertEqual(reconnectController.options.voiceConversationID, "voice-123")
        }
    }

    func testAgentVoiceChatCoordinatorErrorBeforeSessionInfoPreservesPriorConversation() throws {
        let agent = Agent(config: AgentConfig(token: "test-token"))
        try persistConversationState(
            agent: agent,
            voiceConversationID: "voice-123",
            voiceResumeToken: "resume-123"
        )
        let coordinator = AgentVoiceChatCoordinator(
            agent: agent,
            options: .init(
                voiceOptions: AgentVoiceControllerOptions(name: "Voice"),
                chatOptions: AgentChatControllerOptions(name: "Chat")
            )
        )

        let voiceController = coordinator.makeVoiceController()
        withExtendedLifetime(voiceController) {
            coordinator.onVoiceError(error: TestVoiceError.connectionFailed)
            coordinator.onVoiceDismissed()

            XCTAssertEqual(coordinator.conversationID, "chat-123")
            XCTAssertEqual(coordinator.voiceConversationID, "voice-123")
            XCTAssertEqual(coordinator.voiceResumeToken, "resume-123")
            XCTAssertNotNil(agent.getStorage().getItem("embed-chat-test-token"))
        }
    }

    func testAgentVoiceChatCoordinatorVoiceAfterDismissalStartsFreshConversation() throws {
        let agent = Agent(config: AgentConfig(token: "test-token"))
        let coordinator = AgentVoiceChatCoordinator(
            agent: agent,
            options: .init(
                voiceOptions: AgentVoiceControllerOptions(name: "Voice"),
                chatOptions: AgentChatControllerOptions(name: "Chat")
            )
        )

        let firstController = coordinator.makeVoiceController()
        var dismissedVoiceConversationID: String?
        withExtendedLifetime(firstController) {
            coordinator.onSessionInfoReceived(conversationID: "chat-1", encryptionKey: "enc-1")
            coordinator.onResumeTokenReceived(token: "resume-1")
            coordinator.onVoiceDismissed()
            dismissedVoiceConversationID = coordinator.voiceConversationID
        }

        let secondController = coordinator.makeVoiceController()
        try withExtendedLifetime(secondController) {
            XCTAssertNotNil(dismissedVoiceConversationID)
            XCTAssertFalse(secondController.options.resumeConversation)
            XCTAssertNil(secondController.options.resumeToken)
            XCTAssertNotEqual(secondController.options.voiceConversationID, dismissedVoiceConversationID)
            // The dismissed conversation stays resumable in chat via persisted storage.
            XCTAssertNil(coordinator.conversationID)
            let state = try XCTUnwrap(loadSeededConversationState(agent: agent))
            XCTAssertEqual(state["conversationID"] as? String, "chat-1")
        }
    }

    func testAgentVoiceChatCoordinatorVoiceLaunchDropsStaleHandoffLatch() {
        let agent = Agent(config: AgentConfig(token: "test-token"))
        let coordinator = AgentVoiceChatCoordinator(
            agent: agent,
            options: .init(
                voiceOptions: AgentVoiceControllerOptions(name: "Voice"),
                chatOptions: AgentChatControllerOptions(name: "Chat")
            )
        )

        let firstVoiceController = coordinator.makeVoiceController()
        withExtendedLifetime(firstVoiceController) {
            coordinator.onSessionInfoReceived(conversationID: "chat-1", encryptionKey: "enc-1")
            // The agent requests a handoff but the host never presents chat.
            firstVoiceController.options.onSwitchToChat?(true)
        }

        let secondVoiceController = coordinator.makeVoiceController()
        coordinator.onSessionInfoReceived(conversationID: "chat-2", encryptionKey: "enc-2")
        let chatController = coordinator.makeChatController()

        withExtendedLifetime((secondVoiceController, chatController)) {
            // The stale handoff must not seed resume flags for the new conversation.
            XCTAssertNil(agent.getStorage().getItem("embed-chat-test-token"))
        }
    }

    private func loadSeededConversationState(agent: Agent) throws -> [String: Any]? {
        guard let json = agent.getStorage().getItem("embed-chat-test-token") else { return nil }
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func persistConversationState(
        agent: Agent,
        voiceConversationID: String?,
        voiceResumeToken: String?
    ) throws {
        var storedState: [String: String] = [
            "conversationID": "chat-123",
            "encryptionKey": "enc-123",
        ]
        storedState["voiceConversationID"] = voiceConversationID
        storedState["voiceResumeToken"] = voiceResumeToken
        let data = try JSONSerialization.data(withJSONObject: storedState)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        agent.getStorage().setItem("embed-chat-test-token", json)
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

    @MainActor
    func testAgentVoiceChatCoordinatorHandoffOverridesConversationListDefaultOnce() {
        var chatOptions = AgentChatControllerOptions(name: "Chat")
        chatOptions.userIdentityToken = "user-identity-token"
        chatOptions.enableConversationList = true
        chatOptions.showConversationListByDefault = true
        let coordinator = AgentVoiceChatCoordinator(
            agent: Agent(config: AgentConfig(token: "test-token")),
            options: .init(
                voiceOptions: AgentVoiceControllerOptions(name: "Voice"),
                chatOptions: chatOptions
            )
        )

        coordinator.onVoiceEnded()
        let handoffController = coordinator.makeChatController()
        let ordinaryController = coordinator.makeChatController()

        if #available(iOS 16.0, *) {
            XCTAssertNotNil(handoffController.navigationItem.backAction)
            XCTAssertNil(ordinaryController.navigationItem.backAction)
        } else {
            XCTAssertNotNil(handoffController.navigationItem.leftBarButtonItem)
            XCTAssertNil(ordinaryController.navigationItem.leftBarButtonItem)
        }
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

    func testAgentVoiceChatCoordinatorAutoShowChatDoesNotRequireCanSwitchToChat() {
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

        XCTAssertEqual(delegate.voiceDidEndCount, 0)
        XCTAssertEqual(delegate.showChatRequestCount, 1)
    }

    func testAgentVoiceChatCoordinatorCanHideSwitchButtonWhileAutoShowingChatOnEnd() {
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

        let voiceController = coordinator.makeVoiceController()

        XCTAssertNil(voiceController.navigationItem.rightBarButtonItem)
    }

    @MainActor
    func testVoiceErrorDisablesSessionControlsButKeepsExitAvailable() async {
        let muteButton = UIButton()
        let unmuteButton = UIButton()
        let endButton = UIButton()
        var options = AgentVoiceControllerOptions(name: "Voice")
        options.hideTitleBar = true
        options.muteButton = muteButton
        options.unmuteButton = unmuteButton
        options.endCallButton = endButton
        let agent = Agent(config: AgentConfig(token: "test-token"))
        let controller = AgentVoiceController(
            agent: agent,
            options: options,
            automaticallyStartsVoiceSession: false
        )
        let callbacks = CapturingVoiceCallbacks()
        controller.voiceCallbacks = callbacks
        controller.loadViewIfNeeded()
        let session = VoiceSessionManager(config: AgentConfig(token: "test-token"), delegate: controller)

        controller.voiceSession(session, didEncounterError: TestVoiceError.connectionFailed)
        controller.voiceSession(session, didChangeState: .ended)
        controller.voiceSession(session, didChangeState: .listening)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }

        XCTAssertEqual(callbacks.errorCount, 1)
        XCTAssertFalse(muteButton.isEnabled)
        XCTAssertTrue(endButton.isEnabled)

        controller.endConversation()

        XCTAssertEqual(callbacks.endCount, 1)
    }

    func testInitialConversationStaysOutOfQueryItems() {
        var options = AgentChatControllerOptions(name: "Test")
        options.userIdentityToken = "user-identity-token"
        XCTAssertFalse(options.toQueryItems().contains {
            ["userIdentityToken", "state", "conversationID"].contains($0.name)
        })
        let payload = options.initialConversation(conversationState: nil, conversationID: "external-123")
        XCTAssertEqual(payload["userIdentityToken"] as? String, "user-identity-token")
        XCTAssertEqual(payload["target"] as? [String: String], ["kind": "conversationID", "conversationID": "external-123"])
    }

    func testInitialConversationRequiresIdentityOnlyForConversationID() {
        let options = AgentChatControllerOptions(name: "Test")
        for state in [nil, ""] as [String?] {
            let payload = options.initialConversation(conversationState: state, conversationID: nil)
            XCTAssertEqual(payload["target"] as? [String: String], ["kind": "none"])
        }
        for identity in [nil, ""] as [String?] {
            var anonymousOptions = options
            anonymousOptions.userIdentityToken = identity
            let payload = anonymousOptions.initialConversation(conversationState: nil, conversationID: "external-123")
            XCTAssertNil(payload["userIdentityToken"])
            XCTAssertEqual(payload["target"] as? [String: String], ["kind": "none"])
        }
        let payload = options.initialConversation(conversationState: "opaque-state", conversationID: "external-123")
        XCTAssertEqual(payload["target"] as? [String: String], ["kind": "state", "state": "opaque-state"])
    }

    // Covers a reload before the embed has resolved the target. Once it has,
    // WebViewAsyncJavaScriptTests covers the target no longer being replayed.
    @MainActor
    func testInitialConversationScriptSurvivesAppearanceReload() throws {
        var options = AgentChatControllerOptions(name: "Test")
        options.userIdentityToken = "identity-with-\\-and-\"-and-\u{2028}"
        let controller = AgentChatController(
            agent: Agent(config: AgentConfig(token: "test-token")),
            options: options,
            conversationState: "opaque-state",
            conversationID: "external-123"
        )
        controller.overrideUserInterfaceStyle = .light
        controller.loadViewIfNeeded()
        let webView = try XCTUnwrap(findWebView(in: controller.view))
        let expected = options.initialConversation(conversationState: "opaque-state", conversationID: "external-123")
        for appearance in [UIUserInterfaceStyle.light, .dark] {
            if appearance == .dark {
                webView.configuration.userContentController.removeAllUserScripts()
                controller.overrideUserInterfaceStyle = appearance
                controller.traitCollectionDidChange(UITraitCollection(userInterfaceStyle: .light))
            }
            let prefix = "window.__sierraInitialConversation = "
            let script = try XCTUnwrap(webView.configuration.userContentController.userScripts.first {
                $0.source.hasPrefix(prefix)
            })
            XCTAssertEqual(script.injectionTime, .atDocumentStart)
            XCTAssertTrue(script.isForMainFrameOnly)
            let json = String(script.source.dropFirst(prefix.count).dropLast())
            let actual = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary
            XCTAssertEqual(actual, expected as NSDictionary)
        }
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

    func testConfirmEndConversationModeDefaultsToAlwaysAndIsOmittedFromURL() {
        let options = AgentChatControllerOptions(name: "Test")

        XCTAssertEqual(options.confirmEndConversationMode, .always)
        XCTAssertFalse(
            options.toQueryItems().contains { $0.name == "confirmEndConversationMode" }
        )
    }

    func testLiveChatConfirmEndConversationModeIsForwardedAsQueryItem() {
        var options = AgentChatControllerOptions(name: "Test")
        options.confirmEndConversationMode = .liveChat
        let items = options.toQueryItems().filter { $0.name == "confirmEndConversationMode" }

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.value, "liveChat")
    }

    func testInitialUserMessageFrequencyDefaultsToEveryConversationAndForwardsOptIn() {
        var options = AgentChatControllerOptions(name: "Test")
        XCTAssertEqual(options.initialUserMessageFrequency, .everyConversation)
        XCTAssertFalse(
            options.toQueryItems().contains { $0.name == "initialUserMessageFrequency" }
        )

        options.initialUserMessageFrequency = .oncePerChatInstance
        let items = options.toQueryItems().filter { $0.name == "initialUserMessageFrequency" }

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.value, "oncePerChatInstance")
    }

    func testDisclosureBehaviorIsForwardedAsQueryItems() {
        var options = AgentChatControllerOptions(name: "Test")
        XCTAssertNil(options.disclosurePosition)
        XCTAssertFalse(options.hideDisclosureDuringLiveChat)

        options.disclosurePosition = .pinnedBelowComposer
        options.hideDisclosureDuringLiveChat = true
        let items = options.toQueryItems()

        XCTAssertEqual(
            items.first { $0.name == "disclosurePosition" }?.value,
            "pinnedBelowComposer"
        )
        XCTAssertEqual(
            items.first { $0.name == "hideDisclosureDuringLiveChat" }?.value,
            "true"
        )
    }

    func testAddAgentTagsOptionsJSONIncludesOnlyConfiguredValues() {
        let options = AddAgentTagsOptions(dev: true, omitPresent: nil, customField: false)

        XCTAssertEqual(options.jsonValue["dev"], true)
        XCTAssertNil(options.jsonValue["omitPresent"])
        XCTAssertEqual(options.jsonValue["customField"], false)
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

    func testLinear16ByteCountMatchesMonoSampleWidth() {
        // Mono linear16 is 2 bytes per sample. The echo-gate silence path and the converted-audio
        // emit path both size their output through this helper, so equal frame counts must yield
        // equal byte lengths -- that equal length is what keeps the server's reconstructed AudioIn
        // timeline aligned with the real conversation. See CH-633.
        XCTAssertEqual(AudioCaptureSession.linear16ByteCount(frameCount: 0), 0)
        XCTAssertEqual(AudioCaptureSession.linear16ByteCount(frameCount: 1), 2)
        XCTAssertEqual(AudioCaptureSession.linear16ByteCount(frameCount: 240), 480)
    }

    func testCapturePolicyPrecedence() {
        // An audio-session interruption suspends the session, so it drops even when the user is
        // also muted. User mute and speaking-mute emit silence to keep the server's byte-counted
        // AudioIn clock advancing so agent audio stays aligned during playback. See CH-633.
        XCTAssertEqual(
            AudioCaptureSession.capturePolicy(interruptionPaused: true, userMuted: true, speakingMuted: true),
            .drop
        )
        XCTAssertEqual(
            AudioCaptureSession.capturePolicy(interruptionPaused: false, userMuted: true, speakingMuted: false),
            .silence
        )
        XCTAssertEqual(
            AudioCaptureSession.capturePolicy(interruptionPaused: false, userMuted: false, speakingMuted: true),
            .silence
        )
        XCTAssertEqual(
            AudioCaptureSession.capturePolicy(interruptionPaused: false, userMuted: false, speakingMuted: false),
            .send
        )
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

    func testChatStyleColorsSerializesOpacity() {
        let opaque = UIColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        let translucent = UIColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
        let transparent = UIColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0)
        let colors = ChatStyleColors(
            backgroundColor: opaque,
            assistantBubble: transparent,
            userBubble: translucent
        )

        let json = colors.toJSON()

        XCTAssertEqual(json["background"], "#336699")
        XCTAssertEqual(json["userBubble"], "#336699CC")
        XCTAssertEqual(json["assistantBubble"], "#33669900")
    }

    func testChatStyleColorsSerializesBubbleBorders() {
        let colors = ChatStyleColors(
            assistantBubbleBorder: UIColor(red: 1, green: 0, blue: 0, alpha: 0.8),
            userBubbleBorder: UIColor(red: 0, green: 1, blue: 0, alpha: 0.4),
            humanAgentBubbleBorder: UIColor(red: 0, green: 0, blue: 1, alpha: 0)
        )

        let json = colors.toJSON()
        XCTAssertEqual(json["assistantBubbleBorder"], "#FF0000CC")
        XCTAssertEqual(json["userBubbleBorder"], "#00FF0066")
        XCTAssertEqual(json["humanAgentBubbleBorder"], "#0000FF00")
    }

    func testBubbleTailOptionIsForwardedInBrandOnlyWhenConfigured() throws {
        var options = AgentChatControllerOptions(name: "Test")
        var brand = try XCTUnwrap(brandJSON(options))
        XCTAssertNil(brand["hideBubbleTails"])

        options.hideBubbleTails = false
        brand = try XCTUnwrap(brandJSON(options))
        XCTAssertEqual(brand["hideBubbleTails"] as? Bool, false)
    }

    @MainActor
    func testWebViewOpacityFollowsConfiguredChatBackgroundAlpha() throws {
        let cases: [(name: String, background: UIColor, isOpaque: Bool)] = [
            ("opaque", UIColor(red: 1, green: 1, blue: 1, alpha: 1), true),
            ("translucent", UIColor(red: 1, green: 1, blue: 1, alpha: 0.5), false),
            ("transparent", .clear, false),
        ]

        for (name, background, expectedIsOpaque) in cases {
            let controller = makeChatController(background: background)
            controller.loadViewIfNeeded()
            let webView = try XCTUnwrap(findWebView(in: controller.view))

            XCTAssertEqual(webView.isOpaque, expectedIsOpaque, "isOpaque for a \(name) background")
            // A non-opaque background is painted once by the web embed on its own root.
            let expectedNativeBackground: UIColor = expectedIsOpaque ? background : .clear
            XCTAssertEqual(webView.backgroundColor, expectedNativeBackground, "web view background for a \(name) background")
            XCTAssertEqual(controller.view.backgroundColor, expectedNativeBackground, "container background for a \(name) background")
            // The over-scroll area is outside the page, so it keeps the configured alpha. WebKit
            // round-trips the color through 8-bit sRGB, so compare within one channel step.
            XCTAssertEqual(
                try XCTUnwrap(webView.underPageBackgroundColor).cgColor.alpha,
                background.cgColor.alpha,
                accuracy: 1 / 255,
                "underPageBackgroundColor for a \(name) background"
            )
        }
    }

    @MainActor
    func testWebViewOpacityIsReappliedAfterAppearanceChange() throws {
        // Opaque in light mode, transparent in dark mode: the controller has to resolve the
        // dynamic color against the active appearance instead of once when it is created.
        let background = UIColor { $0.userInterfaceStyle == .dark ? .clear : .white }
        let controller = makeChatController(background: background)
        controller.overrideUserInterfaceStyle = .light
        controller.loadViewIfNeeded()
        let webView = try XCTUnwrap(findWebView(in: controller.view))
        XCTAssertTrue(webView.isOpaque, "an opaque light-mode background must keep the web view opaque")

        controller.overrideUserInterfaceStyle = .dark

        XCTAssertFalse(webView.isOpaque, "a transparent dark-mode background must clear isOpaque")
        XCTAssertEqual(webView.backgroundColor, .clear)
    }

    @MainActor
    func testServerConfiguredStyleLeavesNativeBackgroundsTransparent() throws {
        let controller = makeChatController(background: .white, useConfiguredStyle: true)
        controller.loadViewIfNeeded()
        let webView = try XCTUnwrap(findWebView(in: controller.view))

        XCTAssertFalse(webView.isOpaque)
        XCTAssertEqual(try XCTUnwrap(webView.backgroundColor).cgColor.alpha, 0)
        XCTAssertEqual(try XCTUnwrap(webView.scrollView.backgroundColor).cgColor.alpha, 0)
        XCTAssertEqual(try XCTUnwrap(webView.underPageBackgroundColor).cgColor.alpha, 0)
        XCTAssertEqual(try XCTUnwrap(controller.view.backgroundColor).cgColor.alpha, 0)
    }

    @MainActor
    private func makeChatController(
        background: UIColor,
        useConfiguredStyle: Bool = false
    ) -> AgentChatController {
        var options = AgentChatControllerOptions(name: "Test")
        options.useConfiguredStyle = useConfiguredStyle
        options.chatStyle = ChatStyle(colors: ChatStyleColors(backgroundColor: background))
        return AgentChatController(agent: Agent(config: AgentConfig(token: "test-token")), options: options)
    }

    private func findWebView(in view: UIView) -> WKWebView? {
        if let webView = view as? WKWebView {
            return webView
        }
        return view.subviews.lazy.compactMap(findWebView).first
    }

    @MainActor
    func testLoadingSpinnerColorPrefersTextOverTitleBarText() {
        // The Outfitters testbed preset: white title bar text is illegible on the cream chat
        // background, while `text` is a dark green chosen to read on it. Keying off `text` keeps
        // the branded color instead of flattening the spinner to black.
        let brandGreen = UIColor(red: 0.14, green: 0.31, blue: 0.25, alpha: 1)
        let colors = ChatStyleColors(
            backgroundColor: UIColor(red: 0.96, green: 0.95, blue: 0.93, alpha: 1),
            text: brandGreen,
            titleBar: brandGreen,
            titleBarText: .white
        )

        XCTAssertEqual(
            colors.loadingSpinnerColor(using: UITraitCollection(userInterfaceStyle: .light)),
            brandGreen
        )
    }

    @MainActor
    func testLoadingSpinnerColorStaysLegibleWhenTitleBarTextMatchesBackground() {
        // A dark title bar with white text over a white chat background: the customer-reported
        // case, and what the WellnessWave testbed preset produces. The background is static
        // while the default `text` is dynamic, so dark mode flips `text` to white and the
        // fallback has to catch it.
        let colors = ChatStyleColors(backgroundColor: .white, titleBar: .black, titleBarText: .white)

        for (style, name) in [(UIUserInterfaceStyle.light, "light"), (.dark, "dark")] {
            let traitCollection = UITraitCollection(userInterfaceStyle: style)
            let spinnerColor = colors.loadingSpinnerColor(using: traitCollection)

            XCTAssertGreaterThanOrEqual(
                spinnerColor.contrastRatio(against: colors.backgroundColor, using: traitCollection),
                3,
                "spinner must stay legible against the chat background it is drawn on in \(name) mode"
            )
        }
    }

    @MainActor
    func testLoadingSpinnerColorFallsBackWhenTextIsLowContrast() {
        // A custom dark background with no `text` override: the default `.label` assumes a system
        // background and resolves to near-black in light mode, roughly 1.4:1 here.
        let colors = ChatStyleColors(
            backgroundColor: UIColor(red: 16 / 255, green: 34 / 255, blue: 76 / 255, alpha: 1)
        )
        let traitCollection = UITraitCollection(userInterfaceStyle: .light)

        let spinnerColor = colors.loadingSpinnerColor(using: traitCollection)

        XCTAssertEqual(spinnerColor, .white)
        XCTAssertGreaterThanOrEqual(
            spinnerColor.contrastRatio(against: colors.backgroundColor, using: traitCollection),
            3
        )
    }

    @MainActor
    func testLoadingSpinnerColorResolvesPerAppearance() {
        // The default colors are dynamic, so the spinner color has to be resolved against the
        // active appearance rather than once when the controller is created.
        let colors = ChatStyleColors()

        for (style, name) in [(UIUserInterfaceStyle.light, "light"), (.dark, "dark")] {
            let traitCollection = UITraitCollection(userInterfaceStyle: style)
            let spinnerColor = colors.loadingSpinnerColor(using: traitCollection)

            XCTAssertGreaterThanOrEqual(
                spinnerColor.contrastRatio(against: colors.backgroundColor, using: traitCollection),
                3,
                "spinner must stay legible in \(name) mode"
            )
        }
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

private enum TestVoiceError: Error {
    case connectionFailed
}

private final class CapturingVoiceCallbacks: VoiceCallbacks {
    var errorCount = 0
    var endCount = 0

    func onVoiceEnded() {
        endCount += 1
    }

    func onVoiceError(error: Error) {
        errorCount += 1
    }
}
