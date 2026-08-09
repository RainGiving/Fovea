import AppKit
import FoveaCore
import XCTest
@testable import FoveaApp

/// 窗口 chrome 的材质与信息栏布局。
@MainActor
final class ChromeMaterialTests: XCTestCase {
    /// 上下边栏只在环境底图上加渐变染色，不再形成两块独立玻璃。
    func testContentBarsUseAmbientChromeOverThePictureBackdrop() {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))

        XCTAssertTrue(controller.titleBarViewForTesting is AmbientChromeView)
        XCTAssertTrue(controller.bottomBarViewForTesting is AmbientChromeView)
    }

    func testInspectorSidebarUsesTheSharedPanelCornerRadius() {
        XCTAssertEqual(InspectorView(metadata: nil).cornerRadius, GlassMetrics.panelCornerRadius)
    }

    /// 信息栏始终是侧栏。图片通过内边距让位，环境底图仍铺满整窗。
    func testInspectorAlwaysReservesSidebarThroughContentInsets() async throws {
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

    /// 胶片区域进入下边栏后，需要给右侧信息栏留出完整空间。
    func testInspectorSidebarDoesNotCoverTheFilmstrip() async throws {
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
        let filmstripFrame = controller.filmstripOverlayFrameForTesting
        let inspectorFrame = controller.inspectorFrameForTesting

        XCTAssertFalse(
            filmstripFrame.intersects(inspectorFrame),
            "胶卷条 \\(filmstripFrame) 不该压进信息栏 \\(inspectorFrame)"
        )
    }

    /// 右边的翻页按钮同样要让开信息栏。
    func testNextPageButtonStepsAsideForTheInspectorSidebar() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeTestPNG(to: root.appendingPathComponent("a.png"))
        try writeTestPNG(to: root.appendingPathComponent("b.png"))
        let settings = AppSettings(defaults: makeIsolatedDefaults())
        settings.showsInspector = true
        let controller = MainWindowController(settings: settings)
        let window = try XCTUnwrap(controller.window)

        controller.open(url: root.appendingPathComponent("a.png"))
        for _ in 0..<500 where !controller.hasLoadedImageForTesting {
            try await Task.sleep(for: .milliseconds(20))
        }
        window.contentView?.layoutSubtreeIfNeeded()
        let buttonFrame = controller.nextPageButtonFrameForTesting
        let inspectorFrame = controller.inspectorFrameForTesting

        XCTAssertFalse(
            buttonFrame.intersects(inspectorFrame),
            "翻页按钮 \\(buttonFrame) 不该压进信息栏 \\(inspectorFrame)"
        )
        XCTAssertLessThan(buttonFrame.maxX, inspectorFrame.minX, "翻页按钮要完整留在信息栏左侧")
    }

    /// 胶片条在按键当轮开始移动，图片解码期间也有即时反馈。
    func testFilmstripHighlightRespondsWhenNavigationStarts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeTestPNG(to: root.appendingPathComponent("a.png"))
        try writeTestPNG(to: root.appendingPathComponent("b.png"))
        let settings = AppSettings(defaults: makeIsolatedDefaults())
        settings.showsFilmstrip = true
        let controller = MainWindowController(settings: settings)

        controller.open(url: root.appendingPathComponent("a.png"))
        for _ in 0..<500 where controller.navigationItemCountForTesting < 2 {
            try await Task.sleep(for: .milliseconds(20))
        }
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(controller.filmstripHighlightedTitleForTesting, "a")

        // 翻页这一步是同步的，高亮也应在同一轮切到目标条目。
        controller.showNextImageForTesting()
        XCTAssertEqual(controller.currentImageURLForTesting?.lastPathComponent, "b.png", "导航状态已经翻过去了")
        XCTAssertEqual(
            controller.filmstripHighlightedTitleForTesting,
            "b",
            "胶片条不等待解码，按键后立即开始滑动"
        )
    }

    /// 连续浏览本身就是把整个序列铺开滚，再挂一条胶卷等于同一件事说两遍。
    func testFilmstripStandsDownDuringContinuousReading() {
        XCTAssertTrue(MainWindowController.shouldDisplayFilmstripOverlay(
            isEnabled: true,
            hasLoadedImage: true
        ))
        XCTAssertFalse(MainWindowController.shouldDisplayFilmstripOverlay(
            isEnabled: true,
            hasLoadedImage: true,
            usesContinuousReading: true
        ))
    }

    /// 连续浏览的底色由容器那层模糊底负责，文档本身不涂满一片近白。
    func testContinuousReadingDocumentDoesNotPaintAnOpaqueBackground() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let imageURL = root.appendingPathComponent("page.png")
        try writeTestPNG(to: imageURL, side: 400)
        let settings = AppSettings(defaults: makeIsolatedDefaults())
        settings.usesContinuousReading = true
        let controller = MainWindowController(settings: settings)

        controller.open(url: imageURL)
        for _ in 0..<500 where !controller.hasLoadedImageForTesting {
            try await Task.sleep(for: .milliseconds(20))
        }
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        XCTAssertFalse(controller.isFilmstripVisibleForTesting, "连续浏览里胶卷条要让路")

        // 页面窗口是异步算出来的，模糊底跟着那一步落地。
        for _ in 0..<500 where !controller.continuousReadingHasBackdropForTesting {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(
            controller.continuousReadingHasBackdropForTesting,
            "容器要铺上由当前页熬出来的模糊底"
        )
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "FoveaAppTests.ChromeMaterial.\(UUID().uuidString)")!
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
