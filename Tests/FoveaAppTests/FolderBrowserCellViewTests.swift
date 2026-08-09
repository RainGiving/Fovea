import AppKit
import FoveaCore
import XCTest
@testable import FoveaApp

@MainActor
final class FolderBrowserCellViewTests: XCTestCase {
    func testSelectedAppearanceRefreshesWhenEffectiveAppearanceChanges() {
        let cell = FolderBrowserCellView()
        cell.loadView()
        cell.isSelected = true
        let initialRefreshCount = cell.testingAppearanceRefreshCount
        cell.view.appearance = NSAppearance(named: .aqua)
        cell.view.viewDidChangeEffectiveAppearance()
        let lightBackground = cell.testingSelectionBackgroundColor

        cell.view.appearance = NSAppearance(named: .darkAqua)
        cell.view.viewDidChangeEffectiveAppearance()

        XCTAssertNotEqual(cell.testingSelectionBackgroundColor, lightBackground)
        XCTAssertGreaterThanOrEqual(cell.testingAppearanceRefreshCount - initialRefreshCount, 2)
    }

    /// 缩略图按比例居中画在格子里，四周不铺底板。
    ///
    /// 白底加等比缩放会让横图上下、竖图左右各留一块白，每格形状还不一样。
    func testThumbnailFitsInsideTheTileWithoutAPlate() {
        let box = CGRect(x: 0, y: 0, width: 132, height: 132)

        let landscape = ThumbnailTileView.fittedRect(imageSize: CGSize(width: 400, height: 200), in: box)
        XCTAssertEqual(landscape.width, 132, accuracy: 0.5)
        XCTAssertEqual(landscape.height, 66, accuracy: 0.5)
        XCTAssertEqual(landscape.midX, box.midX, accuracy: 0.5)
        XCTAssertEqual(landscape.midY, box.midY, accuracy: 0.5)

        let portrait = ThumbnailTileView.fittedRect(imageSize: CGSize(width: 200, height: 400), in: box)
        XCTAssertEqual(portrait.width, 66, accuracy: 0.5)
        XCTAssertEqual(portrait.height, 132, accuracy: 0.5)

        XCTAssertEqual(
            ThumbnailTileView.fittedRect(imageSize: .zero, in: box),
            .zero,
            "没有尺寸就什么都不画"
        )

        // 格子本身没有底色，网格底透上来。
        let tile = ThumbnailTileView(frame: box)
        XCTAssertNil(tile.layer?.backgroundColor)
    }

    func testSelectionChangesAppearanceWithoutChangingLayoutInLightAndDarkAppearances() {
        let item = ImageItem(
            url: URL(fileURLWithPath: "/tmp/a-very-long-image-filename-that-must-remain-visible.png"),
            format: .png
        )
        let provider = ThumbnailProvider(loader: { _, _, _, completion in
            completion(.success(NSImage(size: NSSize(width: 8, height: 8))))
            return {}
        })

        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let cell = FolderBrowserCellView()
            cell.loadView()
            cell.view.appearance = NSAppearance(named: appearanceName)
            cell.view.widthAnchor.constraint(equalToConstant: 148).isActive = true
            cell.configure(with: item, thumbnailProvider: provider)
            let size = cell.view.fittingSize

            cell.isSelected = true
            XCTAssertFalse(cell.testingFilename.isEmpty)
            XCTAssertTrue(cell.testingShowsSelection)
            XCTAssertGreaterThan(cell.view.layer?.backgroundColor?.alpha ?? 0, 0)
            XCTAssertGreaterThan(cell.view.layer?.borderWidth ?? 0, 0)
            XCTAssertEqual(cell.view.fittingSize, size)

            cell.isSelected = false
            XCTAssertFalse(cell.testingShowsSelection)
            XCTAssertEqual(cell.view.fittingSize, size)
        }
    }
}
