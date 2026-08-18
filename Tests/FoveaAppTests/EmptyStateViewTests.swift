import XCTest
@testable import FoveaApp

@MainActor
final class EmptyStateViewTests: XCTestCase {
    func testLocalizesEnglishAndSimplifiedChineseContent() {
        let english = EmptyStateView(preferredLanguages: ["en"])
        XCTAssertEqual(english.titleTextForTesting, "Open an Image")
        XCTAssertEqual(english.messageTextForTesting, "Drag an image here, or choose one below")
        XCTAssertEqual(english.buttonTitleForTesting, "Open Image…")
        XCTAssertEqual(english.browseFolderButtonTitleForTesting, "Browse Folder…")

        let chinese = EmptyStateView(preferredLanguages: ["zh-Hans"])
        XCTAssertEqual(chinese.titleTextForTesting, "打开图片")
        XCTAssertEqual(chinese.messageTextForTesting, "将图片拖到这里，或点击下方按钮")
        XCTAssertEqual(chinese.buttonTitleForTesting, "打开图片…")
        XCTAssertEqual(chinese.browseFolderButtonTitleForTesting, "浏览文件夹…")
    }

    func testOpenButtonInvokesCallbackExactlyOnce() {
        let view = EmptyStateView(preferredLanguages: ["en"])
        var count = 0
        view.onOpenRequested = { count += 1 }

        view.performOpenForTesting()

        XCTAssertEqual(count, 1)
    }

    /// 最近打开是一份列表：一行一个文件，副标题写它所在的文件夹。
    func testRecentItemsAreListedWithTheirFolder() {
        let view = EmptyStateView(preferredLanguages: ["en"])
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Snapshots", isDirectory: true)

        view.applyRecentItems([
            folder.appendingPathComponent("one.png"),
            folder.appendingPathComponent("two.jpg")
        ])

        let list = view.recentListForTesting
        XCTAssertEqual(list.itemCountForTesting, 2)
        XCTAssertEqual(list.itemTitlesForTesting, ["one.png", "two.jpg"])
        XCTAssertEqual(list.itemSubtitlesForTesting, ["Snapshots", "Snapshots"])
        XCTAssertFalse(list.isHidden)
    }

    /// 列表只留最近几条，再多就把空状态撑得比画面还长。
    func testRecentListKeepsOnlyTheMostRecentItems() {
        let view = EmptyStateView(preferredLanguages: ["en"])
        let folder = FileManager.default.temporaryDirectory

        view.applyRecentItems((0..<9).map { folder.appendingPathComponent("\($0).png") })

        XCTAssertEqual(view.recentListForTesting.itemCountForTesting, RecentItemsListView.maximumItemCount)
        XCTAssertEqual(view.recentListForTesting.itemTitlesForTesting.first, "0.png")
    }

    /// 一条都没有时整块列表让位，标题和清除按钮也不留在画面上。
    func testRecentListDisappearsWithoutItems() {
        let view = EmptyStateView(preferredLanguages: ["en"])
        view.applyRecentItems([FileManager.default.temporaryDirectory.appendingPathComponent("one.png")])

        view.applyRecentItems([])

        XCTAssertEqual(view.recentListForTesting.itemCountForTesting, 0)
        XCTAssertTrue(view.recentListForTesting.isHidden)
    }

    func testRecentRowReportsItsURLAndClearingIsSeparate() {
        let view = EmptyStateView(preferredLanguages: ["en"])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("picked.png")
        var opened: [URL] = []
        var clearCount = 0
        view.onOpenRecentRequested = { opened.append($0) }
        view.onClearRecentRequested = { clearCount += 1 }
        view.applyRecentItems([url])

        view.recentListForTesting.openItemForTesting(at: 0)
        view.recentListForTesting.performClearForTesting()

        XCTAssertEqual(opened, [url])
        XCTAssertEqual(clearCount, 1)
    }

    /// 指针停在一行上时整行着色，落点在哪个字上都一样。
    func testRecentRowHighlightsWholeRowOnHover() {
        let row = RecentItemRowView(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("hover.png"),
            thumbnailProvider: ThumbnailProvider()
        )

        XCTAssertFalse(row.showsHoverForTesting)
        row.setHoveredForTesting(true)
        XCTAssertTrue(row.showsHoverForTesting)
        XCTAssertNotNil(row.layer?.backgroundColor)
        row.setHoveredForTesting(false)
        XCTAssertNil(row.layer?.backgroundColor)
    }

    func testRecentListLocalizesItsHeadingAndClearAction() {
        XCTAssertEqual(EmptyStateView(preferredLanguages: ["en"]).recentListForTesting.headingTextForTesting, "Recent")
        XCTAssertEqual(
            EmptyStateView(preferredLanguages: ["zh-Hans"]).recentListForTesting.headingTextForTesting,
            "最近打开"
        )
        XCTAssertEqual(
            EmptyStateView(preferredLanguages: ["en"]).recentListForTesting.clearTitleForTesting,
            "Clear Recent Items"
        )
    }

    func testBrowseFolderButtonInvokesCallbackExactlyOnce() {
        let view = EmptyStateView(preferredLanguages: ["en"])
        var count = 0
        view.onBrowseFolderRequested = { count += 1 }

        view.performBrowseFolderForTesting()

        XCTAssertEqual(count, 1)
    }
}
