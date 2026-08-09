import AppKit
import XCTest
@testable import FoveaApp
@testable import FoveaCore

@MainActor
final class ContinuousReadingViewTests: XCTestCase {
    func testContinuousReadingKeepsABoundedDecodedWindow() {
        let view = ContinuousReadingView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let radius = ContinuousReadingView.preloadRadius
        let total = radius * 2 + 4
        let focus = total / 2
        let items = (0..<total).map { index in
            ImageItem(
                url: URL(fileURLWithPath: "/tmp/\(index).png"),
                format: .png
            )
        }
        let pages = items.enumerated().map { index, item in
            ContinuousReadingPage(
                item: item,
                image: abs(index - focus) <= radius ? makeDecodedImage(width: 400, height: 600) : nil
            )
        }

        view.apply(pages: pages, currentItemID: items[focus].id)

        // 窗口大小由 preloadRadius 决定，这里只钉住「有界且完整目录可达」这条性质。
        XCTAssertEqual(ContinuousReadingView.maximumDecodedPageCount, radius * 2 + 1)
        XCTAssertEqual(view.testingPageCount, total, "the full directory remains vertically reachable")
        XCTAssertEqual(view.testingDecodedPageCount, radius * 2 + 1)
        XCTAssertEqual(view.testingPageURLs, items.map(\.url))
    }

    func testScrollingToUnloadedDirectoryPageRequestsANewDecodeWindow() {
        let view = ContinuousReadingView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let items = (0..<12).map {
            ImageItem(url: URL(fileURLWithPath: "/tmp/\($0).png"), format: .png)
        }
        var focusedID: ImageItem.ID?
        view.onFocusedItemChanged = { focusedID = $0 }
        view.apply(
            pages: items.map { ContinuousReadingPage(item: $0, image: nil) },
            currentItemID: items[2].id
        )

        view.testingScrollToItem(with: items[8].id)

        XCTAssertEqual(focusedID, items[8].id)
    }

    func testMissingNeighborDecodeRendersAsPlaceholderWithoutChangingOrder() {
        let view = ContinuousReadingView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let first = ImageItem(url: URL(fileURLWithPath: "/tmp/a.png"), format: .png)
        let second = ImageItem(url: URL(fileURLWithPath: "/tmp/b.png"), format: .png)

        view.apply(
            pages: [
                ContinuousReadingPage(item: first, image: makeDecodedImage(width: 400, height: 300)),
                ContinuousReadingPage(item: second, image: nil)
            ],
            currentItemID: first.id
        )

        XCTAssertEqual(view.testingPageURLs, [first.url, second.url])
        XCTAssertEqual(view.testingDecodedPageCount, 1)
    }

    func testLargeFolderFocusLookupUsesBinarySearch() {
        let view = ContinuousReadingView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let items = (0..<4_096).map {
            ImageItem(url: URL(fileURLWithPath: "/tmp/large-folder-\($0).png"), format: .png)
        }
        var focusedID: ImageItem.ID?
        view.onFocusedItemChanged = { focusedID = $0 }
        view.apply(
            pages: items.map { ContinuousReadingPage(item: $0, image: nil) },
            currentItemID: items[0].id
        )

        view.testingScrollToItem(with: items[3_000].id)

        XCTAssertEqual(focusedID, items[3_000].id)
        XCTAssertLessThanOrEqual(view.testingLastNearestLookupCount, 13)
    }

    private func makeDecodedImage(width: Int, height: Int) -> DecodedImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let image = context.makeImage()!
        return DecodedImage(
            cgImage: image,
            pixelSize: CGSize(width: width, height: height),
            isAnimated: false
        )
    }
}
