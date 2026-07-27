import AppKit
import ImageViewCore
import XCTest
@testable import ImageViewApp

@MainActor
final class EditControlsViewTests: XCTestCase {
    func testAspectRatioMenuListsEveryRatioAndMarksTheSelectedOne() {
        let menu = EditControlsView.makeAspectRatioMenu(selected: .threeTwo) { _ in }

        XCTAssertEqual(menu.items.count, CropAspectRatio.allCases.count)
        for (item, ratio) in zip(menu.items, CropAspectRatio.allCases) {
            XCTAssertTrue(item.title.hasPrefix(ratio.displayName))
            XCTAssertEqual(item.state, ratio == .threeTwo ? .on : .off)
        }
    }

    /// 证件照要带上毫米尺寸，只看比例分不出一寸和二寸。
    func testIdentityPhotoItemsCarryMillimetreSizes() {
        let menu = EditControlsView.makeAspectRatioMenu(selected: .free) { _ in }
        let oneInch = menu.items[CropAspectRatio.allCases.firstIndex(of: .idOneInch)!]

        XCTAssertTrue(oneInch.title.contains("25 × 35 mm"))
    }

    func testSelectingAMenuItemReportsItsRatio() throws {
        var selected: CropAspectRatio?
        let menu = EditControlsView.makeAspectRatioMenu(selected: .free) { selected = $0 }
        let squareItem = menu.items[try XCTUnwrap(CropAspectRatio.allCases.firstIndex(of: .square))]

        let target = try XCTUnwrap(squareItem.target as? NSObject)
        let action = try XCTUnwrap(squareItem.action)
        target.perform(action, with: squareItem)

        XCTAssertEqual(selected, .square)
    }

    /// 菜单项的 target 是弱引用，菜单必须自己把它留住，
    /// 否则弹出来的每一项点了都没反应。
    func testMenuKeepsItsActionTargetAlive() {
        let menu = EditControlsView.makeAspectRatioMenu(selected: .free) { _ in }

        for item in menu.items {
            XCTAssertNotNil(item.target)
        }
    }
}
