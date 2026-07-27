import AppKit
import XCTest
@testable import ImageViewApp

@MainActor
final class CropOverlayViewTests: XCTestCase {
    func testBeginCroppingCreatesCenteredEightyPercentCrop() {
        let overlay = CropOverlayView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))

        overlay.beginCropping(in: CGRect(x: 50, y: 100, width: 300, height: 200))

        XCTAssertTrue(overlay.isCropping)
        XCTAssertEqual(overlay.cropRect, CGRect(x: 80, y: 120, width: 240, height: 160))
    }

    func testMoveCropStaysInsideImageBounds() {
        let overlay = CropOverlayView()
        overlay.beginCropping(in: CGRect(x: 50, y: 50, width: 200, height: 100))

        overlay.moveCrop(by: CGPoint(x: 1_000, y: 1_000))

        XCTAssertEqual(overlay.cropRect.maxX, 250)
        XCTAssertEqual(overlay.cropRect.maxY, 150)
        XCTAssertEqual(overlay.cropRect.width, 160)
        XCTAssertEqual(overlay.cropRect.height, 80)
    }

    /// 画出来的那一份选区平时和模型完全一致，只有开裁和换比例才短暂落后一点。
    /// 没上屏时连那一段也没有，直接就是最终位置。
    func testDisplayedCropRectMatchesTheModelWithoutAnimation() {
        let overlay = CropOverlayView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))

        overlay.beginCropping(in: CGRect(x: 50, y: 100, width: 300, height: 200))
        XCTAssertEqual(overlay.displayedCropRect, overlay.cropRect)

        overlay.moveCrop(by: CGPoint(x: 10, y: 10))
        XCTAssertEqual(overlay.displayedCropRect, overlay.cropRect)

        overlay.aspectRatio = .square
        XCTAssertEqual(overlay.displayedCropRect, overlay.cropRect)
    }

    /// 退出编辑后不留下一个还画着的选区。
    func testEndCroppingClearsTheDisplayedCropRectWithoutAnimation() {
        let overlay = CropOverlayView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        overlay.beginCropping(in: CGRect(x: 50, y: 100, width: 300, height: 200))

        overlay.endCropping()

        XCTAssertFalse(overlay.isCropping)
        XCTAssertEqual(overlay.displayedCropRect, .zero)
    }

    func testResizeCropMaintainsMinimumSizeAndImageBounds() {
        let overlay = CropOverlayView()
        overlay.beginCropping(in: CGRect(x: 0, y: 0, width: 100, height: 100))

        overlay.resizeCrop(edge: .topLeft, by: CGPoint(x: 1_000, y: 1_000))

        XCTAssertEqual(overlay.cropRect.maxX, 90)
        XCTAssertEqual(overlay.cropRect.maxY, 90)
        XCTAssertEqual(overlay.cropRect.width, 24)
        XCTAssertEqual(overlay.cropRect.height, 24)
    }
}
