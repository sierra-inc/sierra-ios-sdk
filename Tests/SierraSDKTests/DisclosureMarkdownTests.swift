// Copyright Sierra

import UIKit
import XCTest
@testable import SierraSDKVoice

final class DisclosureMarkdownTests: XCTestCase {
    private let font = UIFont.systemFont(ofSize: 12)

    func testPlainTextIsUnchanged() {
        let text = "By proceeding, you agree to our terms. (Calls may be recorded.) [Note]"
        let rendered = render(text)
        XCTAssertEqual(String(rendered.characters), text)
        XCTAssertEqual(rendered.runs.map { $0.uiKit.font }, [font])
    }

    func testBoldItalicAndCodeUseFontTraits() {
        let rendered = render("**Bold**, *italic*, and `code`")
        XCTAssertEqual(String(rendered.characters), "Bold, italic, and code")
        let traits = Dictionary(
            uniqueKeysWithValues: rendered.runs.map { (String(rendered[$0.range].characters), $0.uiKit.font!.fontDescriptor.symbolicTraits) }
        )
        XCTAssertTrue(traits["Bold"]!.contains(.traitBold))
        XCTAssertTrue(traits["italic"]!.contains(.traitItalic))
        XCTAssertTrue(traits["code"]!.contains(.traitMonoSpace))
        XCTAssertFalse(traits[", and "]!.contains(.traitBold))
    }

    func testKeepsLinksWithAllowedSchemes() {
        let rendered = render(
            "See [Terms](http://example.com/terms), [email](mailto:help@example.com), and [call](tel:+15555550100)."
        )
        XCTAssertEqual(String(rendered.characters), "See Terms, email, and call.")
        XCTAssertEqual(links(rendered), [
            "Terms": "http://example.com/terms",
            "email": "mailto:help@example.com",
            "call": "tel:+15555550100",
        ])
    }

    func testBlockedSchemeRendersPlainLabel() {
        let rendered = render("Open [this](javascript:alert(1)), [that](file:///etc/hosts), and [empty](https://)")
        XCTAssertEqual(String(rendered.characters), "Open this, that, and empty")
        XCTAssertEqual(links(rendered), [:])
    }

    func testLinkKeepsBalancedParenthesesAndIgnoresTitle() {
        let rendered = render(#"[Policy](https://example.com/privacy_(us) "Privacy")."#)
        XCTAssertEqual(String(rendered.characters), "Policy.")
        XCTAssertEqual(links(rendered), ["Policy": "https://example.com/privacy_(us)"])
    }

    func testUppercaseSchemeIsNormalized() {
        XCTAssertEqual(links(render("[Policy](HTTPS://example.com/Privacy)")), ["Policy": "https://example.com/Privacy"])
    }

    private func render(_ markdown: String) -> AttributedString {
        DisclosureMarkdown.attributedText(markdown, font: font)
    }

    private func links(_ text: AttributedString) -> [String: String] {
        Dictionary(uniqueKeysWithValues: text.runs.compactMap { run in
            run.link.map { (String(text[run.range].characters), $0.absoluteString) }
        })
    }
}
