// Copyright Sierra

import UIKit
import XCTest
@testable import SierraSDK

final class ChatButtonStyleTests: XCTestCase {
    func testButtonOptionsReachMobileQueryWithoutChangingDefaults() throws {
        var options = AgentChatControllerOptions(name: "Agent")
        XCTAssertFalse(options.toQueryItems().contains { $0.name == "footerEndConversationButtonStyle" || $0.name == "messageInputPresetAction" })
        XCTAssertNil(ChatButtonStyle().toJSONString())
        let style = ChatButtonStyle(alignment: .end, backgroundColor: .black, textColor: .white,
                                    borderColor: .red, borderWidth: "0px", height: "44px", width: "100%",
                                    padding: "0.5em", borderRadius: "22px", iconSVG: "<svg/>")
        options.footerEndConversationButtonStyle = style
        options.messageInputPresetAction = MessageInputPresetAction(label: "Help",
            clientEvent: .init(message: .init(content: "Help & advice?")), showAfterAgentMessageCount: 1, style: style)
        let items = options.toQueryItems()
        let raw = try XCTUnwrap(items.first { $0.name == "messageInputPresetAction" }?.value)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        let event = try XCTUnwrap(json["clientEvent"] as? [String: Any])
        XCTAssertEqual(event["type"] as? String, "message")
        XCTAssertEqual((event["message"] as? [String: String])?["content"], "Help & advice?")
        let serializedStyle = try XCTUnwrap(json["style"] as? [String: Any])
        XCTAssertEqual(serializedStyle as NSDictionary, [
            "alignment": "end", "backgroundColor": "#000000", "textColor": "#FFFFFF",
            "borderColor": "#FF0000", "borderWidth": "0px", "height": "44px", "width": "100%",
            "padding": "0.5em", "borderRadius": "22px", "iconSVG": "<svg/>",
        ] as NSDictionary)
        XCTAssertEqual(serializedStyle["width"] as? String, "100%")
        XCTAssertEqual(ChatButtonStyle(width: "150px").toJSON()["width"] as? String, "150px")
    }
}
