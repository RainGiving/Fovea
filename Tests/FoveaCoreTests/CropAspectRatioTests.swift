import CoreGraphics
import XCTest
@testable import FoveaCore

final class CropAspectRatioTests: XCTestCase {
    func testFreeIsTheDefaultAndImposesNoConstraint() {
        XCTAssertEqual(CropAspectRatio.allCases.first, .free)
        XCTAssertNil(CropAspectRatio.free.value)
        XCTAssertEqual(CropAspectRatio.free.displayName, "Free")

        let rect = CGRect(x: 10, y: 20, width: 300, height: 100)
        XCTAssertEqual(CropAspectRatio.free.constrained(rect), rect)
    }

    func testIDPhotoRatiosMatchTheirMillimetreSizes() {
        XCTAssertEqual(CropAspectRatio.idOneInch.value ?? 0, 25.0 / 35.0, accuracy: 0.0001)
        XCTAssertEqual(CropAspectRatio.idTwoInch.value ?? 0, 35.0 / 49.0, accuracy: 0.0001)
        XCTAssertEqual(CropAspectRatio.idSmallTwoInch.value ?? 0, 35.0 / 45.0, accuracy: 0.0001)
        // 一寸和二寸只看比例分不清，所以要标出毫米尺寸。
        XCTAssertNotNil(CropAspectRatio.idOneInch.detail)
        XCTAssertNotNil(CropAspectRatio.idTwoInch.detail)
    }

    func testConstrainedShrinksToFitAndKeepsTheCentre() {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 100)
        let result = CropAspectRatio.square.constrained(rect)

        XCTAssertEqual(result.width, result.height, accuracy: 0.001)
        // 只能缩不能撑，否则选区会跑出画面。
        XCTAssertLessThanOrEqual(result.width, rect.width)
        XCTAssertLessThanOrEqual(result.height, rect.height)
        XCTAssertEqual(result.midX, rect.midX, accuracy: 0.001)
        XCTAssertEqual(result.midY, rect.midY, accuracy: 0.001)
    }

    func testConstrainedHitsTheRequestedRatioFromEitherDirection() {
        for ratio in CropAspectRatio.allCases {
            guard let expected = ratio.value else { continue }
            for rect in [
                CGRect(x: 0, y: 0, width: 500, height: 80),
                CGRect(x: 0, y: 0, width: 80, height: 500)
            ] {
                let result = ratio.constrained(rect)
                XCTAssertEqual(result.width / result.height, expected, accuracy: 0.001, "\(ratio)")
            }
        }
    }

    func testEveryRatioHasALabel() {
        for ratio in CropAspectRatio.allCases {
            XCTAssertFalse(ratio.displayName.isEmpty, "\(ratio)")
        }
    }
}
