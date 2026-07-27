import AppKit
import ImageViewCore
import XCTest
@testable import ImageViewApp

/// 窗口 chrome 的材质与信息栏的摆法。
@MainActor
final class ChromeMaterialTests: XCTestCase {
    /// 上下边栏和图片留白区域压着同一层模糊底，边栏要用更透的一档，
    /// 否则会读成另一种材质，和留白那一片对不上。
    func testContentBarsUseClearGlassSoTheySharePictureBackdrop() {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))

        XCTAssertEqual(controller.titleBarGlassStyleForTesting, .clear)
        XCTAssertEqual(controller.bottomBarGlassStyleForTesting, .clear)
    }

    /// 信息栏无论停靠与否都是圆角。以前停靠时改成直角贴边，
    /// 直角和窗口自己的圆角对不齐，边上会露出底下那条直边。
    func testInspectorKeepsItsRoundedCornerWhenDocked() {
        XCTAssertEqual(
            InspectorView(metadata: nil, isDocked: true).cornerRadius,
            GlassMetrics.panelCornerRadius
        )
        XCTAssertEqual(
            InspectorView(metadata: nil, isDocked: false).cornerRadius,
            GlassMetrics.panelCornerRadius
        )
    }

    /// 停靠时让出的是图片的位置，画布本身仍然铺满整窗，
    /// 模糊底才连成一片，浮起的玻璃底下也才有东西可以折射。
    func testDockedInspectorReservesRoomThroughContentInsetsNotByShrinkingTheCanvas() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let imageURL = root.appendingPathComponent("docked.png")
        try writeTestPNG(to: imageURL)
        let settings = AppSettings(defaults: makeIsolatedDefaults())
        settings.showsInspector = true
        let controller = MainWindowController(settings: settings)
        let window = try XCTUnwrap(controller.window)

        controller.open(url: imageURL)
        for _ in 0..<100 where !controller.hasLoadedImageForTesting {
            try await Task.sleep(for: .milliseconds(10))
        }
        window.contentView?.layoutSubtreeIfNeeded()
        let rootWidth = try XCTUnwrap(window.contentView).bounds.width

        XCTAssertFalse(controller.isInspectorDockedForTesting, "默认是浮动的")
        XCTAssertEqual(controller.reservedInspectorWidthForTesting, 0)

        controller.toggleInspectorDockForTesting()
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertTrue(controller.isInspectorDockedForTesting)
        XCTAssertEqual(
            controller.reservedInspectorWidthForTesting,
            GlassMetrics.inspectorWidth + GlassMetrics.floatingInset * 2,
            accuracy: 0.001,
            "让出的是面板宽度加它两侧的间距"
        )
        XCTAssertEqual(
            controller.canvasForTesting.frame.width,
            rootWidth,
            accuracy: 0.5,
            "画布不该被裁窄，否则模糊底到不了面板底下"
        )
        XCTAssertEqual(
            controller.canvasForTesting.contentInsets.right,
            GlassMetrics.inspectorWidth + GlassMetrics.floatingInset * 2,
            accuracy: 0.001
        )
    }

    /// 胶卷条打开之后就该一直在。放大、把焦点挪走都不能让它自己收起来。
    func testFilmstripStaysOnScreenAfterZoomingAndLosingPointerFocus() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let imageURL = root.appendingPathComponent("strip.png")
        // 比窗口大，实际大小才是放大而不是缩小。
        try writeTestPNG(to: imageURL, side: 2_000)
        let settings = AppSettings(defaults: makeIsolatedDefaults())
        settings.showsFilmstrip = true
        let controller = MainWindowController(settings: settings)
        let window = try XCTUnwrap(controller.window)

        controller.open(url: imageURL)
        for _ in 0..<500 where !controller.hasLoadedImageForTesting {
            try await Task.sleep(for: .milliseconds(20))
        }
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertTrue(controller.isFilmstripVisibleForTesting)

        controller.canvasForTesting.zoomToActualSize()
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(controller.canvasForTesting.scale, 1.01, "先确认真的放大了")
        XCTAssertTrue(controller.isFilmstripVisibleForTesting, "放大不该让胶卷条消失")

        // 设置变化经由一次主队列跳转才落到界面上。
        settings.showsFilmstrip = false
        for _ in 0..<100 where controller.isFilmstripVisibleForTesting {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(controller.isFilmstripVisibleForTesting, "只有关掉开关才收起来")
    }

    /// 信息栏停靠时胶卷条要往左收，否则会被压在面板底下。
    func testFilmstripStepsAsideForTheDockedInspector() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let imageURL = root.appendingPathComponent("aside.png")
        try writeTestPNG(to: imageURL)
        let settings = AppSettings(defaults: makeIsolatedDefaults())
        settings.showsFilmstrip = true
        settings.showsInspector = true
        let controller = MainWindowController(settings: settings)
        let window = try XCTUnwrap(controller.window)

        controller.open(url: imageURL)
        for _ in 0..<500 where !controller.hasLoadedImageForTesting {
            try await Task.sleep(for: .milliseconds(20))
        }
        window.contentView?.layoutSubtreeIfNeeded()
        let floatingFrame = controller.filmstripOverlayFrameForTesting

        controller.toggleInspectorDockForTesting()
        window.contentView?.layoutSubtreeIfNeeded()
        let dockedFrame = controller.filmstripOverlayFrameForTesting
        let inspectorFrame = controller.inspectorFrameForTesting

        XCTAssertFalse(
            dockedFrame.intersects(inspectorFrame),
            "胶卷条 \\(dockedFrame) 不该压进信息栏 \\(inspectorFrame)"
        )
        XCTAssertLessThan(dockedFrame.maxX, floatingFrame.maxX, "右沿要往左收")
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ImageViewAppTests.ChromeMaterial.\(UUID().uuidString)")!
    }

    private func writeTestPNG(to url: URL, side: Int = 2) throws {
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        try XCTUnwrap(representation?.representation(using: .png, properties: [:])).write(to: url)
    }
}
