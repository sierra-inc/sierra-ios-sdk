// Copyright Sierra

import XCTest
@testable import SierraSDK

final class ChatConversationEndedStyleTests: XCTestCase {
    func testQueryPreservesFalseAndZeroAndOmitsDefaultStyle() throws {
        var options = AgentChatControllerOptions(name: "Test")
        options.conversationEndedStyle = ChatConversationEndedStyle()
        XCTAssertFalse(options.toQueryItems().contains { $0.name == "conversationEndedStyle" })

        options.conversationEndedStyle = ChatConversationEndedStyle(
            messageAlignment: .center, showComposerContainer: false, actionSpacing: 0,
            newChatButtonStyle: ChatButtonStyle(height: "48px", width: "100%", borderRadius: "24px")
        )
        let item = try XCTUnwrap(options.toQueryItems().first { $0.name == "conversationEndedStyle" })
        let data = try XCTUnwrap(item.value?.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["messageAlignment"] as? String, "center")
        XCTAssertEqual(json["showComposerContainer"] as? Bool, false)
        XCTAssertEqual(json["actionSpacing"] as? Int, 0)
        let button = try XCTUnwrap(json["newChatButtonStyle"] as? [String: Any])
        XCTAssertEqual(button["width"] as? String, "100%")
        XCTAssertEqual(button["height"] as? String, "48px")
        XCTAssertEqual(button["borderRadius"] as? String, "24px")
    }
}
