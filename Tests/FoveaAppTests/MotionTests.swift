import AppKit
import XCTest
@testable import FoveaApp

@MainActor
final class MotionTests: XCTestCase {
    private func makeSlideFixture() -> (root: NSView, panel: NSView, constraint: NSLayoutConstraint) {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let panel = NSView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.wantsLayer = true
        root.addSubview(panel)
        let bottom = panel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14)
        NSLayoutConstraint.activate([
            bottom,
            panel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            panel.widthAnchor.constraint(equalToConstant: 120),
            panel.heightAnchor.constraint(equalToConstant: 40)
        ])
        root.layoutSubtreeIfNeeded()
        return (root, panel, bottom)
    }

    /// 没上屏就没有动画可播，状态必须当场落地。
    func testViewsOutsideAVisibleWindowSkipAnimation() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertFalse(Motion.canAnimate(view), "没有窗口不播动画")
        XCTAssertFalse(Motion.canAnimate(nil))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(view)
        XCTAssertFalse(Motion.canAnimate(view), "窗口没显示出来同样不播")
    }

    func testSetVisibleAppliesTheFinalStateImmediatelyWhenNotAnimating() {
        let fixture = makeSlideFixture()
        let slide = Motion.Slide(fixture.constraint, visible: -14, hidden: 2, in: fixture.root)
        fixture.panel.isHidden = true

        Motion.setVisible(fixture.panel, true, slide: slide)

        XCTAssertFalse(fixture.panel.isHidden)
        XCTAssertEqual(fixture.panel.alphaValue, 1, accuracy: 0.001)
        XCTAssertEqual(fixture.constraint.constant, -14, accuracy: 0.001)

        Motion.setVisible(fixture.panel, false, slide: slide)

        XCTAssertTrue(fixture.panel.isHidden, "不播动画时收起当场生效，不等收尾")
        XCTAssertEqual(fixture.panel.alphaValue, 0, accuracy: 0.001)
    }

    /// 位移只是过场，藏起来之后约束要回到原位，
    /// 否则量这块浮层位置的人会读到一个偏出去的值。
    func testHiddenPanelKeepsItsRestingConstraint() {
        let fixture = makeSlideFixture()
        let slide = Motion.Slide(fixture.constraint, visible: -14, hidden: 2, in: fixture.root)

        Motion.setVisible(fixture.panel, false, slide: slide)

        XCTAssertEqual(fixture.constraint.constant, -14, accuracy: 0.001)
    }

    /// 收起的常数本身就是新布局时（边栏高度收到零）不能被放回去。
    func testSlideCanKeepItsHiddenConstant() {
        let fixture = makeSlideFixture()
        let slide = Motion.Slide(
            fixture.constraint,
            visible: -14,
            hidden: 0,
            in: fixture.root,
            restoresWhenHidden: false
        )

        Motion.setVisible(fixture.panel, false, slide: slide)

        XCTAssertEqual(fixture.constraint.constant, 0, accuracy: 0.001)
    }

    func testRunCallsCompletionSynchronouslyWhenNotAnimating() {
        let view = NSView()
        var didFinish = false

        Motion.run(in: view, duration: Motion.standard) {
            view.alphaValue = 0.5
        } completion: {
            didFinish = true
        }

        XCTAssertTrue(didFinish, "不播动画时收尾要同步跑完")
        XCTAssertEqual(view.alphaValue, 0.5, accuracy: 0.001)
    }

    /// 缩放绕视图中心做：中心点在变换前后落在同一处。
    func testCenteredScaleKeepsTheCenterInPlace() {
        let bounds = CGRect(x: 0, y: 0, width: 24, height: 24)
        let transform = CATransform3DGetAffineTransform(Motion.centeredScale(0.5, in: bounds))
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        let mapped = center.applying(transform)

        XCTAssertEqual(mapped.x, center.x, accuracy: 0.001)
        XCTAssertEqual(mapped.y, center.y, accuracy: 0.001)
        // 角落按倍率朝中心收。
        let corner = CGPoint.zero.applying(transform)
        XCTAssertEqual(corner.x, 6, accuracy: 0.001)
        XCTAssertEqual(corner.y, 6, accuracy: 0.001)
    }

    func testEaseOutStartsFastAndSettles() {
        XCTAssertEqual(Motion.easeOut(0), 0, accuracy: 0.001)
        XCTAssertEqual(Motion.easeOut(1), 1, accuracy: 0.001)
        XCTAssertEqual(Motion.easeOut(-1), 0, accuracy: 0.001)
        XCTAssertEqual(Motion.easeOut(2), 1, accuracy: 0.001)
        XCTAssertGreaterThan(Motion.easeOut(0.5), 0.5, "缓出曲线的前半段走得更快")
    }

    func testInterpolateWalksBetweenTwoRects() {
        let from = CGRect(x: 0, y: 0, width: 100, height: 100)
        let to = CGRect(x: 20, y: 40, width: 60, height: 20)

        XCTAssertEqual(Motion.interpolate(from, to, progress: 0), from)
        XCTAssertEqual(Motion.interpolate(from, to, progress: 1), to)
        XCTAssertEqual(
            Motion.interpolate(from, to, progress: 0.5),
            CGRect(x: 10, y: 20, width: 80, height: 60)
        )
        XCTAssertEqual(Motion.interpolate(from, to, progress: 3), to, "进度超出范围要夹住")
    }

    /// 退场比入场快一档，东西离开时不该让人等。
    func testExitIsShorterThanEntrance() {
        XCTAssertLessThan(Motion.exitRatio, 1)
        XCTAssertLessThan(Motion.quick, Motion.standard)
        XCTAssertLessThan(Motion.standard, Motion.expressive)
    }
}
