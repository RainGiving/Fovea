import AppKit
import XCTest
@testable import FoveaApp

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

    /// 旋转之后画布上的图片换了一块区域，选区必须跟过去。
    ///
    /// 这一条盯住的就是「先转再裁」那个缺陷：不跟过去的话，
    /// 选区还停在图片旋转前占的那一块，用户拖不到真正想裁的范围。
    func testContentTransformMovesTheSelectionOntoTheRotatedImage() {
        let overlay = CropOverlayView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        // 一张 300 × 200 的横图，转成竖的之后占 200 × 300。
        let landscape = CGRect(x: 50, y: 100, width: 300, height: 200)
        let portrait = CGRect(x: 100, y: 50, width: 200, height: 300)
        overlay.beginCropping(in: landscape)
        overlay.resizeCrop(edge: .right, by: CGPoint(x: -100, y: 0))
        let before = overlay.normalizedCropRect

        overlay.applyContentTransform(.rotateClockwise, in: portrait)

        XCTAssertTrue(portrait.contains(overlay.cropRect), "选区应落在旋转后的图片上")
        // 顺时针转一下，原来靠左的那一条到了顶上。
        XCTAssertEqual(overlay.normalizedCropRect.minX, 1 - before.minY - before.height, accuracy: 0.001)
        XCTAssertEqual(overlay.normalizedCropRect.minY, before.minX, accuracy: 0.001)
        XCTAssertEqual(overlay.normalizedCropRect.width, before.height, accuracy: 0.001)
        XCTAssertEqual(overlay.normalizedCropRect.height, before.width, accuracy: 0.001)
    }

    /// 图片只是挪了位置或换了尺寸，选区圈住的那块画面不变。
    func testUpdateImageRectKeepsTheSelectionOnTheSameContent() {
        let overlay = CropOverlayView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        overlay.beginCropping(in: CGRect(x: 50, y: 100, width: 300, height: 200))
        overlay.moveCrop(by: CGPoint(x: 20, y: -10))
        let before = overlay.normalizedCropRect

        overlay.updateImageRect(CGRect(x: 200, y: 150, width: 450, height: 300))

        XCTAssertEqual(overlay.normalizedCropRect.minX, before.minX, accuracy: 0.001)
        XCTAssertEqual(overlay.normalizedCropRect.minY, before.minY, accuracy: 0.001)
        XCTAssertEqual(overlay.normalizedCropRect.width, before.width, accuracy: 0.001)
        XCTAssertEqual(overlay.normalizedCropRect.height, before.height, accuracy: 0.001)
        XCTAssertEqual(overlay.cropRect, CGRect(x: 275, y: 165, width: 360, height: 240))
        XCTAssertEqual(overlay.displayedCropRect, overlay.cropRect, "重铺不留一段没走完的过渡")
    }

    /// 锁了比例的话，换到新区域之后还得是那个比例。
    func testRetargetingKeepsTheLockedAspectRatio() {
        let overlay = CropOverlayView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
        overlay.beginCropping(in: CGRect(x: 0, y: 0, width: 400, height: 300))
        overlay.aspectRatio = .square

        overlay.applyContentTransform(.rotateClockwise, in: CGRect(x: 0, y: 0, width: 300, height: 400))

        XCTAssertEqual(overlay.cropRect.width, overlay.cropRect.height, accuracy: 0.001)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 300, height: 400).contains(overlay.cropRect))
    }

    /// 没在裁的时候画布照样在动，那些通知不该凭空造出一个选区。
    func testRetargetingDoesNothingOutsideACropSession() {
        let overlay = CropOverlayView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))

        overlay.updateImageRect(CGRect(x: 0, y: 0, width: 300, height: 200))
        overlay.applyContentTransform(.rotateClockwise, in: CGRect(x: 0, y: 0, width: 200, height: 300))

        XCTAssertFalse(overlay.isCropping)
        XCTAssertEqual(overlay.cropRect, .zero)
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
