import CoreGraphics
import XCTest
@testable import ImageViewCore

final class EditOperationTests: XCTestCase {
    func testRotationsAreDistinctOperations() {
        XCTAssertNotEqual(EditOperation.rotateClockwise, .rotateCounterClockwise)
        XCTAssertNotEqual(EditOperation.mirrorHorizontal, .mirrorVertical)
    }

    func testCropCarriesItsRectInEquality() {
        let rect = CGRect(x: 1, y: 2, width: 3, height: 4)

        XCTAssertEqual(EditOperation.crop(rect), .crop(rect))
        XCTAssertNotEqual(EditOperation.crop(rect), .crop(rect.insetBy(dx: 1, dy: 1)))
        XCTAssertNotEqual(EditOperation.crop(rect), .rotateClockwise)
    }

    func testFourClockwiseRotationsReturnToTheOriginalImage() throws {
        let service = ImageEditingService()
        let original = try makeImage(width: 3, height: 2)

        let restored = try service.apply(
            Array(repeating: .rotateClockwise, count: 4),
            to: original
        )

        XCTAssertEqual(restored.width, original.width)
        XCTAssertEqual(restored.height, original.height)
    }

    func testOppositeRotationsCancelOut() throws {
        let service = ImageEditingService()
        let original = try makeImage(width: 4, height: 2)

        let restored = try service.apply([.rotateClockwise, .rotateCounterClockwise], to: original)

        XCTAssertEqual(restored.width, 4)
        XCTAssertEqual(restored.height, 2)
    }

    func testQuarterTurnSwapsWidthAndHeight() throws {
        let service = ImageEditingService()
        let original = try makeImage(width: 6, height: 2)

        let rotated = try service.apply([.rotateClockwise], to: original)

        XCTAssertEqual(rotated.width, 2)
        XCTAssertEqual(rotated.height, 6)
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}
