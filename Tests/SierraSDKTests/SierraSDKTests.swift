// Copyright Sierra

import XCTest
@testable import SierraSDK

final class SierraSDKTests: XCTestCase {
    func testAgentConfigDefaults() {
        let config = AgentConfig(token: "test-token")

        XCTAssertEqual(config.token, "test-token")
        XCTAssertNil(config.target)
        XCTAssertEqual(config.persistence, .memory)
        XCTAssertNil(config.headlessAPIToken)
    }
}
