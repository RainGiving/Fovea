import XCTest
@testable import FoveaCore

final class FoveaCoreSmokeTests: XCTestCase {
    func testCoreVersionIsAvailable() {
        XCTAssertEqual(FoveaCoreVersion.current, "0.1.3")
    }
}
