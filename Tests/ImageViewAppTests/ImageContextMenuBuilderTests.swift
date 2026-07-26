import AppKit
import ImageViewCore
import XCTest
@testable import ImageViewApp

@MainActor
final class ImageContextMenuBuilderTests: XCTestCase {
    func testEveryCommandSymbolResolvesToASystemImage() {
        for command in ImageContextMenuBuilder.sections.flatMap({ $0 }) {
            XCTAssertNotNil(
                NSImage(systemSymbolName: command.symbolName, accessibilityDescription: nil),
                "缺少系统符号 \(command.symbolName)（\(command.titleKey)）"
            )
        }
        XCTAssertNotNil(NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil))
    }

    func testEveryCommandTitleHasChineseAndEnglishTranslations() {
        for command in ImageContextMenuBuilder.sections.flatMap({ $0 }) {
            XCTAssertNotEqual(AppStrings.text(command.titleKey, preferredLanguages: ["en"]), command.titleKey)
            XCTAssertNotEqual(AppStrings.text(command.titleKey, preferredLanguages: ["zh-Hans"]), command.titleKey)
        }
        XCTAssertNotEqual(AppStrings.text("contextMenu.openWith", preferredLanguages: ["en"]), "contextMenu.openWith")
        XCTAssertNotEqual(AppStrings.text("contextMenu.openWith", preferredLanguages: ["zh-Hans"]), "contextMenu.openWith")
    }

    func testEveryCommandActionIsHandledByTheWindowController() {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        for command in ImageContextMenuBuilder.sections.flatMap({ $0 }) {
            XCTAssertTrue(
                controller.responds(to: command.action),
                "MainWindowController 无法响应 \(command.action)"
            )
        }
        XCTAssertTrue(controller.responds(to: #selector(MainWindowController.openCurrentImageWithApplication(_:))))
    }

    func testMenuSeparatesEverySectionWithoutLeadingOrTrailingSeparators() {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        let menu = ImageContextMenuBuilder.makeMenu(
            target: controller,
            openWithApplications: [],
            shortcutSource: nil
        )

        let separatorCount = menu.items.filter(\.isSeparatorItem).count
        XCTAssertEqual(separatorCount, ImageContextMenuBuilder.sections.count - 1)
        XCTAssertFalse(try XCTUnwrap(menu.items.first).isSeparatorItem)
        XCTAssertFalse(try XCTUnwrap(menu.items.last).isSeparatorItem)
    }

    func testMenuTargetsTheWindowControllerSoValidationApplies() throws {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        let menu = ImageContextMenuBuilder.makeMenu(
            target: controller,
            openWithApplications: [],
            shortcutSource: nil
        )

        for item in menu.items where !item.isSeparatorItem {
            XCTAssertTrue(item.target === controller, "\(item.title) 没有指向窗口控制器")
        }
    }

    func testOpenWithSubmenuIsOmittedWhenNoApplicationCanOpenTheFile() {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        let menu = ImageContextMenuBuilder.makeMenu(
            target: controller,
            openWithApplications: [],
            shortcutSource: nil
        )

        XCTAssertNil(menu.items.first { $0.submenu != nil })
    }

    func testOpenWithSubmenuCarriesOneEntryPerApplication() throws {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        let applications = [
            URL(fileURLWithPath: "/System/Applications/Preview.app"),
            URL(fileURLWithPath: "/Applications/ImageView.app")
        ]

        let menu = ImageContextMenuBuilder.makeMenu(
            target: controller,
            openWithApplications: applications,
            shortcutSource: nil
        )

        let openWithItem = try XCTUnwrap(menu.items.first { $0.submenu != nil })
        let submenu = try XCTUnwrap(openWithItem.submenu)
        XCTAssertEqual(submenu.items.count, applications.count)
        XCTAssertEqual(submenu.items.map(\.representedObject) as? [URL], applications)
        for item in submenu.items {
            XCTAssertEqual(item.action, #selector(MainWindowController.openCurrentImageWithApplication(_:)))
            XCTAssertTrue(item.target === controller)
        }
    }

    func testMenuMirrorsKeyEquivalentsFromTheMainMenu() throws {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        let source = NSMenu()
        let sourceItem = NSMenuItem(
            title: "Rotate",
            action: #selector(MainWindowController.rotateClockwise(_:)),
            keyEquivalent: "]"
        )
        sourceItem.keyEquivalentModifierMask = .command
        source.addItem(sourceItem)

        let menu = ImageContextMenuBuilder.makeMenu(
            target: controller,
            openWithApplications: [],
            shortcutSource: source
        )

        let rotateItem = try XCTUnwrap(
            menu.items.first { $0.action == #selector(MainWindowController.rotateClockwise(_:)) }
        )
        XCTAssertEqual(rotateItem.keyEquivalent, "]")
        XCTAssertEqual(rotateItem.keyEquivalentModifierMask, .command)
    }

    func testContextMenuIsUnavailableUntilAnImageIsOpen() {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        XCTAssertNil(controller.makeImageContextMenu())
    }

    func testCopyImageIsEnabledOnlyWhenAnImageIsDecoded() {
        XCTAssertFalse(
            MainWindowController.isMenuCommandEnabled(
                .copyImage,
                hasCurrentItem: true,
                hasCurrentImage: false,
                canEditCurrentImage: false,
                hasUnsavedEdits: false
            )
        )
        XCTAssertTrue(
            MainWindowController.isMenuCommandEnabled(
                .copyImage,
                hasCurrentItem: true,
                hasCurrentImage: true,
                canEditCurrentImage: false,
                hasUnsavedEdits: false
            )
        )
    }

    func testCopyFileAndOpenWithFollowTheCurrentItemRatherThanTheDecodedImage() {
        XCTAssertEqual(
            MainWindowController.menuCommand(for: #selector(MainWindowController.copyCurrentImageFile(_:))),
            .fileOperationRequiringCurrentItem
        )
        XCTAssertEqual(
            MainWindowController.menuCommand(for: #selector(MainWindowController.openCurrentImageWithApplication(_:))),
            .fileOperationRequiringCurrentItem
        )
        XCTAssertEqual(
            MainWindowController.menuCommand(for: #selector(MainWindowController.copyCurrentImage(_:))),
            .copyImage
        )
    }

    func testRightClickingTheCanvasProducesTheMenuWithCommandsEnabled() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let imageURL = root.appendingPathComponent("canvas.png")
        try writeTestPNG(to: imageURL)

        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        controller.open(url: imageURL)
        for _ in 0..<100 where !controller.hasLoadedImageForTesting {
            try await Task.sleep(for: .milliseconds(10))
        }

        let menu = try XCTUnwrap(controller.canvasForTesting.menu(for: makeRightClickEvent()))
        menu.update()

        let copyImage = try XCTUnwrap(
            menu.items.first { $0.action == #selector(MainWindowController.copyCurrentImage(_:)) }
        )
        XCTAssertTrue(copyImage.isEnabled)
        let rotate = try XCTUnwrap(
            menu.items.first { $0.action == #selector(MainWindowController.rotateClockwise(_:)) }
        )
        XCTAssertTrue(rotate.isEnabled)
        // 尚未编辑，保存应当是灰的。
        let save = try XCTUnwrap(
            menu.items.first { $0.action == #selector(MainWindowController.saveEdits(_:)) }
        )
        XCTAssertFalse(save.isEnabled)
    }

    func testContinuousReadingViewAnswersTheSameContextMenu() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let imageURL = root.appendingPathComponent("scroll.png")
        try writeTestPNG(to: imageURL)

        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        controller.open(url: imageURL)
        for _ in 0..<100 where !controller.hasLoadedImageForTesting {
            try await Task.sleep(for: .milliseconds(10))
        }

        let document = try XCTUnwrap(
            controller.continuousReadingViewForTesting.documentViewForTesting
        )
        let menu = try XCTUnwrap(document.menu(for: makeRightClickEvent()))
        XCTAssertNotNil(menu.items.first { $0.action == #selector(MainWindowController.copyCurrentImage(_:)) })
    }

    private func makeRightClickEvent() -> NSEvent {
        NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }

    private func writeTestPNG(to url: URL) throws {
        let representation = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 4,
                pixelsHigh: 4,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        try data.write(to: url)
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ImageViewAppTests.ImageContextMenuBuilder.\(UUID().uuidString)")!
    }
}
