import AppKit
import ImageViewCore
import XCTest
@testable import ImageViewApp

@MainActor
final class WindowPresentationTests: XCTestCase {
    // MARK: - 模式

    func testFolderBrowsingWinsOverEverythingElse() {
        let mode = ContentMode.resolve(ContentMode.Input(
            isBrowsingFolder: true,
            hasImage: true,
            loadPhase: .full,
            hasError: true,
            usesContinuousReading: true
        ))

        XCTAssertEqual(mode, .grid, "进了网格就没有「当前这一张」可谈")
    }

    func testModeFollowsImageAndContinuousReadingSwitch() {
        XCTAssertEqual(
            ContentMode.resolve(ContentMode.Input(hasImage: true, loadPhase: .full)),
            .single
        )
        XCTAssertEqual(
            ContentMode.resolve(ContentMode.Input(hasImage: true, loadPhase: .full, usesContinuousReading: true)),
            .continuous
        )
    }

    func testModeWithoutImageDistinguishesEmptyLoadingAndError() {
        XCTAssertEqual(ContentMode.resolve(ContentMode.Input()), .empty)
        XCTAssertEqual(
            ContentMode.resolve(ContentMode.Input(loadPhase: .loading)),
            .loading,
            "解码中什么也不显示，空状态要等到确实没有图可开"
        )
        XCTAssertEqual(
            ContentMode.resolve(ContentMode.Input(loadPhase: .loading, hasError: true)),
            .error
        )
    }

    /// 有图之后错误就退到一边。屏幕上有东西看，就不该再盖一层错误页。
    func testErrorGivesWayOnceAnImageIsOnScreen() {
        XCTAssertEqual(
            ContentMode.resolve(ContentMode.Input(hasImage: true, loadPhase: .full, hasError: true)),
            .single
        )
    }

    // MARK: - 界面状态

    private func gridInput(folder: URL = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)) -> WindowPresentation.Input {
        WindowPresentation.Input(
            mode: .grid,
            isEditing: true,
            inspectorEnabled: true,
            inspectorDocked: true,
            filmstripEnabled: true,
            canEditCurrentImage: true,
            canToggleGrid: true,
            itemCount: 12,
            viewerTitle: "DSC01501.jpg",
            folderURL: folder
        )
    }

    /// 网格模式：标题给目录名，图片那一套浮层和动作全部让开。
    func testGridModeShowsFolderNameAndNoImageChrome() {
        let presentation = WindowPresentation.resolve(gridInput())

        XCTAssertEqual(presentation.title, "photos")
        XCTAssertEqual(presentation.titleToolTip, "/tmp/photos")
        XCTAssertTrue(presentation.showsFolderBrowser)
        XCTAssertFalse(presentation.showsCanvas)
        XCTAssertFalse(presentation.showsInspector)
        XCTAssertFalse(presentation.reservesInspectorColumn)
        XCTAssertFalse(presentation.showsFilmstrip)
        XCTAssertFalse(presentation.showsImageStatus)
        XCTAssertFalse(presentation.allowsPageControls)
        XCTAssertFalse(presentation.allowsImageCommands)
        XCTAssertFalse(presentation.canToggleFilmstrip)
        XCTAssertFalse(presentation.canToggleContinuousReading)
    }

    /// 网格里即使残留着编辑状态，也一律按退出算。裁切框不会浮到缩略图上面。
    func testEditingNeverLeaksOutOfSingleImageMode() {
        XCTAssertFalse(WindowPresentation.resolve(gridInput()).isEditing)
        XCTAssertFalse(WindowPresentation.resolve(gridInput()).canEditImage)

        var continuous = gridInput()
        continuous.mode = .continuous
        XCTAssertFalse(WindowPresentation.resolve(continuous).isEditing)
        XCTAssertFalse(WindowPresentation.resolve(continuous).canEditImage)

        var single = gridInput()
        single.mode = .single
        XCTAssertTrue(WindowPresentation.resolve(single).isEditing)
        XCTAssertTrue(WindowPresentation.resolve(single).canEditImage)
    }

    func testSingleImageModeShowsTheViewerChrome() {
        let presentation = WindowPresentation.resolve(WindowPresentation.Input(
            mode: .single,
            inspectorEnabled: true,
            inspectorDocked: true,
            filmstripEnabled: true,
            canEditCurrentImage: true,
            itemCount: 3,
            viewerTitle: "one.png"
        ))

        XCTAssertEqual(presentation.title, "one.png")
        XCTAssertNil(presentation.titleToolTip)
        XCTAssertTrue(presentation.showsCanvas)
        XCTAssertTrue(presentation.showsInspector)
        XCTAssertTrue(presentation.reservesInspectorColumn)
        XCTAssertTrue(presentation.showsFilmstrip)
        XCTAssertTrue(presentation.showsImageStatus)
        XCTAssertTrue(presentation.showsZoomStatus)
        XCTAssertTrue(presentation.allowsPageControls)
        XCTAssertTrue(presentation.canEditImage)
    }

    /// 连续浏览把整个序列铺开滚，胶卷条和缩放读数都没有意义。
    func testContinuousReadingDropsFilmstripAndZoomStatus() {
        let presentation = WindowPresentation.resolve(WindowPresentation.Input(
            mode: .continuous,
            inspectorEnabled: true,
            filmstripEnabled: true,
            canEditCurrentImage: true,
            itemCount: 5,
            viewerTitle: "one.png"
        ))

        XCTAssertTrue(presentation.showsContinuousReading)
        XCTAssertFalse(presentation.showsCanvas)
        XCTAssertFalse(presentation.showsFilmstrip)
        XCTAssertFalse(presentation.showsZoomStatus)
        XCTAssertTrue(presentation.showsImageStatus)
        XCTAssertTrue(presentation.showsInspector, "信息栏和是不是连续浏览无关")
        XCTAssertFalse(presentation.canEditImage)
    }

    func testEmptyAndErrorModesKeepTheCanvasBehindThem() {
        let empty = WindowPresentation.resolve(WindowPresentation.Input(mode: .empty, viewerTitle: "ImageView"))
        XCTAssertTrue(empty.showsEmptyState)
        XCTAssertFalse(empty.showsErrorState)
        XCTAssertTrue(empty.showsCanvas)
        XCTAssertFalse(empty.showsImageStatus)

        let error = WindowPresentation.resolve(WindowPresentation.Input(mode: .error, viewerTitle: "ImageView"))
        XCTAssertTrue(error.showsErrorState)
        XCTAssertFalse(error.showsEmptyState)

        let loading = WindowPresentation.resolve(WindowPresentation.Input(mode: .loading, viewerTitle: "ImageView"))
        XCTAssertFalse(loading.showsEmptyState)
        XCTAssertFalse(loading.showsErrorState)
    }

    func testPageControlsNeedMoreThanOneItemAndNoEditing() {
        XCTAssertFalse(WindowPresentation.pageControlsAllowed(mode: .single, itemCount: 1, isEditing: false))
        XCTAssertTrue(WindowPresentation.pageControlsAllowed(mode: .single, itemCount: 2, isEditing: false))
        XCTAssertFalse(WindowPresentation.pageControlsAllowed(mode: .single, itemCount: 2, isEditing: true))
        XCTAssertFalse(WindowPresentation.pageControlsAllowed(mode: .grid, itemCount: 9, isEditing: false))
    }

    /// 老的那几个规则入口和新模型必须给出同一个答案，不然又是两套真相。
    func testLegacyRuleEntriesAgreeWithTheModel() {
        XCTAssertEqual(
            MainWindowController.canEditFromTitleBar(
                canEditCurrentImage: true,
                isFolderBrowserMode: true,
                usesContinuousReading: false
            ),
            WindowPresentation.imageEditingAllowed(canEditCurrentImage: true, mode: .grid)
        )
        XCTAssertEqual(
            MainWindowController.shouldDisplayFilmstripOverlay(
                isEnabled: true,
                hasLoadedImage: true,
                isCropping: false,
                isFolderBrowserMode: false,
                usesContinuousReading: true
            ),
            WindowPresentation.filmstripVisible(isEnabled: true, hasImage: true, isEditing: false, mode: .continuous)
        )
        XCTAssertEqual(
            MainWindowController.shouldDisplayInspector(isEnabled: true, hasCurrentImage: false),
            WindowPresentation.inspectorVisible(isEnabled: true, hasImage: false)
        )
    }
}
