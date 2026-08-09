import Foundation
import FoveaCore
import XCTest
@testable import FoveaApp

@MainActor
final class FilmstripViewTests: XCTestCase {
    func testFilmstripContainerAddsNoIndependentSurface() {
        let overlay = FilmstripOverlayView()

        XCTAssertIdentical(overlay.contentView, overlay)
        XCTAssertTrue(overlay.subviews.isEmpty)
    }

    func testFilmstripContentLivesInsideTheContainer() {
        let overlay = FilmstripOverlayView()
        let filmstrip = FilmstripView()
        overlay.contentView.addSubview(filmstrip)

        XCTAssertIdentical(filmstrip.superview, overlay.contentView)
        XCTAssertTrue(overlay.subviews.contains(filmstrip))
    }

    func testSelectionKeepsThumbnailGeometryStable() {
        let regularSize = FilmstripView.thumbnailSize(isSelected: false)
        let selectedSize = FilmstripView.thumbnailSize(isSelected: true)

        XCTAssertEqual(selectedSize, regularSize)
    }

    func testFilmstripUsesReadableThumbnailAndOverlayDimensions() {
        XCTAssertEqual(FilmstripView.thumbnailSize(isSelected: false), CGSize(width: 72, height: 64))
        XCTAssertEqual(FilmstripView.thumbnailSize(isSelected: true), CGSize(width: 72, height: 64))
        XCTAssertEqual(FilmstripView.thumbnailDecodeMaxPixelSize, 192)
        // 选中的缩略图加上下内边距，再加下方滑杆的高度。
        XCTAssertGreaterThan(
            MainWindowController.filmstripOverlayHeight,
            FilmstripView.thumbnailSize(isSelected: true).height
        )
    }

    func testSliderProgressIsClampedAndInertWhenContentFits() {
        let filmstrip = FilmstripView()
        filmstrip.frame = NSRect(x: 0, y: 0, width: 600, height: 80)
        filmstrip.layoutSubtreeIfNeeded()

        // 一屏放得下时没有可滚动距离，进度恒为 0，滑杆也不该可用。
        XCTAssertFalse(filmstrip.isScrollable)
        XCTAssertEqual(filmstrip.scrollProgress, 0)
        filmstrip.scrollProgress = 0.8
        XCTAssertEqual(filmstrip.scrollProgress, 0)
    }

    func testApplyBuildsButtonsAndSelectionCallsOnSelect() {
        let first = ImageItem(url: URL(fileURLWithPath: "/tmp/a.png"), format: .png)
        let second = ImageItem(url: URL(fileURLWithPath: "/tmp/b.png"), format: .png)
        let filmstrip = FilmstripView()
        let expectation = expectation(description: "select")
        var selected: ImageItem?

        filmstrip.onSelect = { item in
            selected = item
            expectation.fulfill()
        }

        filmstrip.apply(items: [first, second], current: second)

        let buttons = filmstrip.debugButtons()
        XCTAssertEqual(buttons.map(\.title), ["a", "b"])
        XCTAssertFalse(filmstrip.debugIsSelected(buttons[0]))
        XCTAssertTrue(filmstrip.debugIsSelected(buttons[1]))
        // 选中态靠描边和亮度区分，不再让系统 bezel 在图后面铺一块底板。
        XCTAssertFalse(buttons[1].isBordered)
        XCTAssertEqual(buttons[1].layer?.borderWidth, FilmstripView.selectionRingWidth)
        XCTAssertEqual(buttons[1].alphaValue, 1, accuracy: 0.001)
        XCTAssertEqual(buttons[0].alphaValue, FilmstripView.unselectedThumbnailAlpha, accuracy: 0.001)
        XCTAssertEqual(buttons[1].imagePosition, .imageOnly)

        filmstrip.performDebugSelection(buttons[0])

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(selected?.url, first.url)
        XCTAssertEqual(selected?.format, .png)
    }

    func testMiddleSelectionIsCenteredInViewport() {
        let items = makeItems(count: 7)
        let filmstrip = FilmstripView()
        filmstrip.frame = NSRect(x: 0, y: 0, width: 360, height: 78)

        filmstrip.apply(items: items, current: items[3])
        filmstrip.layoutSubtreeIfNeeded()

        assertSelectedThumbnailCentered(filmstrip)
    }

    func testFirstAndLastSelectionsUseEmptySpaceToRemainCentered() {
        let items = makeItems(count: 7)
        let filmstrip = FilmstripView()
        filmstrip.frame = NSRect(x: 0, y: 0, width: 360, height: 78)

        filmstrip.apply(items: items, current: items.first)
        filmstrip.layoutSubtreeIfNeeded()
        assertSelectedThumbnailCentered(filmstrip)
        XCTAssertGreaterThan(filmstrip.debugLeadingSpacerWidth(), 0)

        filmstrip.apply(items: items, current: items.last)
        filmstrip.layoutSubtreeIfNeeded()
        assertSelectedThumbnailCentered(filmstrip)
        XCTAssertGreaterThan(filmstrip.debugTrailingSpacerWidth(), 0)
    }

    func testViewportResizeRecomputesSpacersAndRecentersSelection() {
        let items = makeItems(count: 7)
        let filmstrip = FilmstripView()
        filmstrip.frame = NSRect(x: 0, y: 0, width: 300, height: 78)
        filmstrip.apply(items: items, current: items[3])
        filmstrip.layoutSubtreeIfNeeded()
        let originalSpacerWidth = filmstrip.debugLeadingSpacerWidth()

        filmstrip.frame.size.width = 460
        filmstrip.layoutSubtreeIfNeeded()

        assertSelectedThumbnailCentered(filmstrip)
        XCTAssertGreaterThan(filmstrip.debugLeadingSpacerWidth(), originalSpacerWidth)
    }

    func testNilOrMissingSelectionReturnsToLeadingPosition() {
        let items = makeItems(count: 5)
        let filmstrip = FilmstripView()
        filmstrip.frame = NSRect(x: 0, y: 0, width: 300, height: 78)
        filmstrip.apply(items: items, current: items[3])

        filmstrip.apply(items: items, current: nil)
        XCTAssertEqual(filmstrip.contentView.bounds.origin.x, 0, accuracy: 0.5)

        let missing = ImageItem(url: URL(fileURLWithPath: "/tmp/missing.png"), format: .png)
        filmstrip.apply(items: items, current: missing)
        XCTAssertEqual(filmstrip.contentView.bounds.origin.x, 0, accuracy: 0.5)
    }

    func testLargeDirectoryRetainsBoundedWindowAndSelectionUpdateDoesNotReloadThumbnails() {
        let items = makeItems(count: 1_000)
        let loadCount = FilmstripLockedCounter()
        let provider = ThumbnailProvider(loader: { _, _, _, completion in
            loadCount.increment()
            completion(.success(NSImage(size: NSSize(width: 8, height: 8))))
            return {}
        })
        let filmstrip = FilmstripView(thumbnailProvider: provider)

        filmstrip.apply(items: items, current: items[500])
        let originalButtons = filmstrip.debugButtons()
        let originalIdentifiers = originalButtons.map(ObjectIdentifier.init)

        XCTAssertEqual(originalButtons.count, FilmstripView.maximumRetainedItemCount)
        XCTAssertEqual(loadCount.value, FilmstripView.maximumRetainedItemCount)

        for index in 501...519 {
            filmstrip.apply(items: items, current: items[index])
            XCTAssertEqual(filmstrip.debugButtons().map(ObjectIdentifier.init), originalIdentifiers)
            XCTAssertEqual(loadCount.value, FilmstripView.maximumRetainedItemCount)
        }

        XCTAssertEqual(filmstrip.debugSelectedTitle(), "519")
    }

    func testChangingSelectionDoesNotReflowThumbnailFrames() {
        let items = makeItems(count: 7)
        let filmstrip = FilmstripView()
        filmstrip.frame = NSRect(x: 0, y: 0, width: 360, height: 78)
        filmstrip.apply(items: items, current: items[2])
        filmstrip.layoutSubtreeIfNeeded()
        let originalFrames = filmstrip.debugButtons().map(\.frame)

        filmstrip.apply(items: items, current: items[3])
        filmstrip.layoutSubtreeIfNeeded()

        XCTAssertEqual(filmstrip.debugButtons().map(\.frame), originalFrames)
        assertSelectedThumbnailCentered(filmstrip)
    }

    /// 缩略图按格子的宽高比居中裁一刀，横幅照片不再在上下留两条空带。
    func testThumbnailsAreCroppedToFillTheCellInsteadOfLetterboxed() throws {
        let wide = try makeSolidImage(width: 400, height: 100)
        let target = FilmstripView.thumbnailSize(isSelected: false)

        let cropped = FilmstripView.centerCropped(wide, toAspectRatio: target.width / target.height)

        XCTAssertEqual(cropped.height, 100, "短边应当整条留下")
        XCTAssertEqual(
            CGFloat(cropped.width) / CGFloat(cropped.height),
            target.width / target.height,
            accuracy: 0.02
        )
    }

    func testCroppingKeepsTallImagesCenteredOnTheirWidth() throws {
        let tall = try makeSolidImage(width: 100, height: 400)
        let target = FilmstripView.thumbnailSize(isSelected: true)

        let cropped = FilmstripView.centerCropped(tall, toAspectRatio: target.width / target.height)

        XCTAssertEqual(cropped.width, 100, "短边应当整条留下")
        XCTAssertEqual(
            CGFloat(cropped.width) / CGFloat(cropped.height),
            target.width / target.height,
            accuracy: 0.02
        )
    }

    /// 去掉 bezel 之后系统不再给悬停反馈，亮度要自己接上。
    func testHoverBrightensOnlyTheThumbnailsThatAreNotCurrent() {
        let items = makeItems(count: 3)
        let filmstrip = FilmstripView()
        filmstrip.apply(items: items, current: items[1])
        let buttons = filmstrip.debugButtons()

        filmstrip.debugSetHovered(buttons[0], true)
        filmstrip.debugSetHovered(buttons[1], true)

        XCTAssertEqual(buttons[0].alphaValue, FilmstripView.hoveredThumbnailAlpha, accuracy: 0.001)
        XCTAssertEqual(buttons[1].alphaValue, 1, accuracy: 0.001)
    }

    private func makeSolidImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    /// 打开一张图时导航状态先发一次只含当前项的临时列表，扫完目录再发完整列表。
    /// 第二次不能把第一次的按钮和已经在跑的解码全推倒，否则当前这张要重新排队。
    func testRescanKeepsTheAlreadyLoadingButtonForTheOpenedImage() {
        let recorder = FilmstripLoadRecorder()
        let provider = ThumbnailProvider(loader: { item, _, priority, _ in
            recorder.record(url: item.url, priority: priority)
            return {}
        })
        let filmstrip = FilmstripView(thumbnailProvider: provider)
        let opened = ImageItem(url: URL(fileURLWithPath: "/tmp/5.png"), format: .png)

        filmstrip.apply(items: [opened], current: opened)
        let firstButton = filmstrip.debugButtons().first
        XCTAssertEqual(recorder.count(for: opened.url), 1)

        // 目录扫描回来的同一个文件带上了真实的修改时间和大小。
        let scanned = (0..<11).map {
            ImageItem(
                url: URL(fileURLWithPath: "/tmp/\($0).png"),
                format: .png,
                contentModificationDate: Date(timeIntervalSince1970: 1_000),
                fileSize: 4_096
            )
        }
        filmstrip.apply(items: scanned, current: scanned[5])

        XCTAssertEqual(recorder.count(for: opened.url), 1, "当前这张不该被取消后重新排队")
        XCTAssertTrue(
            filmstrip.debugButtons().contains { $0 === firstButton },
            "还在窗口里的条目应当沿用原来的按钮"
        )
        XCTAssertTrue(
            filmstrip.debugButtons().contains { $0 === firstButton && filmstrip.debugIsSelected($0) },
            "元数据换新之后选中态仍要落在这一格上"
        )
    }

    /// 胶卷条一次排进几十张，当前这张在正中间又被放大，缺图最显眼，要先解它。
    func testCurrentThumbnailIsRequestedAtHighPriority() {
        let recorder = FilmstripLoadRecorder()
        let provider = ThumbnailProvider(loader: { item, _, priority, _ in
            recorder.record(url: item.url, priority: priority)
            return {}
        })
        let filmstrip = FilmstripView(thumbnailProvider: provider)
        let items = makeItems(count: 40)

        filmstrip.apply(items: items, current: items[20])

        XCTAssertEqual(recorder.priority(for: items[20].url), .high)
        XCTAssertEqual(recorder.priority(for: items[19].url), .normal)
        XCTAssertEqual(recorder.firstRequestedURL, items[20].url, "当前这张要排在队首")
    }

    private func makeItems(count: Int) -> [ImageItem] {
        (0..<count).map {
            ImageItem(url: URL(fileURLWithPath: "/tmp/\($0).png"), format: .png)
        }
    }

    private func assertSelectedThumbnailCentered(
        _ filmstrip: FilmstripView,
        accuracy: CGFloat = 0.5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let selectedCenter = filmstrip.debugSelectedCenterInViewport() else {
            XCTFail("Expected a selected thumbnail", file: file, line: line)
            return
        }
        XCTAssertEqual(
            selectedCenter,
            filmstrip.contentView.bounds.midX,
            accuracy: accuracy,
            file: file,
            line: line
        )
    }
}

private final class FilmstripLoadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [URL: Int] = [:]
    private var priorities: [URL: ThumbnailPriority] = [:]
    private var order: [URL] = []

    func record(url: URL, priority: ThumbnailPriority) {
        lock.withLock {
            counts[url, default: 0] += 1
            priorities[url] = priority
            order.append(url)
        }
    }

    func count(for url: URL) -> Int {
        lock.withLock { counts[url] ?? 0 }
    }

    func priority(for url: URL) -> ThumbnailPriority? {
        lock.withLock { priorities[url] }
    }

    var firstRequestedURL: URL? {
        lock.withLock { order.first }
    }
}

private final class FilmstripLockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int { lock.withLock { storage } }

    func increment() {
        lock.withLock { storage += 1 }
    }
}
