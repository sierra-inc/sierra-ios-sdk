// Copyright Sierra

import UIKit
import XCTest
@testable import SierraSDK

final class ChatComposerStyleTests: XCTestCase {
    private func json(_ style: ChatComposerStyle) throws -> [String: Any] {
        let string = try XCTUnwrap(style.toJSONString())
        let data = try XCTUnwrap(string.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testEmptyStyleIsNotSerialized() {
        // The query parameter is omitted entirely, so the embed keeps its defaults.
        XCTAssertNil(ChatComposerStyle().toJSONString())
    }

    func testInsetsSerializeWithLogicalStartAndEndKeys() throws {
        let style = ChatComposerStyle(
            outerInsets: NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 16)
        )

        let insets = try XCTUnwrap(try json(style)["outerInsets"] as? [String: Any])
        XCTAssertEqual(insets["top"] as? CGFloat, 0)
        XCTAssertEqual(insets["start"] as? CGFloat, 16)
        XCTAssertEqual(insets["bottom"] as? CGFloat, 16)
        XCTAssertEqual(insets["end"] as? CGFloat, 16)
    }

    func testOmittedFieldsAreNotSerialized() throws {
        let style = ChatComposerStyle(minimumHeight: 50)

        XCTAssertEqual(Array(try json(style).keys), ["minimumHeight"])
    }

    // Distinct values per field, so a swapped key fails.
    func testEverySuppliedFieldIsSerialized() throws {
        let style = ChatComposerStyle(
            outerInsets: NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 16),
            contentInsets: NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 8),
            minimumHeight: 50,
            maximumLines: 3,
            cornerRadius: 25,
            borderWidth: 1,
            actionButtonSize: 28
        )

        let serialized = try json(style)
        XCTAssertEqual((serialized["contentInsets"] as? [String: Any])?["start"] as? CGFloat, 12)
        XCTAssertEqual(serialized["minimumHeight"] as? CGFloat, 50)
        XCTAssertEqual(serialized["maximumLines"] as? Int, 3)
        XCTAssertEqual(serialized["cornerRadius"] as? CGFloat, 25)
        XCTAssertEqual(serialized["borderWidth"] as? CGFloat, 1)
        XCTAssertEqual(serialized["actionButtonSize"] as? CGFloat, 28)
    }

    func testNonFiniteValuesDoNotDiscardValidSettings() throws {
        let style = ChatComposerStyle(
            outerInsets: NSDirectionalEdgeInsets(
                top: .nan, leading: 16, bottom: .infinity, trailing: -.infinity
            ),
            contentInsets: NSDirectionalEdgeInsets(
                top: .nan, leading: .infinity, bottom: -.infinity, trailing: .nan
            ),
            minimumHeight: .nan,
            maximumLines: 3,
            cornerRadius: .infinity,
            borderWidth: -.infinity,
            actionButtonSize: .nan
        )

        let serialized = try json(style)
        XCTAssertEqual(serialized["outerInsets"] as? [String: CGFloat], ["start": 16])
        XCTAssertEqual(serialized["maximumLines"] as? Int, 3)
        XCTAssertEqual(Set(serialized.keys), ["outerInsets", "maximumLines"])
    }

    func testComposerStyleQueryItemIsOmittedByDefault() {
        let options = AgentChatControllerOptions(name: "Agent")

        XCTAssertFalse(options.toQueryItems().contains { $0.name == "composerStyle" })
    }

    func testComposerStyleQueryItemCarriesTheSerializedStyle() throws {
        var options = AgentChatControllerOptions(name: "Agent")
        options.composerStyle = ChatComposerStyle(minimumHeight: 50)

        let item = try XCTUnwrap(options.toQueryItems().first { $0.name == "composerStyle" })
        let data = try XCTUnwrap(item.value?.data(using: .utf8))
        let serialized = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(serialized["minimumHeight"] as? CGFloat, 50)
    }

    func testComposerColorsSerializeAlongsideTheGlobalColors() throws {
        let colors = ChatStyleColors(inputBorder: .black, inputText: .white)

        let serialized = colors.toJSON()
        XCTAssertEqual(serialized["inputBorder"] ?? nil, UIColor.black.toHex())
        XCTAssertEqual(serialized["inputText"] ?? nil, UIColor.white.toHex())
    }

    func testHumanAgentColorsUseEmbedKeys() {
        let colors = ChatStyleColors(humanAgentBubble: .clear, humanAgentBubbleText: .black, humanAgentBubbleLink: .blue)
        let serialized = colors.toJSON()
        XCTAssertEqual(serialized["humanAgentBubble"] ?? nil, UIColor.clear.toHex())
        XCTAssertEqual(serialized["humanAgentBubbleText"] ?? nil, UIColor.black.toHex())
        XCTAssertEqual(serialized["humanAgentBubbleLink"] ?? nil, UIColor.blue.toHex())
        XCTAssertNil(ChatStyleColors().toJSON()["humanAgentBubble"])
    }
}
