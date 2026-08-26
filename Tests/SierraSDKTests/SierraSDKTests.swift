// Copyright Sierra

import UIKit
import XCTest
@testable import SierraSDK
@testable import SierraSDKVoice

final class SierraSDKTests: XCTestCase {
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
        XCTAssertNil(config.headlessAPIToken)
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

    func testSVPTransportFallsBackToHeadlessToken() throws {
        let config = AgentConfig(token: "test-token", headlessAPIToken: "headless-token")
        let transport = SVPTransport(config: config)

        let request = transport.makeWebSocketRequest(url: try XCTUnwrap(URL(string: "wss://example.com")))

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer headless-token")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Sierra-Token-Version"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Sec-WebSocket-Protocol"))
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
        let controller = AgentVoiceController(agent: agent, options: options)
        let callbacks = CapturingVoiceCallbacks()
        controller.voiceCallbacks = callbacks
        controller.loadViewIfNeeded()
        let session = VoiceSessionManager(config: AgentConfig(token: "test-token"), delegate: controller)

        controller.voiceSession(session, didEncounterError: TestVoiceError.connectionFailed)
        controller.voiceSession(session, didChangeState: .ended)
        controller.voiceSession(session, didChangeState: .listening)
        await fulfillment(of: [callbacks.errorExpectation], timeout: 1)

        XCTAssertFalse(muteButton.isEnabled)
        XCTAssertTrue(endButton.isEnabled)

        controller.endConversation()

        XCTAssertEqual(callbacks.endCount, 1)
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
    let errorExpectation: XCTestExpectation = {
        let expectation = XCTestExpectation(description: "voice error delivered")
        expectation.assertForOverFulfill = false
        return expectation
    }()
    var endCount = 0

    func onVoiceEnded() {
        endCount += 1
    }

    func onVoiceError(error: Error) {
        errorExpectation.fulfill()
    }
}
