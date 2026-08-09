import Foundation
import XCTest
@testable import FoveaCore

final class SaveAsNamingTests: XCTestCase {
    private let folder = URL(fileURLWithPath: "/tmp/pictures")

    func testFirstSuggestionAppendsUnderscoreOne() {
        let url = folder.appendingPathComponent("photo.jpg")

        let proposed = SaveAsNaming.proposedURL(for: url) { _ in false }

        XCTAssertEqual(proposed.lastPathComponent, "photo_1.jpg")
        XCTAssertEqual(proposed.deletingLastPathComponent().path, folder.path)
    }

    func testOccupiedNamesCountUpwards() {
        let url = folder.appendingPathComponent("photo.jpg")
        let taken: Set<String> = ["photo_1.jpg", "photo_2.jpg"]

        let proposed = SaveAsNaming.proposedURL(for: url) { taken.contains($0.lastPathComponent) }

        XCTAssertEqual(proposed.lastPathComponent, "photo_3.jpg")
    }

    func testAlreadySuffixedNameContinuesInsteadOfNesting() {
        let url = folder.appendingPathComponent("photo_3.jpg")

        let proposed = SaveAsNaming.proposedURL(for: url) { _ in false }

        // 不能叠成 photo_3_1。
        XCTAssertEqual(proposed.lastPathComponent, "photo_4.jpg")
    }

    func testTrailingUnderscoreWithoutDigitsIsNotTreatedAsASuffix() {
        XCTAssertEqual(SaveAsNaming.baseNameStrippingSuffix("photo_final").base, "photo_final")
        XCTAssertEqual(SaveAsNaming.baseNameStrippingSuffix("photo_final").index, 0)
        XCTAssertEqual(SaveAsNaming.baseNameStrippingSuffix("photo_12").base, "photo")
        XCTAssertEqual(SaveAsNaming.baseNameStrippingSuffix("photo_12").index, 12)
    }

    func testExtensionlessFileStillGetsASuffix() {
        let url = folder.appendingPathComponent("photo")

        let proposed = SaveAsNaming.proposedURL(for: url) { _ in false }

        XCTAssertEqual(proposed.lastPathComponent, "photo_1")
    }

    func testExhaustedSuffixesFallBackToATimestampInsteadOfLooping() {
        let url = folder.appendingPathComponent("photo.jpg")

        // 所有序号都被占用，必须仍然给出一个名字而不是卡死。
        let proposed = SaveAsNaming.proposedURL(for: url) { $0.lastPathComponent != "photo.jpg" }

        XCTAssertTrue(proposed.lastPathComponent.hasPrefix("photo_"))
        XCTAssertTrue(proposed.lastPathComponent.hasSuffix(".jpg"))
        XCTAssertNotEqual(proposed.lastPathComponent, "photo_1.jpg")
    }
}
