import AppKit

/// 图片右键菜单的结构与构建。
///
/// 条目顺序、分组和图标集中在 `sections` 里，`makeMenu` 只负责把它翻译成 `NSMenu`。
/// 启用状态交给 `MainWindowController.validateMenuItem`，由 AppKit 在菜单弹出时自动调用。
@MainActor
enum ImageContextMenuBuilder {
    struct Command {
        let titleKey: String
        let action: Selector
        let symbolName: String
    }

    /// 组与组之间插入分隔线。
    static let sections: [[Command]] = [
        [
            Command(
                titleKey: "contextMenu.copyImage",
                action: #selector(MainWindowController.copyCurrentImage(_:)),
                symbolName: "photo.on.rectangle"
            ),
            Command(
                titleKey: "contextMenu.copyFile",
                action: #selector(MainWindowController.copyCurrentImageFile(_:)),
                symbolName: "doc.on.doc"
            ),
            Command(
                titleKey: "menu.file.copyPath",
                action: #selector(MainWindowController.copyCurrentImagePath(_:)),
                symbolName: "link"
            )
        ],
        [
            Command(
                titleKey: "menu.image.rotateClockwise",
                action: #selector(MainWindowController.rotateClockwise(_:)),
                symbolName: "rotate.right"
            ),
            Command(
                titleKey: "menu.image.rotateCounterclockwise",
                action: #selector(MainWindowController.rotateCounterClockwise(_:)),
                symbolName: "rotate.left"
            ),
            // 翻转会改像素，只放在编辑控制条上，这里不重复出现。
            // 旋转留在菜单里，因为它在查看状态下只是换个角度看，不改文件。
            Command(
                titleKey: "menu.image.edit",
                action: #selector(MainWindowController.startEditingImage(_:)),
                symbolName: "crop.rotate"
            )
        ],
        [
            Command(
                titleKey: "menu.edit.undo",
                action: #selector(MainWindowController.undoEdit(_:)),
                symbolName: "arrow.uturn.backward"
            ),
            Command(
                titleKey: "menu.edit.redo",
                action: #selector(MainWindowController.redoEdit(_:)),
                symbolName: "arrow.uturn.forward"
            ),
            Command(
                titleKey: "menu.image.saveEdits",
                action: #selector(MainWindowController.saveEdits(_:)),
                symbolName: "square.and.arrow.down"
            ),
            Command(
                titleKey: "menu.image.saveAs",
                action: #selector(MainWindowController.saveEditsAs(_:)),
                symbolName: "square.and.arrow.down.on.square"
            )
        ],
        [
            Command(
                titleKey: "menu.file.reveal",
                action: #selector(MainWindowController.revealCurrentImageInFinder(_:)),
                symbolName: "folder"
            ),
            Command(
                titleKey: "menu.file.rename",
                action: #selector(MainWindowController.renameCurrentImage(_:)),
                symbolName: "pencil"
            ),
            Command(
                titleKey: "menu.file.moveToTrash",
                action: #selector(MainWindowController.moveCurrentImageToTrash(_:)),
                symbolName: "trash"
            )
        ],
        // 胶卷、编辑、连续浏览已经是上边栏上的按钮，这里不再重复。
        // 信息面板的开关在底栏右下角，和这一组的其他视图开关放在一起更好找。
        [
            Command(
                titleKey: "menu.view.showInfo",
                action: #selector(MainWindowController.toggleInspector(_:)),
                symbolName: "info.circle"
            )
        ]
    ]

    /// 「打开方式」子菜单插在文件分组的最前面。
    static let openWithSectionIndex = 3

    static func makeMenu(
        target: MainWindowController,
        openWithApplications: [URL],
        shortcutSource: NSMenu? = NSApp.mainMenu
    ) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = true

        for (sectionIndex, section) in sections.enumerated() {
            if sectionIndex > 0 {
                menu.addItem(.separator())
            }
            if sectionIndex == openWithSectionIndex, !openWithApplications.isEmpty {
                menu.addItem(makeOpenWithItem(target: target, applications: openWithApplications))
            }
            for command in section {
                menu.addItem(makeItem(command, target: target, shortcutSource: shortcutSource))
            }
        }

        return menu
    }

    private static func makeItem(
        _ command: Command,
        target: MainWindowController,
        shortcutSource: NSMenu?
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: AppStrings.text(command.titleKey),
            action: command.action,
            keyEquivalent: ""
        )
        item.target = target
        item.image = NSImage(systemSymbolName: command.symbolName, accessibilityDescription: item.title)
        // 沿用主菜单里的快捷键，让右键菜单同时起到提示作用。
        if let source = MainWindowController.menuItem(in: shortcutSource, matching: command.action) {
            item.keyEquivalent = source.keyEquivalent
            item.keyEquivalentModifierMask = source.keyEquivalentModifierMask
        }
        return item
    }

    private static func makeOpenWithItem(
        target: MainWindowController,
        applications: [URL]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: AppStrings.text("contextMenu.openWith"), action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: item.title)

        let submenu = NSMenu()
        submenu.autoenablesItems = true
        for applicationURL in applications {
            let entry = NSMenuItem(
                title: applicationName(for: applicationURL),
                action: #selector(MainWindowController.openCurrentImageWithApplication(_:)),
                keyEquivalent: ""
            )
            entry.target = target
            entry.representedObject = applicationURL
            let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
            icon.size = NSSize(width: 16, height: 16)
            entry.image = icon
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }

    static func applicationName(for applicationURL: URL) -> String {
        FileManager.default.displayName(atPath: applicationURL.path)
    }
}
