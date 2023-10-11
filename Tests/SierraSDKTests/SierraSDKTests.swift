// Copyright Sierra

import XCTest
@testable import SierraSDK

final class SierraSDKTests: XCTestCase {
    func testSDK() throws {
        XCTAssertEqual(sdkMethod(), "hello world")
    }
}
