import AppKit
import XCTest
@testable import ImageViewApp

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

    func testOverlayUsesAppearanceAdaptiveBorderAndBackground() {
        XCTAssertEqual(PageNavigationOverlayView.backgroundColor, .windowBackgroundColor)
        XCTAssertEqual(PageNavigationOverlayView.borderColor, .separatorColor)
        XCTAssertEqual(PageNavigationOverlayView.borderWidth(forBackingScaleFactor: 2), 0.5)
    }
}
