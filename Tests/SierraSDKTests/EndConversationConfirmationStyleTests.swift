// Copyright Sierra

import UIKit
import XCTest
@testable import SierraSDK

final class EndConversationConfirmationStyleTests: XCTestCase {
    func testQueryPreservesDividerAndIndependentButtons() throws {
        var options = AgentChatControllerOptions(name: "Agent")
        XCTAssertFalse(options.toQueryItems().contains { $0.name == "endConversationConfirmationStyle" })
        XCTAssertNil(EndConversationConfirmationStyle(confirmButton: ChatButtonStyle()).toJSONString())

        options.endConversationConfirmationStyle = EndConversationConfirmationStyle(
            showFooterDivider: false,
            confirmButton: ChatButtonStyle(height: "48px"),
            cancelButton: ChatButtonStyle(height: "40px")
        )
        let value = try XCTUnwrap(options.toQueryItems().first { $0.name == "endConversationConfirmationStyle" }?.value)
        let data = try XCTUnwrap(value.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["showFooterDivider"] as? Bool, false)
        XCTAssertEqual((json["confirmButton"] as? [String: Any])?["height"] as? String, "48px")
        XCTAssertEqual((json["cancelButton"] as? [String: Any])?["height"] as? String, "40px")
    }
}
