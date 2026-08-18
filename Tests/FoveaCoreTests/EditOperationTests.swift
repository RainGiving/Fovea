import Foundation
import CoreGraphics
import XCTest
@testable import FoveaCore

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

    /// 归一化选区跟着编辑走过一遍之后，圈住的还是原来那块画面。
    ///
    /// 判据直接落到像素上：先裁再转，和先转再按搬过去的选区裁，两条路
    /// 必须得到同一张图。裁切框就是靠这一条在旋转之后仍然对准原来的内容。
    func testMovingNormalizedRectKeepsTheSameContentUnderEveryTransform() throws {
        let service = ImageEditingService()
        let source = try makeStripedImage(width: 8, height: 4)
        let selections = [
            CGRect(x: 0, y: 0, width: 0.25, height: 0.5),
            CGRect(x: 0.5, y: 0.25, width: 0.5, height: 0.75),
            CGRect(x: 0.25, y: 0.5, width: 0.375, height: 0.25)
        ]
        let operations: [EditOperation] = [
            .rotateClockwise, .rotateCounterClockwise, .mirrorHorizontal, .mirrorVertical
        ]

        for operation in operations {
            let transformed = try service.apply([operation], to: source)
            for selection in selections {
                let cropThenTransform = try service.apply(
                    [operation],
                    to: try service.apply([.crop(pixelRect(selection, in: source))], to: source)
                )
                let transformAfterMovingTheSelection = try service.apply(
                    [.crop(pixelRect(operation.movingNormalizedRect(selection), in: transformed))],
                    to: transformed
                )

                XCTAssertEqual(
                    try bytes(of: cropThenTransform),
                    try bytes(of: transformAfterMovingTheSelection),
                    "\(operation) 下选区 \(selection) 圈住的内容变了"
                )
            }
        }
    }

    /// 反过来那一步要真的把选区送回原处，撤销之后框才落在原来的画面上。
    func testReversedOperationSendsTheSelectionBack() {
        let selection = CGRect(x: 0.25, y: 0.125, width: 0.5, height: 0.375)

        for operation in [EditOperation.rotateClockwise, .rotateCounterClockwise, .mirrorHorizontal, .mirrorVertical] {
            let reversed = operation.reversed
            XCTAssertNotNil(reversed, "\(operation) 应该有反过来的那一步")
            let roundTrip = reversed?.movingNormalizedRect(operation.movingNormalizedRect(selection))

            XCTAssertEqual(roundTrip?.minX ?? .nan, selection.minX, accuracy: 1e-9)
            XCTAssertEqual(roundTrip?.minY ?? .nan, selection.minY, accuracy: 1e-9)
            XCTAssertEqual(roundTrip?.width ?? .nan, selection.width, accuracy: 1e-9)
            XCTAssertEqual(roundTrip?.height ?? .nan, selection.height, accuracy: 1e-9)
        }
    }

    /// 裁切之后整张图就是刚才选中的那一块，选区落回整幅。裁切没有反过来的那一步。
    func testCropLeavesTheSelectionCoveringTheWholeImageAndHasNoReverse() {
        let moved = EditOperation.crop(CGRect(x: 2, y: 3, width: 4, height: 5))
            .movingNormalizedRect(CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5))

        XCTAssertEqual(moved, CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertNil(EditOperation.crop(.zero).reversed)
    }

    private func pixelRect(_ normalized: CGRect, in image: CGImage) -> CGRect {
        CGRect(
            x: normalized.minX * CGFloat(image.width),
            y: normalized.minY * CGFloat(image.height),
            width: normalized.width * CGFloat(image.width),
            height: normalized.height * CGFloat(image.height)
        )
    }

    /// 每个像素一个颜色，任何一次搬错位置都会在比较里露出来。
    private func makeStripedImage(width: Int, height: Int) throws -> CGImage {
        var bytes: [UInt8] = []
        for row in 0..<height {
            for column in 0..<width {
                bytes.append(UInt8(truncatingIfNeeded: 16 + column * 24))
                bytes.append(UInt8(truncatingIfNeeded: 16 + row * 48))
                bytes.append(UInt8(truncatingIfNeeded: 32 + column * 8 + row * 3))
                bytes.append(255)
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
    }

    /// 重画进一个已知布局的上下文再取字节，绕开各家 CGImage 自带的行对齐差异。
    private func bytes(of image: CGImage) throws -> [UInt8] {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try XCTUnwrap(context.data)
        return Array(UnsafeBufferPointer(
            start: data.assumingMemoryBound(to: UInt8.self),
            count: image.width * image.height * 4
        ))
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
