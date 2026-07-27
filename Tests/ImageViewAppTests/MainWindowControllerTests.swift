import AppKit
import ImageViewCore
import XCTest
@testable import ImageViewApp

@MainActor
final class MainWindowControllerTests: XCTestCase {
    func testFilmstripSitsAboveBottomBarAndNeverCoversIt() throws {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        let window = try XCTUnwrap(controller.window)
        window.setContentSize(NSSize(width: 1100, height: 760))
        window.contentView?.layoutSubtreeIfNeeded()

        let filmstrip = controller.filmstripOverlayFrameForTesting
        let bottomBar = controller.bottomBarFrameForTesting

        XCTAssertFalse(filmstrip.intersects(bottomBar))
        // rootView 未翻转，y 向上增长，胶卷条的下沿必须高于下边栏的上沿。
        XCTAssertGreaterThanOrEqual(filmstrip.minY, bottomBar.maxY)
    }

    /// 没有图可编辑的时候按钮不该可按，也不该亮着。
    func testTitleBarEditButtonStartsDisabledAndUnlit() {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        let button = controller.titleBarEditButtonForTesting

        XCTAssertNotNil(button.image)
        XCTAssertFalse(button.isEnabled)
        XCTAssertFalse(button.isOnState)
    }

    func testTitleBarEditButtonAvailabilityFollowsTheCurrentMode() {
        XCTAssertTrue(MainWindowController.canEditFromTitleBar(
            canEditCurrentImage: true,
            isFolderBrowserMode: false,
            usesContinuousReading: false
        ))
        // 文件夹网格里没有「当前这一张」，连续阅读也不进编辑。
        XCTAssertFalse(MainWindowController.canEditFromTitleBar(
            canEditCurrentImage: true,
            isFolderBrowserMode: true,
            usesContinuousReading: false
        ))
        XCTAssertFalse(MainWindowController.canEditFromTitleBar(
            canEditCurrentImage: true,
            isFolderBrowserMode: false,
            usesContinuousReading: true
        ))
        XCTAssertFalse(MainWindowController.canEditFromTitleBar(
            canEditCurrentImage: false,
            isFolderBrowserMode: false,
            usesContinuousReading: false
        ))
    }

    func testTitleBarFilmstripButtonMirrorsTheSetting() {
        let settings = AppSettings(defaults: makeIsolatedDefaults())
        settings.showsFilmstrip = false
        let controller = MainWindowController(settings: settings)
        let button = controller.titleBarFilmstripButtonForTesting

        XCTAssertFalse(button.isOnState)

        controller.toggleFilmstrip(nil)

        XCTAssertTrue(settings.showsFilmstrip)
        XCTAssertTrue(button.isOnState)

        controller.toggleFilmstrip(nil)

        XCTAssertFalse(settings.showsFilmstrip)
        XCTAssertFalse(button.isOnState)
    }

    /// 更多菜单只放上边栏上没有的功能，已经有按钮的不再重复一遍。
    func testContextMenuDoesNotRepeatWhatTheTitleBarAlreadyOffers() {
        let actions = ImageContextMenuBuilder.sections.flatMap { $0 }.map(\.action)

        XCTAssertFalse(actions.contains(#selector(MainWindowController.toggleFilmstrip(_:))))
        XCTAssertFalse(actions.contains(#selector(MainWindowController.toggleContinuousReading(_:))))
        // 信息面板的开关不在上边栏，留在菜单里。
        XCTAssertTrue(actions.contains(#selector(MainWindowController.toggleInspector(_:))))
    }

    /// 右键菜单的编辑图标和上边栏那颗保持一致，同一件事只有一个图形。
    func testContextMenuEditUsesTheSameSymbolAsTheTitleBarButton() {
        let editCommand = ImageContextMenuBuilder.sections.flatMap { $0 }.first {
            $0.action == #selector(MainWindowController.startEditingImage(_:))
        }

        XCTAssertEqual(editCommand?.symbolName, "crop.rotate")
    }

    func testOpenRequestMarksWindowAssignedBeforeDecodeCompletes() {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        XCTAssertFalse(controller.hasAssignedOpenRequest)

        controller.open(url: URL(fileURLWithPath: "/missing/image.png"))

        XCTAssertTrue(controller.hasAssignedOpenRequest)
    }

    func testWindowLifecycleCallbacksIdentifyTheirController() throws {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        var keyController: MainWindowController?
        var closedController: MainWindowController?
        controller.onWindowDidBecomeKey = { keyController = $0 }
        controller.onWindowDidClose = { closedController = $0 }
        let window = try XCTUnwrap(controller.window)

        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: window))
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))

        XCTAssertTrue(keyController === controller)
        XCTAssertTrue(closedController === controller)
    }

    func testBottomBarInfoControlUsesStandardInfoSymbol() {
        XCTAssertEqual(MainWindowController.bottomBarInfoSymbolName, "info.circle")
    }

    func testBottomBarStatusUsesCompactTrailingSpacing() {
        XCTAssertEqual(MainWindowController.bottomBarStatusToInfoSpacing, 8)
    }

    func testStatusBarFormatsDimensionsPageAndZoomIndependently() {
        let first = ImageItem(url: URL(fileURLWithPath: "/tmp/first.png"), format: .png)
        let second = ImageItem(url: URL(fileURLWithPath: "/tmp/second.png"), format: .png)
        let state = NavigationState(items: [first, second], currentURL: second.url)

        XCTAssertEqual(
            MainWindowController.dimensionText(pixelWidth: 6000, pixelHeight: 4000),
            "6000 × 4000 px"
        )
        XCTAssertEqual(
            MainWindowController.dimensionText(pixelWidth: nil, pixelHeight: nil),
            "— × — px"
        )
        XCTAssertEqual(MainWindowController.pageText(navigationState: state), "2 / 2")
        XCTAssertEqual(MainWindowController.pageText(navigationState: nil), "0 / 0")
        XCTAssertEqual(MainWindowController.zoomText(zoomScale: 1.25), "125%")
        XCTAssertEqual(
            MainWindowController.zoomText(displayMode: .manual, pixelScale: 1.25),
            "125%"
        )
        XCTAssertFalse(
            MainWindowController.zoomText(displayMode: .fit, pixelScale: 0.82).hasPrefix("100%")
        )
    }

    func testCustomTitleBarHidesNativeWindowTitle() {
        let controller = MainWindowController()

        XCTAssertEqual(controller.window?.titleVisibility, .hidden)
    }

    func testDoubleClickTitleBarTogglesWindowZoom() throws {
        let controller = MainWindowController()
        let window = try XCTUnwrap(controller.window)
        let initialZoomState = window.isZoomed

        controller.toggleWindowZoom(nil)

        XCTAssertNotEqual(window.isZoomed, initialZoomState)
    }

    func testContentBarsReserveStableSpaceAroundCanvas() {
        XCTAssertEqual(MainWindowController.titleBarHeight, 32)
        XCTAssertEqual(MainWindowController.bottomBarHeight, 28)
    }

    func testShouldResetCanvasTransformOnlyWhenDisplayedItemChanges() {
        let first = URL(fileURLWithPath: "/tmp/first.png")
        let firstDuplicate = URL(fileURLWithPath: "/tmp/./first.png")
        let second = URL(fileURLWithPath: "/tmp/second.png")

        XCTAssertTrue(MainWindowController.shouldResetCanvasTransform(from: nil, to: first))
        XCTAssertFalse(MainWindowController.shouldResetCanvasTransform(from: first, to: firstDuplicate))
        XCTAssertTrue(MainWindowController.shouldResetCanvasTransform(from: first, to: second))
        XCTAssertTrue(MainWindowController.shouldResetCanvasTransform(from: first, to: nil))
        XCTAssertFalse(MainWindowController.shouldResetCanvasTransform(from: nil, to: nil))
    }

    func testKeyActionRoutesNavigationAndFullscreenKeys() {
        XCTAssertEqual(MainWindowController.keyAction(for: 123, shouldEndEditing: false), .showPrevious)
        XCTAssertEqual(MainWindowController.keyAction(for: 124, shouldEndEditing: false), .showNext)
        XCTAssertEqual(MainWindowController.keyAction(for: 51, shouldEndEditing: false), .moveToTrash)
        XCTAssertEqual(MainWindowController.keyAction(for: 49, shouldEndEditing: false), .toggleZoom)
        XCTAssertEqual(MainWindowController.keyAction(for: 36, shouldEndEditing: false), .toggleFullscreen)
        XCTAssertEqual(
            MainWindowController.keyAction(for: 13, shouldEndEditing: false, modifierFlags: [.command]),
            .closeWindow
        )
    }

    func testFolderBrowserModePassesThroughViewerOnlyKeyActions() {
        XCTAssertEqual(
            MainWindowController.keyAction(for: 123, shouldEndEditing: false, isFolderBrowserMode: true),
            .passThrough
        )
        XCTAssertEqual(
            MainWindowController.keyAction(for: 124, shouldEndEditing: false, isFolderBrowserMode: true),
            .passThrough
        )
        XCTAssertEqual(
            MainWindowController.keyAction(for: 51, shouldEndEditing: false, isFolderBrowserMode: true),
            .passThrough
        )
        XCTAssertEqual(
            MainWindowController.keyAction(for: 49, shouldEndEditing: false, isFolderBrowserMode: true),
            .passThrough
        )
        XCTAssertEqual(
            MainWindowController.keyAction(
                for: 40,
                shouldEndEditing: false,
                modifierFlags: [.command],
                isFolderBrowserMode: true
            ),
            .passThrough
        )
        XCTAssertEqual(
            MainWindowController.keyAction(for: 36, shouldEndEditing: false, isFolderBrowserMode: true),
            .passThrough
        )
    }

    func testMenuCommandMapsViewSelectors() {
        XCTAssertEqual(
            MainWindowController.menuCommand(for: #selector(MainWindowController.showPreviousImage(_:))),
            .navigation
        )
        XCTAssertEqual(
            MainWindowController.menuCommand(for: #selector(MainWindowController.actualSize(_:))),
            .canvasSizing
        )
    }

    func testEscapeOnlyEndsEditingWhenDismissibleEditingStateExists() {
        XCTAssertEqual(MainWindowController.keyAction(for: 53, shouldEndEditing: true), .endEditing)
        XCTAssertEqual(MainWindowController.keyAction(for: 53, shouldEndEditing: false), .passThrough)
    }

    func testCropKeyActionsOverrideNormalWindowActionsWhileCropping() {
        XCTAssertEqual(
            MainWindowController.keyAction(
                for: 40,
                shouldEndEditing: false,
                isCropping: false,
                modifierFlags: [.command]
            ),
            .startCropping
        )
        XCTAssertEqual(
            MainWindowController.keyAction(for: 36, shouldEndEditing: false, isCropping: true),
            .applyCrop
        )
        XCTAssertEqual(
            MainWindowController.keyAction(for: 53, shouldEndEditing: false, isCropping: true),
            .cancelCrop
        )
    }

    func testWindowActivationRequestsExternalFileRefresh() {
        XCTAssertTrue(MainWindowController.shouldRefreshCurrentFileOnWindowActivation())
    }

    func testExternalFileCheckIntervalStaysLightweight() {
        XCTAssertEqual(MainWindowController.externalFileCheckInterval, 2)
    }

    func testDroppedDirectoryDetectionDistinguishesFoldersFromFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("image.png")
        try Data().write(to: file)

        XCTAssertTrue(MainWindowController.isDirectoryURL(root))
        XCTAssertFalse(MainWindowController.isDirectoryURL(file))
    }

    func testResolveUnsavedChangesProceedsOnlyForDiscardOrSuccessfulSave() {
        XCTAssertEqual(
            MainWindowController.resolveUnsavedChanges(choice: .save, saveSucceeded: true),
            .proceed
        )
        XCTAssertEqual(
            MainWindowController.resolveUnsavedChanges(choice: .save, saveSucceeded: false),
            .stayOnCurrentImage
        )
        XCTAssertEqual(
            MainWindowController.resolveUnsavedChanges(choice: .discard, saveSucceeded: false),
            .proceed
        )
        XCTAssertEqual(
            MainWindowController.resolveUnsavedChanges(choice: .cancel, saveSucceeded: false),
            .stayOnCurrentImage
        )
    }

    func testMenuCommandMapsEditSelectorsToExpectedOperations() {
        XCTAssertEqual(
            MainWindowController.menuCommand(for: #selector(MainWindowController.startCropping(_:))),
            .startCropping
        )
        XCTAssertEqual(
            MainWindowController.menuCommand(for: #selector(MainWindowController.rotateClockwise(_:))),
            .editOperation(.rotateClockwise)
        )
        XCTAssertEqual(
            MainWindowController.menuCommand(for: #selector(MainWindowController.rotateCounterClockwise(_:))),
            .editOperation(.rotateCounterClockwise)
        )
        XCTAssertEqual(
            MainWindowController.menuCommand(for: #selector(MainWindowController.mirrorHorizontal(_:))),
            .editOperation(.mirrorHorizontal)
        )
        XCTAssertEqual(
            MainWindowController.menuCommand(for: #selector(MainWindowController.mirrorVertical(_:))),
            .editOperation(.mirrorVertical)
        )
        XCTAssertEqual(
            MainWindowController.menuCommand(for: #selector(MainWindowController.saveEdits(_:))),
            .saveEdits
        )
        XCTAssertEqual(
            MainWindowController.menuCommand(for: #selector(MainWindowController.saveEditsAs(_:))),
            .saveEditsAs
        )
        XCTAssertEqual(
            MainWindowController.menuCommand(for: #selector(MainWindowController.discardEdits(_:))),
            .discardEdits
        )
    }

    func testMenuCommandAvailabilityRequiresFullImageForEditingButKeepsPreviewViewingAvailable() {
        XCTAssertFalse(
            MainWindowController.isMenuCommandEnabled(
                .startCropping,
                hasCurrentItem: true,
                hasCurrentImage: false,
                canEditCurrentImage: false,
                hasUnsavedEdits: false
            )
        )
        XCTAssertFalse(
            MainWindowController.isMenuCommandEnabled(
                .startCropping,
                hasCurrentItem: true,
                hasCurrentImage: true,
                canEditCurrentImage: false,
                hasUnsavedEdits: false
            )
        )
        XCTAssertFalse(
            MainWindowController.isMenuCommandEnabled(
                .editOperation(.rotateClockwise),
                hasCurrentItem: true,
                hasCurrentImage: true,
                canEditCurrentImage: false,
                hasUnsavedEdits: false
            )
        )
        XCTAssertTrue(
            MainWindowController.isMenuCommandEnabled(
                .editOperation(.mirrorHorizontal),
                hasCurrentItem: false,
                hasCurrentImage: true,
                canEditCurrentImage: true,
                hasUnsavedEdits: false
            )
        )
        XCTAssertFalse(
            MainWindowController.isMenuCommandEnabled(
                .saveEdits,
                hasCurrentItem: true,
                hasCurrentImage: true,
                canEditCurrentImage: false,
                hasUnsavedEdits: true
            )
        )
        XCTAssertFalse(
            MainWindowController.isMenuCommandEnabled(
                .saveEditsAs,
                hasCurrentItem: true,
                hasCurrentImage: true,
                canEditCurrentImage: false,
                hasUnsavedEdits: true
            )
        )
        XCTAssertTrue(
            MainWindowController.isMenuCommandEnabled(
                .saveEditsAs,
                hasCurrentItem: true,
                hasCurrentImage: true,
                canEditCurrentImage: true,
                hasUnsavedEdits: true
            )
        )
        XCTAssertTrue(
            MainWindowController.isMenuCommandEnabled(
                .canvasSizing,
                hasCurrentItem: true,
                hasCurrentImage: true,
                canEditCurrentImage: false,
                hasUnsavedEdits: false
            )
        )
        XCTAssertTrue(
            MainWindowController.isMenuCommandEnabled(
                .navigation,
                hasCurrentItem: true,
                hasCurrentImage: true,
                canEditCurrentImage: false,
                hasUnsavedEdits: false
            )
        )
    }

    func testFolderBrowserModeDisablesViewerOnlyMenuCommands() {
        let viewerOnlyCommands: [MainWindowController.MenuCommand] = [
            .fileOperationRequiringCurrentItem,
            .navigation,
            .canvasSizing,
            .startCropping,
            .editOperation(.rotateClockwise),
            .saveEdits,
            .saveEditsAs,
            .discardEdits
        ]

        for command in viewerOnlyCommands {
            XCTAssertFalse(
                MainWindowController.isMenuCommandEnabled(
                    command,
                    hasCurrentItem: true,
                    hasCurrentImage: true,
                    canEditCurrentImage: true,
                    hasUnsavedEdits: true,
                    isFolderBrowserMode: true
                ),
                "\(command) should be disabled while the folder browser owns the canvas"
            )
        }
    }

    func testValidateMenuItemDisablesHiddenViewerCommandsInFolderMode() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let imageURL = root.appendingPathComponent("one.png")
        try writeTestPNG(to: imageURL)
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        controller.open(url: imageURL)
        for _ in 0..<100 where !controller.hasLoadedImageForTesting {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(controller.hasLoadedImageForTesting)
        controller.openFolderForTesting(root, items: [ImageItem(url: imageURL, format: .png)])

        let rename = NSMenuItem(title: "Rename", action: #selector(MainWindowController.renameCurrentImage(_:)), keyEquivalent: "")
        let reveal = NSMenuItem(title: "Reveal", action: #selector(MainWindowController.revealCurrentImageInFinder(_:)), keyEquivalent: "")
        let trash = NSMenuItem(title: "Trash", action: #selector(MainWindowController.moveCurrentImageToTrash(_:)), keyEquivalent: "")
        let rotate = NSMenuItem(title: "Rotate", action: #selector(MainWindowController.rotateClockwise(_:)), keyEquivalent: "")
        let crop = NSMenuItem(title: "Crop", action: #selector(MainWindowController.startCropping(_:)), keyEquivalent: "")
        let zoom = NSMenuItem(title: "Zoom", action: #selector(MainWindowController.zoomToFit(_:)), keyEquivalent: "")

        for item in [rename, reveal, trash, rotate, crop, zoom] {
            XCTAssertFalse(controller.validateMenuItem(item), "\(item.title) should not target the hidden viewer")
        }
    }

    func testEnteringFolderBrowserEndsActiveCropSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let imageURL = root.appendingPathComponent("crop.png")
        try writeTestPNG(to: imageURL)
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))

        controller.open(url: imageURL)
        for _ in 0..<100 where !controller.hasLoadedImageForTesting {
            try await Task.sleep(for: .milliseconds(10))
        }
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        controller.startCropping(nil)
        XCTAssertTrue(controller.isCroppingForTesting)
        let continuousReading = NSMenuItem(
            title: "Continuous Reading",
            action: #selector(MainWindowController.toggleContinuousReading(_:)),
            keyEquivalent: ""
        )
        XCTAssertFalse(controller.validateMenuItem(continuousReading))

        controller.openFolderForTesting(root, items: [ImageItem(url: imageURL, format: .png)])

        XCTAssertFalse(controller.isCroppingForTesting)
    }

    /// 标题栏那颗编辑按钮是开关：按一下进编辑并亮起，再按一下退出并熄灭。
    func testTitleBarEditButtonTogglesEditingAndTracksItsState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let imageURL = root.appendingPathComponent("editable.png")
        try writeTestPNG(to: imageURL)
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))

        controller.open(url: imageURL)
        for _ in 0..<100 where !controller.hasLoadedImageForTesting {
            try await Task.sleep(for: .milliseconds(10))
        }
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        let button = controller.titleBarEditButtonForTesting

        XCTAssertTrue(button.isEnabled)
        XCTAssertFalse(button.isOnState)

        button.performClick(nil)
        XCTAssertTrue(controller.isCroppingForTesting)
        XCTAssertTrue(button.isOnState)

        button.performClick(nil)
        XCTAssertFalse(controller.isCroppingForTesting)
        XCTAssertFalse(button.isOnState)
    }

    /// 翻到下一张、解码完成之后，编辑按钮必须还能按。
    ///
    /// 能不能编辑取决于 loadPhase 走到 full，而 loadPhase 自己原来不触发按钮刷新，
    /// 全靠导航状态那一路顺带带到。这条盯住的是最终状态一致，不是那条时序本身。
    func testTitleBarEditButtonStaysEnabledAfterNavigatingToAnotherImage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("a.png")
        let second = root.appendingPathComponent("b.png")
        try writeTestPNG(to: first)
        try writeTestPNG(to: second)
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))

        controller.open(url: first)
        // 整套测试一起跑时解码会慢，等待额度给宽一点。
        for _ in 0..<500 where !controller.hasLoadedImageForTesting {
            try await Task.sleep(for: .milliseconds(20))
        }
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        XCTAssertTrue(controller.titleBarEditButtonForTesting.isEnabled)

        // 打开时先发一份只含当前项的导航状态，扫完目录才有第二张可翻。
        for _ in 0..<500 where controller.navigationItemCountForTesting < 2 {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(controller.navigationItemCountForTesting, 2, "先等目录扫描把两张都列出来")

        controller.showNextImageForTesting()
        let target = second.standardizedFileURL.resolvingSymlinksInPath()
        // 等到新的一张真的解完，视图模型认为可以编辑为止。
        for _ in 0..<500 where !(
            controller.currentImageURLForTesting?.resolvingSymlinksInPath() == target
                && controller.canEditCurrentImageForTesting
        ) {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(
            controller.currentImageURLForTesting?.resolvingSymlinksInPath(),
            target,
            "先确认真的翻过去了"
        )
        XCTAssertTrue(controller.canEditCurrentImageForTesting, "视图模型这一侧应当已经可以编辑")
        XCTAssertTrue(controller.titleBarEditButtonForTesting.isEnabled, "翻页之后编辑按钮不该变灰")
    }

    /// 按钮要真的能被鼠标命中。performClick 绕开了事件派发，测不出这一层。
    func testTitleBarButtonsAreReachableByRealHitTesting() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let imageURL = root.appendingPathComponent("hittest.png")
        try writeTestPNG(to: imageURL)
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        let window = try XCTUnwrap(controller.window)

        controller.open(url: imageURL)
        for _ in 0..<100 where !controller.hasLoadedImageForTesting {
            try await Task.sleep(for: .milliseconds(10))
        }
        let rootView = try XCTUnwrap(window.contentView)
        rootView.layoutSubtreeIfNeeded()

        for button: NSButton in [
            controller.titleBarGridButtonForTesting,
            controller.titleBarFilmstripButtonForTesting,
            controller.titleBarEditButtonForTesting
        ] {
            XCTAssertGreaterThan(button.bounds.width, 0, "按钮要先有尺寸")
            let center = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
            let hit = rootView.hitTest(center)
            XCTAssertTrue(
                hit === button || hit?.isDescendant(of: button) == true,
                "点在 \(button.toolTip ?? "?") 上应当命中它自己，实际命中 \(String(describing: hit))"
            )
        }
    }

    func testFullImageLoadProducesOneConciseAccessibilityAnnouncement() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let imageURL = root.appendingPathComponent("announced.png")
        try writeTestPNG(to: imageURL)
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        var announcements: [String] = []
        controller.accessibilityAnnouncementHandlerForTesting = { announcements.append($0) }

        controller.open(url: imageURL)
        for _ in 0..<100 where announcements.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(announcements, [
            String(format: AppStrings.text("viewer.announcement.loaded"), imageURL.lastPathComponent)
        ])
    }

    func testCanvasBackgroundAlwaysUsesSystemAppearance() {
        XCTAssertEqual(MainWindowController.canvasBackgroundColor(), .windowBackgroundColor)
    }

    func testEmptyStateOnlyAppearsForARealNonErrorEmptyWindow() {
        XCTAssertTrue(MainWindowController.shouldDisplayEmptyState(
            hasCurrentImage: false,
            loadPhase: .empty,
            hasError: false
        ))

        for phase in [ImageLoadPhase.loading, .preview, .full, .failed] {
            XCTAssertFalse(MainWindowController.shouldDisplayEmptyState(
                hasCurrentImage: false,
                loadPhase: phase,
                hasError: false
            ))
        }

        XCTAssertFalse(MainWindowController.shouldDisplayEmptyState(
            hasCurrentImage: true,
            loadPhase: .empty,
            hasError: false
        ))
        XCTAssertFalse(MainWindowController.shouldDisplayEmptyState(
            hasCurrentImage: false,
            loadPhase: .empty,
            hasError: true
        ))
    }

    func testNewWindowShowsEmptyStateAndHidesImageOnlyStatus() {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))

        XCTAssertTrue(controller.isEmptyStateVisibleForTesting)
        XCTAssertTrue(controller.isImageStatusContentHiddenForTesting)
    }

    func testImageStatusContentOnlyAppearsWhenAnImageExists() {
        XCTAssertTrue(MainWindowController.shouldHideImageStatusContent(hasCurrentImage: false))
        XCTAssertFalse(MainWindowController.shouldHideImageStatusContent(hasCurrentImage: true))
    }

    func testInspectorRequiresBothTheSettingAndAnImage() {
        XCTAssertFalse(MainWindowController.shouldDisplayInspector(
            isEnabled: false,
            hasCurrentImage: false
        ))
        XCTAssertFalse(MainWindowController.shouldDisplayInspector(
            isEnabled: true,
            hasCurrentImage: false
        ))
        XCTAssertFalse(MainWindowController.shouldDisplayInspector(
            isEnabled: false,
            hasCurrentImage: true
        ))
        XCTAssertTrue(MainWindowController.shouldDisplayInspector(
            isEnabled: true,
            hasCurrentImage: true
        ))
    }

    func testNewEmptyWindowHidesPreviouslyEnabledInspector() {
        let defaults = makeIsolatedDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.showsInspector = true

        let controller = MainWindowController(settings: settings)

        XCTAssertFalse(controller.isInspectorVisibleForTesting)
    }

    func testEmptyStateOpenRequestIsForwarded() {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        var requestCount = 0
        controller.onOpenRequested = { requestCount += 1 }

        controller.requestOpenFromEmptyStateForTesting()

        XCTAssertEqual(requestCount, 1)
    }

    func testEmptyStateBrowseFolderRequestIsForwarded() {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        var requestCount = 0
        controller.onBrowseFolderRequested = { requestCount += 1 }

        controller.requestBrowseFolderFromEmptyStateForTesting()

        XCTAssertEqual(requestCount, 1)
    }

    func testErrorStateOnlyAppearsForAnErrorWithoutAnImage() {
        XCTAssertTrue(MainWindowController.shouldDisplayErrorState(
            hasCurrentImage: false,
            hasError: true
        ))
        XCTAssertFalse(MainWindowController.shouldDisplayErrorState(
            hasCurrentImage: true,
            hasError: true
        ))
        XCTAssertFalse(MainWindowController.shouldDisplayErrorState(
            hasCurrentImage: false,
            hasError: false
        ))
    }

    func testErrorStateOpenRequestIsForwarded() {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        var requestCount = 0
        controller.onOpenRequested = { requestCount += 1 }

        controller.requestOpenFromErrorStateForTesting()

        XCTAssertEqual(requestCount, 1)
    }

    func testCancelledRetryResetsFailedWindowForReuse() async {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        controller.open(url: URL(fileURLWithPath: "/tmp/not-an-image.txt"))
        for _ in 0..<100 where !controller.isShowingRecoverableErrorForTesting {
            await Task.yield()
        }
        XCTAssertTrue(controller.isShowingRecoverableErrorForTesting)

        controller.returnToEmptyStateAfterCancelledOpen()

        XCTAssertTrue(controller.isEmptyStateVisibleForTesting)
        XCTAssertFalse(controller.isErrorStateVisibleForTesting)
        XCTAssertFalse(controller.hasAssignedOpenRequest)
    }

    func testErrorStateGetsVisibleLayoutAfterFailedOpen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let invalidPNG = root.appendingPathComponent("invalid.png")
        try Data("not an image".utf8).write(to: invalidPNG)

        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        controller.showWindow(nil)
        controller.open(url: invalidPNG)
        for _ in 0..<100 where !controller.isShowingRecoverableErrorForTesting {
            try await Task.sleep(for: .milliseconds(10))
        }

        controller.window?.contentView?.layoutSubtreeIfNeeded()
        let button = try XCTUnwrap(controller.errorRetryButtonForTesting)
        var ancestor: NSView? = button
        while let current = ancestor, !(current is ErrorStateView) {
            ancestor = current.superview
        }
        let errorStateView = try XCTUnwrap(ancestor)

        XCTAssertGreaterThan(errorStateView.frame.width, 0)
        XCTAssertGreaterThan(errorStateView.frame.height, 0)
        var visibilityChain: [String] = []
        var visibilityAncestor: NSView? = errorStateView
        while let current = visibilityAncestor {
            visibilityChain.append("\(type(of: current)): hidden=\(current.isHidden) frame=\(current.frame)")
            visibilityAncestor = current.superview
        }
        XCTAssertFalse(
            errorStateView.isHiddenOrHasHiddenAncestor,
            visibilityChain.joined(separator: " | ")
        )
    }

    func testErrorStateButtonHasNoGestureRecognizerInAncestorChain() throws {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        let button = try XCTUnwrap(controller.errorRetryButtonForTesting)
        var ancestor = button.superview
        while let view = ancestor {
            XCTAssertTrue(view.gestureRecognizers.isEmpty)
            ancestor = view.superview
        }
    }

    func testEmptyStateOpenButtonHasNoGestureRecognizerInAncestorChain() throws {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        let contentView = try XCTUnwrap(controller.window?.contentView)

        func findOpenButton(in view: NSView) -> NSButton? {
            if let button = view as? NSButton,
               button.title == "打开图片…" || button.title == "Open Image…" {
                return button
            }
            return view.subviews.lazy.compactMap(findOpenButton).first
        }

        let button = try XCTUnwrap(findOpenButton(in: contentView))
        var ancestor = button.superview
        while let view = ancestor {
            XCTAssertTrue(
                view.gestureRecognizers.isEmpty,
                "Interactive empty-state controls must not sit below a gesture-recognizing canvas"
            )
            ancestor = view.superview
        }
    }

    func testFilmstripMenuValidationReflectsSettingState() {
        let defaults = UserDefaults(suiteName: "ImageViewAppTests.Filmstrip.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        let controller = MainWindowController(window: nil, settings: settings)
        let item = NSMenuItem(title: "Show Filmstrip", action: #selector(MainWindowController.toggleFilmstrip(_:)), keyEquivalent: "")

        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertEqual(item.state, .off)

        settings.showsFilmstrip = true
        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertEqual(item.state, .on)
    }

    /// 胶卷条打开就一直在。指针停在哪、图片放大到多少，都不该让它自己消失。
    func testFilmstripStaysVisibleRegardlessOfPointerOrZoom() {
        XCTAssertTrue(MainWindowController.shouldDisplayFilmstripOverlay(
            isEnabled: true,
            hasLoadedImage: true
        ))
        XCTAssertFalse(MainWindowController.shouldDisplayFilmstripOverlay(
            isEnabled: false,
            hasLoadedImage: true
        ))
        XCTAssertFalse(MainWindowController.shouldDisplayFilmstripOverlay(
            isEnabled: true,
            hasLoadedImage: false
        ))
        // 裁切时它会压住选区，网格模式没有「当前这一张」，这两种情况才让路。
        XCTAssertFalse(MainWindowController.shouldDisplayFilmstripOverlay(
            isEnabled: true,
            hasLoadedImage: true,
            isCropping: true
        ))
        XCTAssertFalse(MainWindowController.shouldDisplayFilmstripOverlay(
            isEnabled: true,
            hasLoadedImage: true,
            isFolderBrowserMode: true
        ))
    }

    /// 浮动的信息栏点到别处就收起来，点在它自己身上或那颗开关上不收。
    func testFloatingInspectorDismissesOnlyOnClicksElsewhere() {
        XCTAssertTrue(MainWindowController.shouldDismissFloatingInspector(
            hitViewIsInsideInspector: false,
            hitViewIsTheInspectorToggle: false
        ))
        XCTAssertFalse(MainWindowController.shouldDismissFloatingInspector(
            hitViewIsInsideInspector: true,
            hitViewIsTheInspectorToggle: false
        ))
        // 开关自己要放过去，否则这里先关掉、开关再打开，按下去像没反应。
        XCTAssertFalse(MainWindowController.shouldDismissFloatingInspector(
            hitViewIsInsideInspector: false,
            hitViewIsTheInspectorToggle: true
        ))
    }

    func testPageControlsRequireMultipleImagesAndNoCropSession() {
        XCTAssertFalse(MainWindowController.shouldDisplayPageControls(itemCount: 0, isCropping: false))
        XCTAssertFalse(MainWindowController.shouldDisplayPageControls(itemCount: 1, isCropping: false))
        XCTAssertTrue(MainWindowController.shouldDisplayPageControls(itemCount: 2, isCropping: false))
        XCTAssertFalse(MainWindowController.shouldDisplayPageControls(itemCount: 2, isCropping: true))
    }

    func testPageControlAvailabilityTracksSequenceBoundaries() {
        let first = ImageItem(url: URL(fileURLWithPath: "/tmp/first.png"), format: .png)
        let second = ImageItem(url: URL(fileURLWithPath: "/tmp/second.png"), format: .png)
        let firstState = NavigationState(items: [first, second], currentURL: first.url)
        let secondState = NavigationState(items: [first, second], currentURL: second.url)

        XCTAssertEqual(
            MainWindowController.pageControlAvailability(navigationState: firstState),
            .init(previous: false, next: true)
        )
        XCTAssertEqual(
            MainWindowController.pageControlAvailability(navigationState: secondState),
            .init(previous: true, next: false)
        )
        XCTAssertEqual(
            MainWindowController.pageControlAvailability(
                navigationState: firstState,
                readingDirection: .rightToLeft
            ),
            .init(previous: true, next: false)
        )
    }

    func testNavigationMenuValidationTracksSequenceBoundaries() async throws {
        let fixture = try makeFolderNavigationFixture(itemNames: ["first.png", "second.png"])
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        await fixture.controller.openFolderForTesting(fixture.folder, scannerItems: fixture.items)
        fixture.controller.openFirstFolderBrowserItemForTesting()
        for _ in 0..<100 where fixture.controller.viewerNavigationURLsForTesting.count != 2 {
            await Task.yield()
        }
        let previous = NSMenuItem(
            title: "Previous",
            action: #selector(MainWindowController.showPreviousImage(_:)),
            keyEquivalent: ""
        )
        let next = NSMenuItem(
            title: "Next",
            action: #selector(MainWindowController.showNextImage(_:)),
            keyEquivalent: ""
        )

        XCTAssertFalse(fixture.controller.validateMenuItem(previous))
        XCTAssertTrue(fixture.controller.validateMenuItem(next))

        fixture.controller.showNextImage(nil)
        for _ in 0..<100 where fixture.controller.viewerNavigationURLForTesting != fixture.items[1].url {
            await Task.yield()
        }

        XCTAssertTrue(fixture.controller.validateMenuItem(previous))
        XCTAssertFalse(fixture.controller.validateMenuItem(next))
    }

    func testPageControlsStayVisibleWhileHovered() {
        XCTAssertFalse(MainWindowController.shouldAutoHidePageControls(pointerIsOverControls: true))
        XCTAssertTrue(MainWindowController.shouldAutoHidePageControls(pointerIsOverControls: false))
    }

    func testFilmstripAndPageControlsShareDisappearanceTiming() {
        XCTAssertEqual(MainWindowController.overlayAutoHideDelay, 1.8)
        XCTAssertEqual(MainWindowController.overlayFadeOutDuration, 0.18)
    }

    func testFullScreenChromeStartsHiddenAndReappearsForInteraction() {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))

        controller.windowDidEnterFullScreen(Notification(name: NSWindow.didEnterFullScreenNotification))
        XCTAssertFalse(controller.isFullScreenChromeVisibleForTesting)

        controller.revealFullScreenChromeForTesting()
        XCTAssertTrue(controller.isFullScreenChromeVisibleForTesting)

        controller.windowDidExitFullScreen(Notification(name: NSWindow.didExitFullScreenNotification))
        XCTAssertTrue(controller.isFullScreenChromeVisibleForTesting)
    }

    func testInspectorMenuValidationReflectsSettingState() {
        let defaults = UserDefaults(suiteName: "ImageViewAppTests.Inspector.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        let controller = MainWindowController(window: nil, settings: settings)
        let item = NSMenuItem(title: "Show Info", action: #selector(MainWindowController.toggleInspector(_:)), keyEquivalent: "")

        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertEqual(item.state, .off)

        settings.showsInspector = true
        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertEqual(item.state, .on)
    }

    func testOpeningFolderShowsBrowserAndHidesImageOnlyStatus() {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.png"), format: .png)
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))

        controller.openFolderForTesting(folder, items: [item])

        XCTAssertTrue(controller.isFolderBrowserVisibleForTesting)
        XCTAssertFalse(controller.isCanvasVisibleForTesting)
        XCTAssertTrue(controller.isImageStatusContentHiddenForTesting)
        XCTAssertFalse(controller.isInspectorVisibleForTesting)
        XCTAssertFalse(controller.isFilmstripVisibleForTesting)
        XCTAssertFalse(controller.isPageControlsVisibleForTesting)
        XCTAssertEqual(controller.folderBrowserItemCountForTesting, 1)
    }

    func testOpeningImageAfterFolderModeReturnsToViewerMode() {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        controller.openFolderForTesting(folder, items: [])

        controller.open(url: folder.appendingPathComponent("one.png"))

        XCTAssertFalse(controller.isFolderBrowserVisibleForTesting)
        XCTAssertTrue(controller.isCanvasVisibleForTesting)
    }

    func testBrowserOpenItemCallbackCallsOpenURLAndHidesFolderBrowser() {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.png"), format: .png)
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        controller.openFolderForTesting(folder, items: [item])

        controller.openFirstFolderBrowserItemForTesting()

        XCTAssertTrue(controller.hasAssignedOpenRequest)
        XCTAssertFalse(controller.isFolderBrowserVisibleForTesting)
        XCTAssertTrue(controller.isCanvasVisibleForTesting)
    }

    func testFolderBrowserTrashCallbackUsesConfirmationAndKeepsFolderBrowserVisible() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.png"), format: .png)
        let movedToTrash = MainWindowLockedValue<[URL]>([])
        let folderViewModel = FolderBrowserViewModel(
            scanFolder: { _ in [item] },
            moveToTrash: { urls in
                movedToTrash.set(urls)
                return BatchOperationResult(succeeded: urls)
            }
        )
        let controller = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: folderViewModel
        )
        controller.batchActionDialogProviderForTesting = .init(
            confirmTrash: { count in
                XCTAssertEqual(count, 1)
                return true
            }
        )
        await controller.openFolderForTesting(folder, scannerItems: [item])
        controller.selectFolderBrowserItemsForTesting([item.id])

        controller.triggerFolderBrowserTrashForTesting()
        for _ in 0..<100 where controller.folderBrowserItemCountForTesting != 0 {
            await Task.yield()
        }

        XCTAssertEqual(movedToTrash.value, [item.url])
        XCTAssertTrue(controller.isFolderBrowserVisibleForTesting)
        XCTAssertFalse(controller.isCanvasVisibleForTesting)
        XCTAssertEqual(controller.folderBrowserItemCountForTesting, 0)
    }

    func testFolderBrowserMoveCallbackUsesDirectoryPickerSkipPolicyAndStaysInFolderMode() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let destination = URL(fileURLWithPath: "/tmp/archive", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.png"), format: .png)
        let planned = MainWindowLockedValue<(urls: [URL], destination: URL, policy: MoveConflictPolicy)?>(nil)
        let executed = MainWindowLockedValue<[URL]?>(nil)
        let folderViewModel = FolderBrowserViewModel(
            scanFolder: { _ in [item] },
            planBatchMove: { urls, destinationFolder, policy in
                planned.set((urls, destinationFolder, policy))
                return BatchMovePlan(
                    proposals: urls.map {
                        BatchMoveProposal(
                            source: $0,
                            destination: destinationFolder.appendingPathComponent($0.lastPathComponent)
                        )
                    },
                    failures: []
                )
            },
            executeMovePlan: { plan in
                let urls = plan.proposals.map(\.source)
                executed.set(urls)
                return BatchOperationResult(succeeded: urls)
            }
        )
        let controller = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: folderViewModel
        )
        controller.batchActionDialogProviderForTesting = .init(
            chooseDestinationFolder: { destination }
        )
        await controller.openFolderForTesting(folder, scannerItems: [item])
        controller.selectFolderBrowserItemsForTesting([item.id])

        controller.triggerFolderBrowserMoveForTesting()
        for _ in 0..<100 where executed.value == nil {
            await Task.yield()
        }

        XCTAssertEqual(planned.value?.urls, [item.url])
        XCTAssertEqual(planned.value?.destination, destination)
        XCTAssertEqual(planned.value?.policy, .skip)
        XCTAssertEqual(executed.value, [item.url])
        XCTAssertTrue(controller.isFolderBrowserVisibleForTesting)
    }

    func testMoveConflictsRequireSkipKeepBothOrCancelBeforeExecution() async throws {
        for choice in [
            MainWindowController.MoveConflictChoice.cancel,
            .skipConflicts,
            .keepBoth
        ] {
            let plannedPolicies = MainWindowLockedValue<[MoveConflictPolicy]>([])
            let executedPlans = MainWindowLockedValue<[BatchMovePlan]>([])
            let fixture = try makeFolderNavigationFixture(
                itemNames: ["a.png", "b.png"],
                planBatchMove: { urls, destination, policy in
                    plannedPolicies.update { $0.append(policy) }
                    switch policy {
                    case .skip:
                        return BatchMovePlan(
                            proposals: [],
                            failures: urls.map { BatchFileFailure(url: $0, reason: .destinationExists) }
                        )
                    case .keepBoth:
                        return BatchMovePlan(
                            proposals: urls.map {
                                BatchMoveProposal(
                                    source: $0,
                                    destination: destination.appendingPathComponent("copy-\($0.lastPathComponent)")
                                )
                            },
                            failures: []
                        )
                    }
                },
                executeMovePlan: { plan in
                    executedPlans.update { $0.append(plan) }
                    return BatchOperationResult(succeeded: plan.proposals.map(\.source))
                }
            )
            defer { try? FileManager.default.removeItem(at: fixture.folder) }
            let destination = fixture.folder.appendingPathComponent("destination", isDirectory: true)
            fixture.controller.batchActionDialogProviderForTesting = .init(
                chooseDestinationFolder: { destination },
                chooseMoveConflict: { names in
                    XCTAssertEqual(names, ["a.png", "b.png"])
                    return choice
                }
            )
            await fixture.controller.openFolderForTesting(fixture.folder, scannerItems: fixture.items)
            fixture.controller.selectFolderBrowserItemsForTesting(fixture.items.map(\.id))

            fixture.controller.triggerFolderBrowserMoveForTesting()
            for _ in 0..<100 where fixture.controller.folderBrowserIsOperatingForTesting {
                await Task.yield()
            }

            switch choice {
            case .cancel:
                XCTAssertEqual(plannedPolicies.value, [.skip])
                XCTAssertTrue(executedPlans.value.isEmpty)
                XCTAssertEqual(fixture.controller.folderBrowserItemCountForTesting, 2)
            case .skipConflicts:
                XCTAssertEqual(plannedPolicies.value, [.skip])
                XCTAssertEqual(executedPlans.value.count, 1)
                XCTAssertTrue(executedPlans.value[0].proposals.isEmpty)
                XCTAssertEqual(fixture.controller.folderBrowserItemCountForTesting, 2)
            case .keepBoth:
                XCTAssertEqual(plannedPolicies.value, [.skip, .keepBoth])
                XCTAssertEqual(executedPlans.value.count, 1)
                XCTAssertEqual(executedPlans.value[0].proposals.map(\.source), fixture.items.map(\.url))
                XCTAssertEqual(fixture.controller.folderBrowserItemCountForTesting, 0)
            }
        }
    }

    func testFolderBrowserRenameExecutesExactValidatedPlanAndStaysInFolderMode() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.png"), format: .png)
        let renamedURL = folder.appendingPathComponent("Batch 05.png")
        let receivedParameters = MainWindowLockedValue<BatchRenameSheetController.RenameParameters?>(nil)
        let plannedCount = MainWindowLockedValue(0)
        let executedPlan = MainWindowLockedValue<BatchRenamePlan?>(nil)
        let folderViewModel = FolderBrowserViewModel(
            scanFolder: { _ in [item] },
            planBatchRename: { urls, baseName, startNumber, padding in
                plannedCount.update { $0 += 1 }
                receivedParameters.set(.init(baseName: baseName, startNumber: startNumber, padding: padding))
                return BatchRenamePlan(
                    proposals: [RenameProposal(source: urls[0], destination: renamedURL)],
                    failures: []
                )
            },
            executeRenamePlan: { plan in
                executedPlan.set(plan)
                return BatchOperationResult(succeeded: [item.url])
            }
        )
        let controller = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: folderViewModel
        )
        controller.batchActionDialogProviderForTesting = .init(
            requestRenameParameters: { items, planRename, confirm in
                XCTAssertEqual(items, [item])
                let parameters = BatchRenameSheetController.RenameParameters(
                    baseName: "Batch",
                    startNumber: 5,
                    padding: 2
                )
                let plan = planRename(items.map(\.url), parameters.baseName, parameters.startNumber, parameters.padding)
                confirm(parameters, plan)
            }
        )
        await controller.openFolderForTesting(folder, scannerItems: [item])
        controller.selectFolderBrowserItemsForTesting([item.id])

        controller.triggerFolderBrowserRenameForTesting()
        for _ in 0..<100 where executedPlan.value == nil {
            await Task.yield()
        }

        XCTAssertEqual(receivedParameters.value, .init(baseName: "Batch", startNumber: 5, padding: 2))
        XCTAssertEqual(plannedCount.value, 1)
        XCTAssertEqual(
            executedPlan.value,
            BatchRenamePlan(
                proposals: [RenameProposal(source: item.url, destination: renamedURL)],
                failures: []
            )
        )
        XCTAssertTrue(controller.isFolderBrowserVisibleForTesting)
        XCTAssertEqual(controller.folderBrowserItemCountForTesting, 1)
    }

    func testFolderBrowserBatchActionsReturnWhenSelectionIsEmpty() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let operationCount = MainWindowLockedValue(0)
        let folderViewModel = FolderBrowserViewModel(
            scanFolder: { _ in [] },
            moveToTrash: { _ in
                operationCount.update { $0 += 1 }
                return BatchOperationResult()
            },
            moveToFolder: { _, _, _ in
                operationCount.update { $0 += 1 }
                return BatchOperationResult()
            },
            planBatchRename: { _, _, _, _ in
                operationCount.update { $0 += 1 }
                return BatchRenamePlan(proposals: [], failures: [])
            }
        )
        let controller = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: folderViewModel
        )
        controller.batchActionDialogProviderForTesting = .init(
            confirmTrash: { _ in
                operationCount.update { $0 += 1 }
                return true
            },
            chooseDestinationFolder: {
                operationCount.update { $0 += 1 }
                return folder
            },
            requestRenameParameters: { _, _, _ in operationCount.update { $0 += 1 } }
        )
        await controller.openFolderForTesting(folder, scannerItems: [])

        controller.triggerFolderBrowserTrashForTesting()
        controller.triggerFolderBrowserMoveForTesting()
        controller.triggerFolderBrowserRenameForTesting()

        XCTAssertEqual(operationCount.value, 0)
        XCTAssertTrue(controller.isFolderBrowserVisibleForTesting)
    }

    func testFolderBrowserOperationStatusIsRenderedAfterFailure() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.png"), format: .png)
        let failure = BatchFileFailure(url: item.url, reason: .trashFailed("locked"))
        let folderViewModel = FolderBrowserViewModel(
            scanFolder: { _ in [item] },
            moveToTrash: { _ in BatchOperationResult(failures: [failure]) }
        )
        let controller = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: folderViewModel
        )
        controller.batchActionDialogProviderForTesting = .init(confirmTrash: { _ in true })
        await controller.openFolderForTesting(folder, scannerItems: [item])
        controller.selectFolderBrowserItemsForTesting([item.id])

        controller.triggerFolderBrowserTrashForTesting()
        let expectedStatus = "\(String(format: AppStrings.text("folderBrowser.operation.failed"), 1)) · " +
            "\(String(format: AppStrings.text("folderBrowser.status.failure.one"), 1)) · " +
            "one.png: \(String(format: AppStrings.text("folderBrowser.failure.trashFailed"), "locked"))"
        for _ in 0..<100 where controller.folderBrowserOperationStatusTextForTesting != expectedStatus {
            await Task.yield()
        }

        XCTAssertEqual(controller.folderBrowserOperationStatusTextForTesting, expectedStatus)
        XCTAssertTrue(controller.isFolderBrowserVisibleForTesting)
    }

    func testTitleBarGridButtonOpensCurrentImageFolderWithoutChangingWindowTitle() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let imageURL = root.appendingPathComponent("one.png")
        try writeTestPNG(to: imageURL)
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        controller.open(url: imageURL)
        for _ in 0..<100 where controller.window?.title == "ImageView" {
            try await Task.sleep(for: .milliseconds(10))
        }
        let title = controller.window?.title

        controller.performTitleBarBrowseCurrentFolderForTesting(items: [
            ImageItem(url: imageURL, format: .png)
        ])

        XCTAssertTrue(controller.isFolderBrowserVisibleForTesting)
        XCTAssertEqual(controller.window?.title, title)
    }

    func testGridButtonTogglesBackToLiveViewerWithoutRescanning() async throws {
        let fixture = try makeFolderNavigationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        await fixture.controller.openFolderForTesting(fixture.folder, scannerItems: [fixture.items[0]])
        fixture.controller.openFirstFolderBrowserItemForTesting()

        XCTAssertEqual(fixture.controller.titleBarGridButtonForTesting.toolTip, AppStrings.text("titleBar.showFolder"))
        XCTAssertEqual(
            fixture.controller.titleBarGridButtonForTesting.accessibilityLabel(),
            AppStrings.text("titleBar.showFolder")
        )
        XCTAssertEqual(
            fixture.controller.titleBarGridButtonForTesting.image?.accessibilityDescription,
            AppStrings.text("titleBar.showFolder")
        )

        fixture.controller.performTitleBarGridToggleForTesting()
        XCTAssertTrue(fixture.controller.isFolderBrowserVisibleForTesting)
        XCTAssertEqual(fixture.controller.titleBarGridButtonForTesting.toolTip, AppStrings.text("titleBar.showImage"))
        XCTAssertEqual(
            fixture.controller.titleBarGridButtonForTesting.accessibilityLabel(),
            AppStrings.text("titleBar.showImage")
        )
        XCTAssertEqual(
            fixture.controller.titleBarGridButtonForTesting.image?.accessibilityDescription,
            AppStrings.text("titleBar.showImage")
        )

        fixture.controller.performTitleBarGridToggleForTesting()
        XCTAssertTrue(fixture.controller.isCanvasVisibleForTesting)
        XCTAssertEqual(fixture.scanCount.value, 1)
    }

    func testGridToggleReturnsToDisplayedViewerAfterNavigatingAwayFromLastOpenedItem() async throws {
        let fixture = try makeFolderNavigationFixture(itemNames: ["a.png", "b.png"])
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        await fixture.controller.openFolderForTesting(fixture.folder, scannerItems: fixture.items)
        fixture.controller.openFolderBrowserItemForTesting(at: 1)
        for _ in 0..<100 where fixture.controller.viewerNavigationURLsForTesting.count != 2 {
            await Task.yield()
        }
        fixture.controller.showPreviousImage(nil)
        for _ in 0..<100 where fixture.controller.viewerNavigationURLForTesting != fixture.items[0].url {
            await Task.yield()
        }

        fixture.controller.performTitleBarGridToggleForTesting()
        fixture.controller.performTitleBarGridToggleForTesting()

        let expectedURL = fixture.items[0].url.standardizedFileURL
        XCTAssertEqual(fixture.controller.currentViewerRouteURLForTesting, expectedURL)
        XCTAssertEqual(fixture.controller.viewerNavigationURLForTesting, expectedURL)
        XCTAssertEqual(fixture.controller.displayedItemURLForTesting, expectedURL)
        XCTAssertTrue(fixture.controller.isCanvasVisibleForTesting)
    }

    func testGridToggleReturnsToDirectViewerWhileNewFolderScanIsStillLoading() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let oldFolder = root.appendingPathComponent("old", isDirectory: true)
        let newFolder = root.appendingPathComponent("new", isDirectory: true)
        try FileManager.default.createDirectory(at: oldFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let oldURL = oldFolder.appendingPathComponent("x1.png")
        let newURL = newFolder.appendingPathComponent("y1.png")
        try writeTestPNG(to: oldURL)
        try writeTestPNG(to: newURL)
        let oldItem = ImageItem(url: oldURL, format: .png)
        let newItem = ImageItem(url: newURL, format: .png)
        let scanner = MainWindowControlledFolderScanner(
            oldFolder: oldFolder,
            oldItems: [oldItem],
            newFolder: newFolder,
            newItems: [newItem]
        )
        let folderViewModel = FolderBrowserViewModel(scanFolder: { folder in
            await scanner.scan(folder)
        })
        let controller = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: folderViewModel
        )
        await controller.openFolderForTesting(oldFolder, scannerItems: [oldItem])
        controller.openFirstFolderBrowserItemForTesting()
        for _ in 0..<100 where controller.viewerNavigationURLForTesting != oldURL {
            await Task.yield()
        }
        controller.open(url: newURL)
        for _ in 0..<100 where controller.viewerNavigationURLForTesting != newURL {
            await Task.yield()
        }

        controller.performTitleBarGridToggleForTesting()
        await scanner.waitUntilNewScanStarts()
        controller.performTitleBarGridToggleForTesting()

        let expectedURL = newURL.standardizedFileURL
        XCTAssertEqual(controller.currentViewerRouteURLForTesting, expectedURL)
        XCTAssertEqual(controller.viewerNavigationURLForTesting, expectedURL)
        XCTAssertEqual(controller.displayedItemURLForTesting, expectedURL)
        XCTAssertTrue(controller.isCanvasVisibleForTesting)
        await scanner.finishNewScan()
    }

    func testOpeningGridItemEnablesBackAndBackForwardReuseLiveViews() async throws {
        let fixture = try makeFolderNavigationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        await fixture.controller.openFolderForTesting(fixture.folder, scannerItems: [fixture.items[0]])
        fixture.controller.openFirstFolderBrowserItemForTesting()

        XCTAssertTrue(fixture.controller.canGoBackForTesting)
        fixture.controller.goBackForTesting()
        XCTAssertTrue(fixture.controller.isFolderBrowserVisibleForTesting)
        XCTAssertTrue(fixture.controller.canGoForwardForTesting)
        fixture.controller.goForwardForTesting()
        XCTAssertTrue(fixture.controller.isCanvasVisibleForTesting)
        XCTAssertEqual(fixture.scanCount.value, 1)
    }

    func testTitleBarShowsFolderGridNavigationAndMoreButtons() async throws {
        let fixture = try makeFolderNavigationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let controller = fixture.controller

        // 网格、胶卷开关、编辑、连续浏览、更多。
        XCTAssertEqual(controller.titleBarControlsStackForTesting.arrangedSubviews.count, 5)
        XCTAssertEqual(
            controller.titleBarControlsStackForTesting.arrangedSubviews.first,
            controller.titleBarGridButtonForTesting
        )
        XCTAssertEqual(
            controller.titleBarControlsStackForTesting.arrangedSubviews[1],
            controller.titleBarFilmstripButtonForTesting
        )
        XCTAssertEqual(
            controller.titleBarControlsStackForTesting.arrangedSubviews[2],
            controller.titleBarEditButtonForTesting
        )
        XCTAssertEqual(
            controller.titleBarControlsStackForTesting.arrangedSubviews[3],
            controller.titleBarContinuousReadingButtonForTesting
        )
        XCTAssertNotNil(controller.titleBarGridButtonForTesting.image)
        XCTAssertFalse(controller.titleBarGridButtonForTesting.isEnabled)

        await controller.openFolderForTesting(fixture.folder, scannerItems: [fixture.items[0]])
        controller.openFirstFolderBrowserItemForTesting()

        XCTAssertTrue(controller.titleBarGridButtonForTesting.isEnabled)

        controller.titleBarGridButtonForTesting.performClick(nil)
        XCTAssertTrue(controller.isFolderBrowserVisibleForTesting)

        controller.titleBarGridButtonForTesting.performClick(nil)
        XCTAssertTrue(controller.isCanvasVisibleForTesting)
    }

    func testGridAvailabilityRefreshesAfterAsyncFolderLoadRejectsDisplayedViewer() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let oldFolder = root.appendingPathComponent("old", isDirectory: true)
        let newFolder = root.appendingPathComponent("new", isDirectory: true)
        try FileManager.default.createDirectory(at: oldFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let oldURL = oldFolder.appendingPathComponent("old.png")
        let newURL = newFolder.appendingPathComponent("new.png")
        try writeTestPNG(to: oldURL)
        try writeTestPNG(to: newURL)
        let newItem = ImageItem(url: newURL, format: .png)
        let folderViewModel = FolderBrowserViewModel(scanFolder: { _ in [newItem] })
        let controller = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: folderViewModel
        )
        controller.open(url: oldURL)
        for _ in 0..<100 where controller.displayedItemURLForTesting != oldURL.standardizedFileURL {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(controller.titleBarGridButtonForTesting.isEnabled)

        await controller.openFolderForTesting(newFolder, scannerItems: [newItem])

        XCTAssertTrue(controller.isFolderBrowserVisibleForTesting)
        XCTAssertFalse(controller.titleBarGridButtonForTesting.isEnabled)
    }

    func testTitleBarDoubleClickOnlyZoomsBarBackground() throws {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        let window = try XCTUnwrap(controller.window)
        window.contentView?.layoutSubtreeIfNeeded()
        let initialZoomState = window.isZoomed
        let recognizer = controller.titleBarDoubleClickRecognizerForTesting

        for protectedView in [
            controller.titleBarGridButtonForTesting,
            controller.titleBarControlsStackForTesting
        ] {
            XCTAssertFalse(controller.shouldRecognizeTitleBarDoubleClickForTesting(hitView: protectedView))
            let location = protectedView.convert(
                NSPoint(x: protectedView.bounds.midX, y: protectedView.bounds.midY),
                to: nil
            )
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: location,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 2,
                pressure: 1
            ))
            XCTAssertFalse(controller.gestureRecognizer(
                recognizer,
                shouldAttemptToRecognizeWith: event
            ))
            controller.performTitleBarDoubleClickForTesting(hitView: protectedView)
            XCTAssertEqual(window.isZoomed, initialZoomState)
        }

        XCTAssertTrue(controller.shouldRecognizeTitleBarDoubleClickForTesting(
            hitView: controller.titleBarViewForTesting
        ))
        controller.performTitleBarDoubleClickForTesting(hitView: controller.titleBarViewForTesting)
        XCTAssertNotEqual(window.isZoomed, initialZoomState)
    }

    /// 上一条测试是直接把视图递进判断函数的，绕开了坐标换算和真实命中。
    /// 这条从事件出发走完整条路径：双击标题栏空白处必须被识别。
    func testTitleBarDoubleClickOnBlankAreaIsRecognisedThroughRealHitTesting() throws {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        let window = try XCTUnwrap(controller.window)
        window.contentView?.layoutSubtreeIfNeeded()
        let titleBar = controller.titleBarViewForTesting
        XCTAssertGreaterThan(titleBar.bounds.width, 200, "标题栏要先有宽度，否则取点没有意义")

        // 那组按钮贴在左侧，标题文字居中，右侧这一块是空的。
        let blankPoint = NSPoint(x: titleBar.bounds.maxX - 24, y: titleBar.bounds.midY)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: titleBar.convert(blankPoint, to: nil),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 2,
            pressure: 1
        ))

        XCTAssertTrue(controller.gestureRecognizer(
            controller.titleBarDoubleClickRecognizerForTesting,
            shouldAttemptToRecognizeWith: event
        ))
    }

    /// 双击标题栏的行为跟随系统偏好，和其他应用一致。
    func testTitleBarDoubleClickFollowsTheSystemPreference() {
        XCTAssertEqual(MainWindowController.TitleBarDoubleClickAction.fromSystemPreference(nil), .zoom)
        XCTAssertEqual(MainWindowController.TitleBarDoubleClickAction.fromSystemPreference("Maximize"), .zoom)
        XCTAssertEqual(MainWindowController.TitleBarDoubleClickAction.fromSystemPreference("Minimize"), .minimize)
        XCTAssertEqual(MainWindowController.TitleBarDoubleClickAction.fromSystemPreference("None"), .none)
    }

    func testDirectImageOpenDoesNotInventBackHistory() throws {
        let fixture = try makeFolderNavigationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }

        fixture.controller.open(url: fixture.items[0].url)

        XCTAssertFalse(fixture.controller.canGoBackForTesting)
        XCTAssertFalse(fixture.controller.canGoForwardForTesting)
    }

    func testDirectViewerGridToggleReturnsToLiveViewerAfterEmptyScan() async throws {
        let fixture = try makeFolderNavigationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let folderViewModel = FolderBrowserViewModel(scanFolder: { _ in [] })
        let controller = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: folderViewModel
        )
        controller.open(url: fixture.items[0].url)
        for _ in 0..<100 where controller.displayedItemURLForTesting == nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        controller.performTitleBarGridToggleForTesting()
        for _ in 0..<100 where folderViewModel.presentation != .emptyFolder {
            await Task.yield()
        }
        controller.performTitleBarGridToggleForTesting()

        XCTAssertEqual(controller.currentViewerRouteURLForTesting, fixture.items[0].url.standardizedFileURL)
        XCTAssertTrue(controller.isCanvasVisibleForTesting)
    }

    func testDirectViewerGridToggleReturnsToLiveViewerAfterFailedScan() async throws {
        let fixture = try makeFolderNavigationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        enum ScanFailure: Error { case denied }
        let folderViewModel = FolderBrowserViewModel(scanFolder: { _ in throw ScanFailure.denied })
        let controller = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: folderViewModel
        )
        controller.open(url: fixture.items[0].url)
        for _ in 0..<100 where controller.displayedItemURLForTesting == nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        controller.performTitleBarGridToggleForTesting()
        for _ in 0..<100 {
            if case .loadFailed = folderViewModel.presentation { break }
            await Task.yield()
        }
        controller.performTitleBarGridToggleForTesting()

        XCTAssertEqual(controller.currentViewerRouteURLForTesting, fixture.items[0].url.standardizedFileURL)
        XCTAssertTrue(controller.isCanvasVisibleForTesting)
    }

    func testGridTrashHonorsUnsavedSaveDiscardAndCancel() async throws {
        try await assertGridDestructiveActionHonorsUnsavedChoices(action: .trash)
    }

    func testGridMoveHonorsUnsavedSaveDiscardAndCancel() async throws {
        try await assertGridDestructiveActionHonorsUnsavedChoices(action: .move)
    }

    func testGridRenameHonorsUnsavedSaveDiscardAndCancel() async throws {
        try await assertGridDestructiveActionHonorsUnsavedChoices(action: .rename)
    }

    func testGridBackForwardPreservesScrollOrigin() async throws {
        let fixture = try makeFolderNavigationFixture(itemNames: (0..<20).map { "\($0).png" })
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        await fixture.controller.openFolderForTesting(fixture.folder, scannerItems: fixture.items)
        fixture.controller.setFolderBrowserScrollOriginForTesting(NSPoint(x: 0, y: 123))
        let origin = fixture.controller.folderBrowserScrollOriginForTesting
        fixture.controller.openFirstFolderBrowserItemForTesting()

        fixture.controller.goBackForTesting()
        XCTAssertEqual(fixture.controller.folderBrowserScrollOriginForTesting, origin)
        fixture.controller.goForwardForTesting()
        fixture.controller.performTitleBarGridToggleForTesting()
        XCTAssertEqual(fixture.controller.folderBrowserScrollOriginForTesting, origin)
    }

    func testOpeningNewGridItemReplacesForwardRouteAndRecordsLastOpenedItem() async throws {
        let fixture = try makeFolderNavigationFixture(itemNames: ["one.png", "two.png"])
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        await fixture.controller.openFolderForTesting(fixture.folder, scannerItems: fixture.items)
        fixture.controller.openFirstFolderBrowserItemForTesting()
        fixture.controller.goBackForTesting()
        XCTAssertTrue(fixture.controller.canGoForwardForTesting)

        fixture.controller.openFolderBrowserItemForTesting(at: 1)

        XCTAssertFalse(fixture.controller.canGoForwardForTesting)
        XCTAssertEqual(fixture.controller.lastOpenedFolderItemIDForTesting, fixture.items[1].id)
    }

    func testCancellingUnsavedGridItemOpenPreservesRouteHistoryAndLastOpenedItem() async throws {
        let fixture = try makeFolderNavigationFixture(itemNames: ["one.png", "two.png"])
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        await fixture.controller.openFolderForTesting(fixture.folder, scannerItems: fixture.items)
        fixture.controller.openFirstFolderBrowserItemForTesting()
        for _ in 0..<100 where !fixture.controller.canEditCurrentImageForTesting {
            try await Task.sleep(for: .milliseconds(10))
        }
        fixture.controller.performEditForTesting(.rotateClockwise)
        XCTAssertTrue(fixture.controller.hasUnsavedEditsForTesting)
        fixture.controller.goBackForTesting()
        fixture.controller.setUnsavedChangesChoiceForTesting(.cancel)

        fixture.controller.openFolderBrowserItemForTesting(at: 1)

        XCTAssertTrue(fixture.controller.isFolderBrowserVisibleForTesting)
        XCTAssertTrue(fixture.controller.canGoForwardForTesting)
        XCTAssertEqual(fixture.controller.forwardViewerURLForTesting, fixture.items[0].url.standardizedFileURL)
        XCTAssertEqual(fixture.controller.lastOpenedFolderItemIDForTesting, fixture.items[0].id)
    }

    func testDeletingForwardViewerTargetAfterBackDisablesForward() async throws {
        let fixture = try makeFolderNavigationFixture(
            itemNames: ["one.png", "two.png"],
            moveToTrash: { BatchOperationResult(succeeded: $0) }
        )
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        await fixture.controller.openFolderForTesting(fixture.folder, scannerItems: fixture.items)
        fixture.controller.openFirstFolderBrowserItemForTesting()
        fixture.controller.goBackForTesting()
        XCTAssertTrue(fixture.controller.canGoForwardForTesting)
        fixture.controller.batchActionDialogProviderForTesting = .init(confirmTrash: { _ in true })
        fixture.controller.selectFolderBrowserItemsForTesting([fixture.items[0].id])

        fixture.controller.triggerFolderBrowserTrashForTesting()
        for _ in 0..<100 where fixture.controller.folderBrowserItemCountForTesting != 1 {
            await Task.yield()
        }

        XCTAssertFalse(fixture.controller.canGoForwardForTesting)
        XCTAssertNil(fixture.controller.forwardViewerURLForTesting)
        XCTAssertNil(fixture.controller.lastOpenedFolderItemIDForTesting)
    }

    func testRenamingForwardViewerTargetAfterBackMigratesRouteAndViewerNavigation() async throws {
        let renamedURLBox = MainWindowLockedValue<URL?>(nil)
        let fixture = try makeFolderNavigationFixture(
            moveToTrash: nil,
            planBatchRename: { urls, _, _, _ in
                let destination = urls[0].deletingLastPathComponent().appendingPathComponent("renamed.png")
                renamedURLBox.set(destination)
                return BatchRenamePlan(
                    proposals: [RenameProposal(source: urls[0], destination: destination)],
                    failures: []
                )
            },
            executeRenamePlan: { plan in
                BatchOperationResult(succeeded: plan.proposals.map(\.source))
            }
        )
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        await fixture.controller.openFolderForTesting(fixture.folder, scannerItems: fixture.items)
        fixture.controller.openFirstFolderBrowserItemForTesting()
        for _ in 0..<100 where !fixture.controller.canEditCurrentImageForTesting {
            try await Task.sleep(for: .milliseconds(10))
        }
        fixture.controller.goBackForTesting()
        fixture.controller.selectFolderBrowserItemsForTesting([fixture.items[0].id])
        fixture.controller.batchActionDialogProviderForTesting = .init(
            requestRenameParameters: { items, planRename, confirm in
                let parameters = BatchRenameSheetController.RenameParameters(
                    baseName: "renamed",
                    startNumber: 1,
                    padding: 2
                )
                confirm(parameters, planRename(items.map(\.url), parameters.baseName, parameters.startNumber, parameters.padding))
            }
        )

        fixture.controller.triggerFolderBrowserRenameForTesting()
        for _ in 0..<100 where fixture.controller.lastOpenedFolderItemIDForTesting == fixture.items[0].id {
            await Task.yield()
        }
        let renamedURL = try XCTUnwrap(renamedURLBox.value).standardizedFileURL

        XCTAssertEqual(fixture.controller.lastOpenedFolderItemIDForTesting, renamedURL)
        XCTAssertEqual(fixture.controller.forwardViewerURLForTesting, renamedURL)
        XCTAssertEqual(fixture.controller.viewerNavigationURLForTesting, renamedURL)
        fixture.controller.goForwardForTesting()
        XCTAssertEqual(fixture.controller.currentViewerRouteURLForTesting, renamedURL)
        XCTAssertTrue(fixture.controller.isCanvasVisibleForTesting)
    }

    func testStaleRenameSuccessMigratesForwardRouteAssociatedViewerAndViewerNavigation() async throws {
        let folderA = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folderB = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folderA)
            try? FileManager.default.removeItem(at: folderB)
        }
        let oldURL = folderA.appendingPathComponent("old.png")
        let renamedURL = folderA.appendingPathComponent("renamed.png")
        let itemA = ImageItem(url: oldURL, format: .png)
        let itemB = ImageItem(url: folderB.appendingPathComponent("b.png"), format: .png)
        try writeTestPNG(to: oldURL)
        try writeTestPNG(to: itemB.url)
        let gate = MainWindowBlockingBatchOperation()
        let plan = BatchRenamePlan(
            proposals: [RenameProposal(source: oldURL, destination: renamedURL)],
            failures: []
        )
        let viewModel = FolderBrowserViewModel(
            scanFolder: { folder in folder == folderA ? [itemA] : [itemB] },
            planBatchRename: { _, _, _, _ in plan },
            executeRenamePlan: { _ in gate.run(result: BatchOperationResult(succeeded: [oldURL])) }
        )
        let controller = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: viewModel
        )
        controller.batchActionDialogProviderForTesting = .init(
            requestRenameParameters: { items, planRename, confirm in
                let parameters = BatchRenameSheetController.RenameParameters(
                    baseName: "renamed",
                    startNumber: 1,
                    padding: 2
                )
                confirm(parameters, planRename(items.map(\.url), parameters.baseName, parameters.startNumber, parameters.padding))
            }
        )
        await controller.openFolderForTesting(folderA, scannerItems: [itemA])
        controller.openFirstFolderBrowserItemForTesting()
        for _ in 0..<100 where controller.viewerNavigationURLForTesting != oldURL.standardizedFileURL {
            await Task.yield()
        }
        controller.goBackForTesting()
        controller.selectFolderBrowserItemsForTesting([itemA.id])

        controller.triggerFolderBrowserRenameForTesting()
        await gate.waitUntilStarted()
        await viewModel.openFolder(folderB)
        gate.finish()
        for _ in 0..<100 where controller.forwardViewerURLForTesting != renamedURL.standardizedFileURL {
            await Task.yield()
        }

        XCTAssertEqual(viewModel.session?.folderURL, folderB)
        XCTAssertEqual(viewModel.visibleItems, [itemB])
        XCTAssertEqual(controller.forwardViewerURLForTesting, renamedURL.standardizedFileURL)
        XCTAssertEqual(controller.associatedViewerURLForTesting, renamedURL.standardizedFileURL)
        XCTAssertEqual(controller.viewerNavigationURLForTesting, renamedURL.standardizedFileURL)
        XCTAssertNil(controller.folderBrowserOperationStatusTextForTesting)
    }

    func testDeletingNavigatedForwardTargetAfterBackClearsForwardAndViewerNavigation() async throws {
        let fixture = try makeFolderNavigationFixture(
            itemNames: ["a.png", "b.png"],
            moveToTrash: { BatchOperationResult(succeeded: $0) }
        )
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        await fixture.controller.openFolderForTesting(fixture.folder, scannerItems: fixture.items)
        fixture.controller.openFirstFolderBrowserItemForTesting()
        for _ in 0..<100 where !fixture.controller.canEditCurrentImageForTesting {
            try await Task.sleep(for: .milliseconds(10))
        }
        for _ in 0..<100 where fixture.controller.viewerNavigationURLsForTesting.count != 2 {
            await Task.yield()
        }
        fixture.controller.showNextImage(nil)
        for _ in 0..<100 where fixture.controller.viewerNavigationURLForTesting != fixture.items[1].url {
            await Task.yield()
        }
        fixture.controller.goBackForTesting()
        fixture.controller.batchActionDialogProviderForTesting = .init(confirmTrash: { _ in true })
        fixture.controller.selectFolderBrowserItemsForTesting([fixture.items[1].id])

        fixture.controller.triggerFolderBrowserTrashForTesting()
        for _ in 0..<100 where fixture.controller.folderBrowserItemCountForTesting != 1 {
            await Task.yield()
        }

        XCTAssertFalse(fixture.controller.canGoForwardForTesting)
        XCTAssertNil(fixture.controller.forwardViewerURLForTesting)
        XCTAssertEqual(fixture.controller.viewerNavigationURLsForTesting, [fixture.items[0].url.standardizedFileURL])
    }

    func testDeletingCurrentViewerDuringInFlightGridOperationKeepsReplacementViewerRoute() async throws {
        let gate = MainWindowBlockingBatchOperation()
        let fixture = try makeFolderNavigationFixture(
            itemNames: ["a.png", "b.png"],
            moveToTrash: { urls in gate.run(succeeded: urls) }
        )
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        await fixture.controller.openFolderForTesting(fixture.folder, scannerItems: fixture.items)
        fixture.controller.openFirstFolderBrowserItemForTesting()
        for _ in 0..<100 where fixture.controller.viewerNavigationURLsForTesting.count != 2 {
            await Task.yield()
        }
        fixture.controller.showNextImage(nil)
        for _ in 0..<100 where fixture.controller.viewerNavigationURLForTesting != fixture.items[1].url {
            await Task.yield()
        }
        fixture.controller.goBackForTesting()
        fixture.controller.batchActionDialogProviderForTesting = .init(confirmTrash: { _ in true })
        fixture.controller.selectFolderBrowserItemsForTesting([fixture.items[1].id])
        fixture.controller.triggerFolderBrowserTrashForTesting()
        await gate.waitUntilStarted()

        fixture.controller.goForwardForTesting()
        XCTAssertEqual(fixture.controller.currentViewerRouteURLForTesting, fixture.items[1].url.standardizedFileURL)
        gate.finish()
        for _ in 0..<100 where fixture.controller.viewerNavigationURLForTesting != fixture.items[0].url {
            await Task.yield()
        }

        XCTAssertEqual(fixture.controller.viewerNavigationURLForTesting, fixture.items[0].url.standardizedFileURL)
        XCTAssertEqual(fixture.controller.currentViewerRouteURLForTesting, fixture.items[0].url.standardizedFileURL)
        XCTAssertTrue(fixture.controller.isCanvasVisibleForTesting)
    }

    func testRenamingNavigatedForwardTargetAfterBackMigratesForwardAndAllViewerItems() async throws {
        let renamedURLBox = MainWindowLockedValue<URL?>(nil)
        let fixture = try makeFolderNavigationFixture(
            itemNames: ["a.png", "b.png"],
            planBatchRename: { urls, _, _, _ in
                let destination = urls[0].deletingLastPathComponent().appendingPathComponent("renamed-b.png")
                renamedURLBox.set(destination)
                return BatchRenamePlan(
                    proposals: [RenameProposal(source: urls[0], destination: destination)],
                    failures: []
                )
            },
            executeRenamePlan: { plan in
                BatchOperationResult(succeeded: plan.proposals.map(\.source))
            }
        )
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        await fixture.controller.openFolderForTesting(fixture.folder, scannerItems: fixture.items)
        fixture.controller.openFirstFolderBrowserItemForTesting()
        for _ in 0..<100 where !fixture.controller.canEditCurrentImageForTesting {
            try await Task.sleep(for: .milliseconds(10))
        }
        for _ in 0..<100 where fixture.controller.viewerNavigationURLsForTesting.count != 2 {
            await Task.yield()
        }
        fixture.controller.showNextImage(nil)
        for _ in 0..<100 where fixture.controller.viewerNavigationURLForTesting != fixture.items[1].url {
            await Task.yield()
        }
        fixture.controller.goBackForTesting()
        fixture.controller.selectFolderBrowserItemsForTesting([fixture.items[1].id])
        fixture.controller.batchActionDialogProviderForTesting = .init(
            requestRenameParameters: { items, planRename, confirm in
                let parameters = BatchRenameSheetController.RenameParameters(
                    baseName: "renamed-b",
                    startNumber: 1,
                    padding: 2
                )
                confirm(parameters, planRename(items.map(\.url), parameters.baseName, parameters.startNumber, parameters.padding))
            }
        )

        fixture.controller.triggerFolderBrowserRenameForTesting()
        for _ in 0..<100 where renamedURLBox.value == nil {
            await Task.yield()
        }
        let renamedURL = try XCTUnwrap(renamedURLBox.value).standardizedFileURL
        for _ in 0..<100 where fixture.controller.forwardViewerURLForTesting != renamedURL {
            await Task.yield()
        }

        XCTAssertEqual(fixture.controller.forwardViewerURLForTesting, renamedURL)
        XCTAssertEqual(
            Set(fixture.controller.viewerNavigationURLsForTesting),
            Set([fixture.items[0].url.standardizedFileURL, renamedURL])
        )
        XCTAssertFalse(fixture.controller.viewerNavigationURLsForTesting.contains(fixture.items[1].url.standardizedFileURL))
    }

    func testTitleBarGridButtonTooltipIsLocalized() {
        XCTAssertEqual(
            AppStrings.text("titleBar.showFolder", preferredLanguages: ["en"]),
            "Show Folder"
        )
        XCTAssertEqual(
            AppStrings.text("titleBar.showFolder", preferredLanguages: ["zh-Hans"]),
            "显示文件夹"
        )
    }

    func testFolderBrowserPresentationAndRecoveryCallbacksAreIntegrated() async throws {
        let folder = URL(fileURLWithPath: "/tmp/recovery", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.png"), format: .png)
        let attempts = MainWindowLockedValue(0)
        let viewModel = FolderBrowserViewModel(scanFolder: { _ in
            attempts.update { $0 += 1 }
            if attempts.value == 1 {
                throw NSError(domain: "MainWindowControllerTests", code: 1)
            }
            return [item]
        })
        let controller = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: viewModel
        )

        await controller.openFolderForTesting(folder, scannerItems: [])
        XCTAssertEqual(
            controller.folderBrowserPresentationTitleForTesting,
            AppStrings.text("folderBrowser.state.loadFailed.title")
        )
        controller.triggerPrimaryFolderBrowserRecoveryForTesting()
        for _ in 0..<100 where viewModel.presentation != .content {
            await Task.yield()
        }

        XCTAssertEqual(attempts.value, 2)
        XCTAssertEqual(viewModel.presentation, .content)
        XCTAssertEqual(controller.folderBrowserItemCountForTesting, 1)
    }

    func testFolderBrowserOperationRecoveryFailuresAreVisibleThroughControllerBinding() async {
        let viewModel = FolderBrowserViewModel(scanFolder: { _ in [] })
        let controller = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: viewModel
        )
        let expected = URL(fileURLWithPath: "/tmp/photos/original.png")
        let actual = URL(fileURLWithPath: "/tmp/photos/.batch-rename-stranded.tmp")
        viewModel.applyOperationResult(
            BatchOperationResult(
                failures: [BatchFileFailure(url: expected, reason: .renameFailed("locked"))],
                recoveryFailures: [BatchRecoveryFailure(
                    expectedURL: expected,
                    actualURL: actual,
                    reason: "rollback permission denied"
                )]
            ),
            removingSucceeded: false
        )
        await Task.yield()

        let status = controller.folderBrowserOperationStatusTextForTesting
        XCTAssertTrue(status?.contains("original.png → .batch-rename-stranded.tmp") == true)
        XCTAssertTrue(status?.contains("rollback permission denied") == true)
        XCTAssertTrue(status?.contains(AppStrings.text("folderBrowser.recovery.hiddenTemporaryHint")) == true)
        let ordinaryFailure = "original.png: " + String(
            format: AppStrings.text("folderBrowser.failure.renameFailed"),
            "locked"
        )
        XCTAssertTrue(status?.contains(ordinaryFailure) == true, "ordinary failure details must remain visible")
    }

    func testStaleRenameRecoveryShowsIndependentAlertWithoutPollutingReplacementFolderStatus() async throws {
        let folderA = URL(fileURLWithPath: "/tmp/recovery-a", isDirectory: true)
        let folderB = URL(fileURLWithPath: "/tmp/recovery-b", isDirectory: true)
        let itemA = ImageItem(url: folderA.appendingPathComponent("original.png"), format: .png)
        let itemB = ImageItem(url: folderB.appendingPathComponent("b.png"), format: .png)
        let recovery = BatchRecoveryFailure(
            expectedURL: itemA.url,
            actualURL: folderA.appendingPathComponent(".batch-rename-stranded.tmp"),
            reason: "rollback permission denied"
        )
        let failure = BatchFileFailure(url: itemA.url, reason: .renameFailed("locked"))
        let gate = MainWindowBlockingBatchOperation()
        let plan = BatchRenamePlan(
            proposals: [RenameProposal(source: itemA.url, destination: folderA.appendingPathComponent("new.png"))],
            failures: []
        )
        let viewModel = FolderBrowserViewModel(
            scanFolder: { folder in folder == folderA ? [itemA] : [itemB] },
            planBatchRename: { _, _, _, _ in plan },
            executeRenamePlan: { _ in
                gate.run(result: BatchOperationResult(failures: [failure], recoveryFailures: [recovery]))
            }
        )
        let controller = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: viewModel
        )
        let presentation = MainWindowLockedValue<MainWindowController.RecoveryAlertPresentation?>(nil)
        controller.recoveryAlertPresenterForTesting = { presentation.set($0) }
        controller.batchActionDialogProviderForTesting = .init(
            requestRenameParameters: { items, planRename, confirm in
                let parameters = BatchRenameSheetController.RenameParameters(
                    baseName: "new",
                    startNumber: 1,
                    padding: 2
                )
                confirm(parameters, planRename(items.map(\.url), parameters.baseName, parameters.startNumber, parameters.padding))
            }
        )
        await controller.openFolderForTesting(folderA, scannerItems: [itemA])
        controller.selectFolderBrowserItemsForTesting([itemA.id])

        controller.triggerFolderBrowserRenameForTesting()
        await gate.waitUntilStarted()
        await viewModel.openFolder(folderB)
        gate.finish()
        for _ in 0..<100 where presentation.value == nil {
            await Task.yield()
        }

        let alert = try XCTUnwrap(presentation.value)
        XCTAssertEqual(alert.folderURL, folderA)
        XCTAssertEqual(alert.title, AppStrings.text("folderBrowser.recovery.alert.title"))
        XCTAssertTrue(alert.message.contains(folderA.path))
        XCTAssertTrue(alert.details.contains("original.png → .batch-rename-stranded.tmp"))
        XCTAssertTrue(alert.details.contains("rollback permission denied"))
        XCTAssertTrue(alert.details.contains(AppStrings.text("folderBrowser.recovery.hiddenTemporaryHint")))
        XCTAssertEqual(viewModel.session?.folderURL, folderB)
        XCTAssertEqual(viewModel.visibleItems, [itemB])
        XCTAssertTrue(viewModel.operationFailures.isEmpty)
        XCTAssertTrue(viewModel.operationRecoveryFailures.isEmpty)
        XCTAssertNil(controller.folderBrowserOperationStatusTextForTesting)
    }

    func testFolderBrowserClearFiltersAndChooseAnotherFolderCallbacksAreIntegrated() async throws {
        let folder = URL(fileURLWithPath: "/tmp/filtered", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.png"), format: .png)
        let viewModel = FolderBrowserViewModel(scanFolder: { _ in [item] })
        let controller = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: viewModel
        )
        var browseRequests = 0
        controller.onBrowseFolderRequested = { browseRequests += 1 }

        await controller.openFolderForTesting(folder, scannerItems: [item])
        viewModel.searchText = "missing"
        viewModel.setAllowedFormats([.png])
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let searchField = try XCTUnwrap(findSearchField(in: contentView))
        let typeFilter = try XCTUnwrap(findTypeFilterPopUp(in: contentView))
        XCTAssertEqual(
            controller.folderBrowserPresentationTitleForTesting,
            AppStrings.text("folderBrowser.state.filteredEmpty.title")
        )
        controller.triggerPrimaryFolderBrowserRecoveryForTesting()
        XCTAssertEqual(viewModel.presentation, .content)
        XCTAssertEqual(viewModel.session?.filter.allowedFormats, Set(SupportedImageFormat.allCases))
        XCTAssertEqual(searchField.stringValue, "")
        XCTAssertEqual(typeFilter.selectedTag(), -1)

        let emptyViewModel = FolderBrowserViewModel(scanFolder: { _ in [] })
        let emptyController = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: emptyViewModel
        )
        emptyController.onBrowseFolderRequested = { browseRequests += 1 }
        await emptyController.openFolderForTesting(folder, scannerItems: [])
        XCTAssertEqual(
            emptyController.folderBrowserPresentationTitleForTesting,
            AppStrings.text("folderBrowser.state.emptyFolder.title")
        )
        emptyController.triggerPrimaryFolderBrowserRecoveryForTesting()

        XCTAssertEqual(browseRequests, 1)
    }

    func testOpeningNewFolderSessionResetsSearchAndTypeFilterControls() async throws {
        let firstFolder = URL(fileURLWithPath: "/tmp/first-filtered", isDirectory: true)
        let secondFolder = URL(fileURLWithPath: "/tmp/second-default", isDirectory: true)
        let firstItem = ImageItem(url: firstFolder.appendingPathComponent("first.png"), format: .png)
        let secondItem = ImageItem(url: secondFolder.appendingPathComponent("second.jpg"), format: .jpeg)
        let viewModel = FolderBrowserViewModel(scanFolder: { folder in
            folder == firstFolder ? [firstItem] : [secondItem]
        })
        let controller = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: viewModel
        )

        await controller.openFolderForTesting(firstFolder, scannerItems: [firstItem])
        viewModel.searchText = "first"
        viewModel.setAllowedFormats([.png])
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let searchField = try XCTUnwrap(findSearchField(in: contentView))
        let typeFilter = try XCTUnwrap(findTypeFilterPopUp(in: contentView))
        XCTAssertEqual(searchField.stringValue, "first")
        XCTAssertNotEqual(typeFilter.selectedTag(), -1)

        await controller.openFolderForTesting(secondFolder, scannerItems: [secondItem])

        XCTAssertEqual(searchField.stringValue, "")
        XCTAssertEqual(typeFilter.selectedTag(), -1)
    }

    func testRapidRepeatedRetryStartsOnlyOneOwnedRetryTask() async throws {
        let folder = URL(fileURLWithPath: "/tmp/retry-once", isDirectory: true)
        let scanner = MainWindowRetryScanner(failingFolder: folder)
        let viewModel = FolderBrowserViewModel(scanFolder: { folder in
            try await scanner.scan(folder)
        })
        let controller = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: viewModel
        )
        await controller.openFolderForTesting(folder, scannerItems: [])

        controller.requestFolderRetryForTesting()
        controller.requestFolderRetryForTesting()
        await scanner.waitForRetryToStart()

        let retrySnapshot = await scanner.counts()
        XCTAssertEqual(retrySnapshot.scans, 2, "initial load plus exactly one retry")
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: controller.window))
        await scanner.waitForRetryCancellation()
        let closedSnapshot = await scanner.counts()
        XCTAssertEqual(closedSnapshot.cancellations, 1)
    }

    func testOpeningAnotherFolderCancelsOwnedRetryTask() async throws {
        let failingFolder = URL(fileURLWithPath: "/tmp/retry-cancel", isDirectory: true)
        let replacementFolder = URL(fileURLWithPath: "/tmp/replacement", isDirectory: true)
        let scanner = MainWindowRetryScanner(failingFolder: failingFolder)
        let viewModel = FolderBrowserViewModel(scanFolder: { folder in
            try await scanner.scan(folder)
        })
        let controller = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: viewModel
        )
        await controller.openFolderForTesting(failingFolder, scannerItems: [])
        controller.triggerPrimaryFolderBrowserRecoveryForTesting()
        await scanner.waitForRetryToStart()

        controller.openFolder(url: replacementFolder)
        await scanner.waitForReplacementScan()
        await scanner.waitForRetryCancellation()

        let snapshot = await scanner.counts()
        XCTAssertEqual(snapshot.scans, 3)
        XCTAssertEqual(snapshot.cancellations, 1)
    }

    func testWindowCloseInvalidatesRetryWhenScannerIgnoresTaskCancellation() async {
        let folder = URL(fileURLWithPath: "/tmp/close-stale-retry", isDirectory: true)
        let lateItem = ImageItem(url: folder.appendingPathComponent("late.png"), format: .png)
        let scanner = MainWindowIgnoringCancellationRetryScanner(failingFolder: folder)
        let viewModel = FolderBrowserViewModel(scanFolder: { folder in
            try await scanner.scan(folder)
        })
        let controller = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: viewModel
        )
        await controller.openFolderForTesting(folder, scannerItems: [])
        controller.requestFolderRetryForTesting()
        await scanner.waitForRetryToStart()

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: controller.window))
        let closedSession = viewModel.session
        let closedPresentation = viewModel.presentation
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.loadErrorMessage)
        await scanner.finishRetry(with: .success([lateItem]))
        await scanner.waitForRetryToReturn()

        XCTAssertEqual(viewModel.session, closedSession)
        XCTAssertEqual(viewModel.presentation, closedPresentation)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.loadErrorMessage)
    }

    func testWindowCloseRemovesLocalKeyMonitor() {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        XCTAssertTrue(controller.hasKeyMonitorForTesting)

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: controller.window))

        XCTAssertFalse(controller.hasKeyMonitorForTesting)
    }

    func testControllerDeinitInvalidatesRetryWhenScannerIgnoresTaskCancellation() async {
        let folder = URL(fileURLWithPath: "/tmp/deinit-stale-retry", isDirectory: true)
        let lateItem = ImageItem(url: folder.appendingPathComponent("late.png"), format: .png)
        let scanner = MainWindowIgnoringCancellationRetryScanner(failingFolder: folder)
        let viewModel = FolderBrowserViewModel(scanFolder: { folder in
            try await scanner.scan(folder)
        })
        var controller: MainWindowController? = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: viewModel
        )
        await controller?.openFolderForTesting(folder, scannerItems: [])
        controller?.requestFolderRetryForTesting()
        await scanner.waitForRetryToStart()
        weak let weakController = controller

        controller = nil
        XCTAssertNil(weakController)
        for _ in 0..<100 where viewModel.isLoading {
            await Task.yield()
        }
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.loadErrorMessage)
        let deinitSession = viewModel.session
        let deinitPresentation = viewModel.presentation
        await scanner.finishRetry(with: .success([lateItem]))
        await scanner.waitForRetryToReturn()

        XCTAssertEqual(viewModel.session, deinitSession)
        XCTAssertEqual(viewModel.presentation, deinitPresentation)
    }

    func testSwitchingFoldersRejectsLateRetryPublishFromCancellationIgnoringScanner() async {
        let failingFolder = URL(fileURLWithPath: "/tmp/switch-stale-retry", isDirectory: true)
        let replacementFolder = URL(fileURLWithPath: "/tmp/switch-replacement", isDirectory: true)
        let lateItem = ImageItem(url: failingFolder.appendingPathComponent("late.png"), format: .png)
        let replacementItem = ImageItem(url: replacementFolder.appendingPathComponent("replacement.png"), format: .png)
        let scanner = MainWindowIgnoringCancellationRetryScanner(
            failingFolder: failingFolder,
            replacementFolder: replacementFolder,
            replacementItems: [replacementItem]
        )
        let viewModel = FolderBrowserViewModel(scanFolder: { folder in
            try await scanner.scan(folder)
        })
        let controller = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: viewModel
        )
        await controller.openFolderForTesting(failingFolder, scannerItems: [])
        controller.requestFolderRetryForTesting()
        await scanner.waitForRetryToStart()

        controller.openFolder(url: replacementFolder)
        await scanner.waitForReplacementScan()
        XCTAssertEqual(viewModel.session?.folderURL, replacementFolder)
        XCTAssertEqual(viewModel.presentation, .content)
        await scanner.finishRetry(with: .success([lateItem]))
        await scanner.waitForRetryToReturn()

        XCTAssertEqual(viewModel.session?.folderURL, replacementFolder)
        XCTAssertEqual(viewModel.visibleItems, [replacementItem])
        XCTAssertEqual(viewModel.presentation, .content)
        XCTAssertNil(viewModel.loadErrorMessage)
    }

    private func findSearchField(in view: NSView) -> NSSearchField? {
        if let searchField = view as? NSSearchField { return searchField }
        return view.subviews.lazy.compactMap { self.findSearchField(in: $0) }.first
    }

    private enum GridDestructiveAction {
        case trash
        case move
        case rename
    }

    private func assertGridDestructiveActionHonorsUnsavedChoices(
        action: GridDestructiveAction
    ) async throws {
        for choice in [
            MainWindowController.UnsavedChangesChoice.save,
            .discard,
            .cancel
        ] {
            let operationCount = MainWindowLockedValue(0)
            let renamePlan: FolderBrowserViewModel.PlanBatchRename = { urls, baseName, startNumber, _ in
                BatchRenamePlan(
                    proposals: urls.enumerated().map { index, source in
                        RenameProposal(
                            source: source,
                            destination: source.deletingLastPathComponent()
                                .appendingPathComponent("\(baseName) \(startNumber + index).png")
                        )
                    },
                    failures: []
                )
            }
            let fixture = try makeFolderNavigationFixture(
                moveToTrash: { urls in
                    operationCount.update { $0 += 1 }
                    return BatchOperationResult(succeeded: urls)
                },
                planBatchMove: { urls, destination, _ in
                    BatchMovePlan(
                        proposals: urls.map {
                            BatchMoveProposal(
                                source: $0,
                                destination: destination.appendingPathComponent($0.lastPathComponent)
                            )
                        },
                        failures: []
                    )
                },
                executeMovePlan: { plan in
                    operationCount.update { $0 += 1 }
                    return BatchOperationResult(succeeded: plan.proposals.map(\.source))
                },
                planBatchRename: renamePlan,
                executeRenamePlan: { plan in
                    operationCount.update { $0 += 1 }
                    return BatchOperationResult(succeeded: plan.proposals.map(\.source))
                }
            )
            defer { try? FileManager.default.removeItem(at: fixture.folder) }
            await fixture.controller.openFolderForTesting(fixture.folder, scannerItems: fixture.items)
            fixture.controller.openFirstFolderBrowserItemForTesting()
            for _ in 0..<100 where !fixture.controller.canEditCurrentImageForTesting {
                try await Task.sleep(for: .milliseconds(10))
            }
            fixture.controller.performEditForTesting(.rotateClockwise)
            fixture.controller.goBackForTesting()
            fixture.controller.selectFolderBrowserItemsForTesting([fixture.items[0].id])
            fixture.controller.setUnsavedChangesChoiceForTesting(choice)
            fixture.controller.batchActionDialogProviderForTesting = .init(
                confirmTrash: { _ in true },
                chooseDestinationFolder: { fixture.folder.appendingPathComponent("destination", isDirectory: true) },
                requestRenameParameters: { items, planRename, confirm in
                    let parameters = BatchRenameSheetController.RenameParameters(
                        baseName: "Renamed",
                        startNumber: 1,
                        padding: 0
                    )
                    confirm(parameters, planRename(items.map(\.url), parameters.baseName, parameters.startNumber, parameters.padding))
                }
            )

            switch action {
            case .trash:
                fixture.controller.triggerFolderBrowserTrashForTesting()
            case .move:
                fixture.controller.triggerFolderBrowserMoveForTesting()
            case .rename:
                fixture.controller.triggerFolderBrowserRenameForTesting()
            }
            for _ in 0..<100 where choice != .cancel && operationCount.value == 0 {
                await Task.yield()
            }
            if choice == .cancel {
                for _ in 0..<100 { await Task.yield() }
            }

            XCTAssertEqual(operationCount.value, choice == .cancel ? 0 : 1, "choice=\(choice)")
            XCTAssertEqual(fixture.controller.hasUnsavedEditsForTesting, choice == .cancel, "choice=\(choice)")
        }
    }

    private func findTypeFilterPopUp(in view: NSView) -> NSPopUpButton? {
        if let popUp = view as? NSPopUpButton,
           popUp.itemTitles.contains(AppStrings.text("folderBrowser.typeFilter.all")) {
            return popUp
        }
        return view.subviews.lazy.compactMap { self.findTypeFilterPopUp(in: $0) }.first
    }

    private func writeTestPNG(to url: URL) throws {
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
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

    private func makeFolderNavigationFixture(
        itemNames: [String] = ["one.png"],
        moveToTrash: FolderBrowserViewModel.MoveToTrash? = nil,
        moveToFolder: FolderBrowserViewModel.MoveToFolder? = nil,
        planBatchMove: FolderBrowserViewModel.PlanBatchMove? = nil,
        executeMovePlan: FolderBrowserViewModel.ExecuteMovePlan? = nil,
        planBatchRename: FolderBrowserViewModel.PlanBatchRename? = nil,
        executeRenamePlan: FolderBrowserViewModel.ExecuteRenamePlan? = nil
    ) throws -> (
        folder: URL,
        items: [ImageItem],
        scanCount: MainWindowLockedValue<Int>,
        controller: MainWindowController
    ) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let items = try itemNames.map { name -> ImageItem in
            let imageURL = folder.appendingPathComponent(name)
            try writeTestPNG(to: imageURL)
            return ImageItem(url: imageURL, format: .png)
        }
        let scanCount = MainWindowLockedValue(0)
        let viewModel = FolderBrowserViewModel(
            scanFolder: { _ in
                scanCount.update { $0 += 1 }
                return items
            },
            moveToTrash: moveToTrash,
            moveToFolder: moveToFolder,
            planBatchMove: planBatchMove,
            executeMovePlan: executeMovePlan,
            planBatchRename: planBatchRename,
            executeRenamePlan: executeRenamePlan
        )
        let controller = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: viewModel
        )
        return (folder, items, scanCount, controller)
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ImageViewAppTests.MainWindowController.\(UUID().uuidString)")!
    }
}

private final class MainWindowLockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        self.storedValue = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func set(_ value: Value) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }

    func update(_ update: (inout Value) -> Void) {
        lock.lock()
        update(&storedValue)
        lock.unlock()
    }
}

private actor MainWindowRetryScanner {
    let failingFolder: URL
    private(set) var scanCount = 0
    private(set) var cancellationCount = 0
    private var retryStarted = false
    private var retryStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var retryCancelled = false
    private var retryCancellationWaiters: [CheckedContinuation<Void, Never>] = []
    private var replacementScanned = false
    private var replacementWaiters: [CheckedContinuation<Void, Never>] = []

    init(failingFolder: URL) {
        self.failingFolder = failingFolder.standardizedFileURL
    }

    func scan(_ folder: URL) async throws -> [ImageItem] {
        scanCount += 1
        guard folder.standardizedFileURL == failingFolder else {
            replacementScanned = true
            let pending = replacementWaiters
            replacementWaiters.removeAll()
            pending.forEach { $0.resume() }
            return []
        }
        if scanCount == 1 {
            throw NSError(domain: "MainWindowRetryScanner", code: 1)
        }
        retryStarted = true
        let pending = retryStartWaiters
        retryStartWaiters.removeAll()
        pending.forEach { $0.resume() }
        do {
            try await Task.sleep(for: .milliseconds(500))
            return []
        } catch {
            cancellationCount += 1
            retryCancelled = true
            let pending = retryCancellationWaiters
            retryCancellationWaiters.removeAll()
            pending.forEach { $0.resume() }
            throw error
        }
    }

    func waitForRetryToStart() async {
        guard !retryStarted else { return }
        await withCheckedContinuation { retryStartWaiters.append($0) }
    }

    func waitForReplacementScan() async {
        guard !replacementScanned else { return }
        await withCheckedContinuation { replacementWaiters.append($0) }
    }

    func waitForRetryCancellation() async {
        guard !retryCancelled else { return }
        await withCheckedContinuation { retryCancellationWaiters.append($0) }
    }

    func counts() -> (scans: Int, cancellations: Int) {
        (scanCount, cancellationCount)
    }
}

private actor MainWindowIgnoringCancellationRetryScanner {
    private let failingFolder: URL
    private let replacementFolder: URL?
    private let replacementItems: [ImageItem]
    private var failingScanCount = 0
    private var retryContinuation: CheckedContinuation<Result<[ImageItem], Error>, Never>?
    private var retryStarted = false
    private var retryStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var retryReturned = false
    private var retryReturnWaiters: [CheckedContinuation<Void, Never>] = []
    private var replacementScanned = false
    private var replacementWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        failingFolder: URL,
        replacementFolder: URL? = nil,
        replacementItems: [ImageItem] = []
    ) {
        self.failingFolder = failingFolder.standardizedFileURL
        self.replacementFolder = replacementFolder?.standardizedFileURL
        self.replacementItems = replacementItems
    }

    func scan(_ folder: URL) async throws -> [ImageItem] {
        if folder.standardizedFileURL == replacementFolder {
            replacementScanned = true
            let pending = replacementWaiters
            replacementWaiters.removeAll()
            pending.forEach { $0.resume() }
            return replacementItems
        }
        guard folder.standardizedFileURL == failingFolder else { return [] }
        failingScanCount += 1
        if failingScanCount == 1 {
            throw NSError(domain: "MainWindowIgnoringCancellationRetryScanner", code: 1)
        }
        retryStarted = true
        let startPending = retryStartWaiters
        retryStartWaiters.removeAll()
        startPending.forEach { $0.resume() }
        let result = await withCheckedContinuation { retryContinuation = $0 }
        retryReturned = true
        let returnPending = retryReturnWaiters
        retryReturnWaiters.removeAll()
        returnPending.forEach { $0.resume() }
        return try result.get()
    }

    func waitForRetryToStart() async {
        guard !retryStarted else { return }
        await withCheckedContinuation { retryStartWaiters.append($0) }
    }

    func finishRetry(with result: Result<[ImageItem], Error>) {
        retryContinuation?.resume(returning: result)
        retryContinuation = nil
    }

    func waitForRetryToReturn() async {
        guard !retryReturned else { return }
        await withCheckedContinuation { retryReturnWaiters.append($0) }
    }

    func waitForReplacementScan() async {
        guard !replacementScanned else { return }
        await withCheckedContinuation { replacementWaiters.append($0) }
    }
}

private final class MainWindowBlockingBatchOperation: @unchecked Sendable {
    private let started = MainWindowAsyncStartFlag()
    private let finished = DispatchSemaphore(value: 0)

    func run(succeeded urls: [URL]) -> BatchOperationResult {
        Task { await started.markStarted() }
        finished.wait()
        return BatchOperationResult(succeeded: urls)
    }

    func run(result: BatchOperationResult) -> BatchOperationResult {
        Task { await started.markStarted() }
        finished.wait()
        return result
    }

    func waitUntilStarted() async {
        await started.wait()
    }

    func finish() {
        finished.signal()
    }
}

private actor MainWindowAsyncStartFlag {
    private var isStarted = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func markStarted() {
        isStarted = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }

    func wait() async {
        guard !isStarted else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private actor MainWindowControlledFolderScanner {
    private let oldFolder: URL
    private let oldItems: [ImageItem]
    private let newFolder: URL
    private let newItems: [ImageItem]
    private var newScanStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var newScanContinuation: CheckedContinuation<[ImageItem], Never>?

    init(oldFolder: URL, oldItems: [ImageItem], newFolder: URL, newItems: [ImageItem]) {
        self.oldFolder = oldFolder.standardizedFileURL
        self.oldItems = oldItems
        self.newFolder = newFolder.standardizedFileURL
        self.newItems = newItems
    }

    func scan(_ folder: URL) async -> [ImageItem] {
        if folder.standardizedFileURL == oldFolder {
            return oldItems
        }
        guard folder.standardizedFileURL == newFolder else { return [] }
        newScanStarted = true
        let pending = startWaiters
        startWaiters.removeAll()
        pending.forEach { $0.resume() }
        return await withCheckedContinuation { newScanContinuation = $0 }
    }

    func waitUntilNewScanStarts() async {
        guard !newScanStarted else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func finishNewScan() {
        newScanContinuation?.resume(returning: newItems)
        newScanContinuation = nil
    }
}
