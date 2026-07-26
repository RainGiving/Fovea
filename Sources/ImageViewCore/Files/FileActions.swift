import AppKit
import Foundation

public enum FileActionError: Error, Equatable {
    case emptyName
    case invalidBaseName
    case unsupportedRenameTarget
}

public final class FileActions {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func moveToTrash(_ url: URL) throws {
        var resultingURL: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
    }

    public func rename(_ url: URL, to newBaseName: String) throws -> URL {
        let trimmed = newBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FileActionError.emptyName
        }
        guard trimmed != ".",
              trimmed != "..",
              !trimmed.contains("/"),
              !trimmed.contains(":") else {
            throw FileActionError.invalidBaseName
        }

        let ext = url.pathExtension
        guard !ext.isEmpty else {
            throw FileActionError.unsupportedRenameTarget
        }

        let parentDirectory = url.deletingLastPathComponent()
        let destination = parentDirectory
            .appendingPathComponent(trimmed)
            .appendingPathExtension(ext)
        guard destination.deletingLastPathComponent().standardizedFileURL == parentDirectory.standardizedFileURL else {
            throw FileActionError.invalidBaseName
        }
        if destination.standardizedFileURL == url.standardizedFileURL {
            return url
        }
        try fileManager.moveItem(at: url, to: destination)
        return destination
    }

    public func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func absolutePath(for url: URL) -> String {
        url.path
    }

    /// 把位图写入剪贴板，同时提供 TIFF 和 PNG 两种表示。
    /// 贴到备忘录、聊天窗口或图像编辑器都能直接得到图片。
    @discardableResult
    public func copyImage(_ image: CGImage, to pasteboard: NSPasteboard = .general) -> Bool {
        let representation = NSBitmapImageRep(cgImage: image)
        guard let tiffData = representation.tiffRepresentation else { return false }

        let item = NSPasteboardItem()
        item.setData(tiffData, forType: .tiff)
        if let pngData = representation.representation(using: .png, properties: [:]) {
            item.setData(pngData, forType: .png)
        }

        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    /// 把文件本身写入剪贴板，可以在访达里直接粘贴出一份拷贝。
    @discardableResult
    public func copyFile(_ url: URL, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.writeObjects([url as NSURL])
    }

    /// 能打开该文件的应用，按系统给出的优先顺序排列，默认应用排在最前。
    public func applicationURLs(toOpen url: URL) -> [URL] {
        NSWorkspace.shared.urlsForApplications(toOpen: url)
    }

    public func open(_ url: URL, withApplicationAt applicationURL: URL) {
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: applicationURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
