import AppKit
import FoveaCore
import XCTest
@testable import FoveaApp

/// 画布把图片交给图层承载之后，方向由 `contentTransform` 一处决定。
///
/// 这里只断言这个变换的契约，不去离屏渲染取色。`CALayer.render(in:)` 对翻转
/// 几何的处理和屏幕合成不一致，拿它验方向会得出图片需要额外镜像的错误结论。
@MainActor
final class ImageCanvasRenderingTests: XCTestCase {
    /// 不旋转时不能有任何变换。多一次 y 轴镜像，图片在屏幕上就是上下颠倒的。
    func testUnrotatedContentTransformIsIdentity() {
        XCTAssertTrue(CATransform3DIsIdentity(ImageCanvasView.contentTransform(quarterTurns: 0)))
    }

    /// 每一档都是绕 z 轴的纯旋转，不含缩放和镜像，行列式恒为 1。
    func testEveryQuarterTurnIsAPureRotation() {
        for turns in 0...3 {
            let transform = ImageCanvasView.contentTransform(quarterTurns: turns)
            let affine = CATransform3DGetAffineTransform(transform)
            XCTAssertTrue(
                CATransform3DIsAffine(transform),
                "第 \(turns) 档应当只在平面内旋转"
            )
            let determinant = affine.a * affine.d - affine.b * affine.c
            XCTAssertEqual(determinant, 1, accuracy: 0.0001, "第 \(turns) 档不该出现镜像或缩放")
        }
    }

    /// 视图是翻转的，y 向下，正角度在屏幕上看是顺时针。
    /// 一档要把图片的顶边转到右边，也就是把向上的方向送到向右。
    func testOneQuarterTurnSendsImageTopToTheRight() {
        let affine = CATransform3DGetAffineTransform(ImageCanvasView.contentTransform(quarterTurns: 1))
        // 翻转坐标系里「向上」是 (0, -1)。
        let up = CGPoint(x: 0, y: -1).applying(affine)

        XCTAssertEqual(up.x, 1, accuracy: 0.0001, "顶边应当落到屏幕右侧")
        XCTAssertEqual(up.y, 0, accuracy: 0.0001)
    }

    func testFourQuarterTurnsComeBackToTheStart() {
        let full = ImageCanvasView.contentTransform(quarterTurns: 4)
        let affine = CATransform3DGetAffineTransform(full)

        XCTAssertEqual(affine.a, 1, accuracy: 0.0001)
        XCTAssertEqual(affine.b, 0, accuracy: 0.0001)
        XCTAssertEqual(affine.c, 0, accuracy: 0.0001)
        XCTAssertEqual(affine.d, 1, accuracy: 0.0001)
    }
}
