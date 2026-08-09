import AppKit
import XCTest
@testable import FoveaApp

@MainActor
final class PageNavigationOverlayViewTests: XCTestCase {
    func testControlsUseApprovedSymbolsAndDimensions() {
        let view = PageNavigationOverlayView()

        XCTAssertEqual(PageNavigationOverlayView.controlSize, CGSize(width: 44, height: 64))
        XCTAssertEqual(view.debugPreviousButton.image?.accessibilityDescription, AppStrings.text("menu.view.previousImage"))
        XCTAssertEqual(view.debugNextButton.image?.accessibilityDescription, AppStrings.text("menu.view.nextImage"))
    }

    func testUpdateAppliesSequenceBoundaryStates() {
        let view = PageNavigationOverlayView()

        view.update(previousEnabled: false, nextEnabled: true)

        XCTAssertFalse(view.debugPreviousButton.isEnabled)
        XCTAssertTrue(view.debugNextButton.isEnabled)
    }

    func testButtonsProvideHoverAndPressedFeedback() {
        let view = PageNavigationOverlayView(frame: NSRect(x: 0, y: 0, width: 500, height: 320))
        view.layoutSubtreeIfNeeded()
        let button = view.debugNextButton

        button.setHoveredForTesting(true)
        XCTAssertTrue(button.testingShowsHover)

        button.highlight(true)
        XCTAssertTrue(button.testingShowsPressed)

        button.isEnabled = false
        XCTAssertFalse(button.testingShowsHover)
        XCTAssertFalse(button.testingShowsPressed)
    }

    func testButtonsCallNavigationCallbacks() {
        let view = PageNavigationOverlayView()
        var previousCount = 0
        var nextCount = 0
        view.onPrevious = { previousCount += 1 }
        view.onNext = { nextCount += 1 }

        view.performDebugPrevious()
        view.performDebugNext()

        XCTAssertEqual(previousCount, 1)
        XCTAssertEqual(nextCount, 1)
    }

    func testHitTestingRoutesOnlyVisibleButtonBounds() {
        let view = PageNavigationOverlayView(frame: NSRect(x: 0, y: 0, width: 500, height: 320))
        view.layoutSubtreeIfNeeded()

        let previousButton = view.debugPreviousButton
        let previousCenter = view.convert(
            NSPoint(x: previousButton.bounds.midX, y: previousButton.bounds.midY),
            from: previousButton
        )

        XCTAssertIdentical(view.hitTest(previousCenter), previousButton)
        XCTAssertNil(view.hitTest(NSPoint(x: view.bounds.midX, y: view.bounds.midY)))
    }

    /// 浮层在窗口里不是贴着原点放的，它上下都让开了玻璃 chrome。
    /// 命中测试拿到的点在父视图坐标系里，漏掉换算时可点区域会整体错位。
    func testHitTestingHonoursOverlayOriginInsideItsSuperview() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 380))
        let view = PageNavigationOverlayView(frame: NSRect(x: 0, y: 28, width: 500, height: 320))
        container.addSubview(view)
        view.layoutSubtreeIfNeeded()

        let nextButton = view.debugNextButton
        let topOfButton = NSPoint(x: nextButton.frame.midX, y: nextButton.frame.maxY - 2)
        let containerPoint = container.convert(topOfButton, from: view)

        XCTAssertIdentical(view.hitTest(containerPoint), nextButton)
        XCTAssertNil(view.hitTest(container.convert(
            NSPoint(x: nextButton.frame.midX, y: nextButton.frame.maxY + 12),
            from: view
        )))
    }

    func testButtonsUseGlassBezelInsteadOfHandDrawnLayers() {
        let view = PageNavigationOverlayView()

        for button in [view.debugPreviousButton, view.debugNextButton] {
            XCTAssertEqual(button.bezelStyle, .glass)
            XCTAssertTrue(button.isBordered)
        }
    }

    /// 进出是「淡入淡出加一段贴边位移」，落位之后按钮要回到正常的边距上，
    /// 否则藏起来那段时间量出来的位置是偏的。
    func testPresentationSettlesButtonsAtTheirRestingInset() {
        let view = PageNavigationOverlayView(frame: NSRect(x: 0, y: 0, width: 500, height: 320))
        view.layoutSubtreeIfNeeded()

        view.setPresented(false)

        XCTAssertTrue(view.isHidden)
        XCTAssertEqual(view.debugPreviousButton.frame.minX, PageNavigationOverlayView.edgeInset, accuracy: 0.001)
        XCTAssertEqual(
            view.bounds.maxX - view.debugNextButton.frame.maxX,
            PageNavigationOverlayView.edgeInset,
            accuracy: 0.001
        )

        view.setPresented(true)

        XCTAssertFalse(view.isHidden)
        XCTAssertEqual(view.alphaValue, 1, accuracy: 0.001)
        XCTAssertEqual(view.debugPreviousButton.frame.minX, PageNavigationOverlayView.edgeInset, accuracy: 0.001)
    }

    func testHoverLiftsSymbolToAccentColorAndDisabledDropsIt() {
        let view = PageNavigationOverlayView()
        let button = view.debugNextButton

        XCTAssertEqual(button.contentTintColor, .labelColor)

        button.setHoveredForTesting(true)
        XCTAssertEqual(button.contentTintColor, .controlAccentColor)

        button.isEnabled = false
        XCTAssertEqual(button.contentTintColor, .tertiaryLabelColor)
    }
}
