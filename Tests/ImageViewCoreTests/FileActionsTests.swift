import XCTest
@testable import ImageViewCore

final class FileActionsTests: XCTestCase {
    func testRenamePreservesExtension() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("old.png")
        FileManager.default.createFile(atPath: original.path, contents: Data("x".utf8))

        let renamed = try FileActions().rename(original, to: "new")

        XCTAssertEqual(renamed.lastPathComponent, "new.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
    }

    func testAbsolutePathReturnsPathString() {
        let url = URL(fileURLWithPath: "/tmp/a.png")
        XCTAssertEqual(FileActions().absolutePath(for: url), "/tmp/a.png")
    }

    func testRenameRejectsEmptyName() {
        XCTAssertEqual(renameError(for: "   "), .emptyName)
    }

    func testRenameRejectsPathLikeNames() {
        XCTAssertEqual(renameError(for: "nested/name"), .invalidBaseName)
        XCTAssertEqual(renameError(for: "nested:name"), .invalidBaseName)
        XCTAssertEqual(renameError(for: "."), .invalidBaseName)
        XCTAssertEqual(renameError(for: ".."), .invalidBaseName)
    }

    func testRenameToExistingBaseNameIsANoOp() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("same.png")
        let contents = Data("keep me".utf8)
        try contents.write(to: original)

        let renamed = try FileActions().rename(original, to: "same")

        XCTAssertEqual(renamed, original)
        XCTAssertEqual(try Data(contentsOf: original), contents)
    }

    func testCopyImageOffersBothTiffAndPngSoAnyReceiverCanPaste() throws {
        let pasteboard = makeScratchPasteboard()
        let image = try makeSolidImage(width: 4, height: 3)

        XCTAssertTrue(FileActions().copyImage(image, to: pasteboard))

        let types = try XCTUnwrap(pasteboard.types)
        XCTAssertTrue(types.contains(.tiff))
        XCTAssertTrue(types.contains(.png))
        let pasted = try XCTUnwrap(NSImage(pasteboard: pasteboard))
        XCTAssertEqual(pasted.representations.first?.pixelsWide, 4)
        XCTAssertEqual(pasted.representations.first?.pixelsHigh, 3)
    }

    func testCopyImageReplacesWhateverWasOnThePasteboard() throws {
        let pasteboard = makeScratchPasteboard()
        pasteboard.clearContents()
        pasteboard.setString("stale", forType: .string)

        XCTAssertTrue(FileActions().copyImage(try makeSolidImage(width: 2, height: 2), to: pasteboard))

        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func testCopyFileWritesAFileURLThatFinderCanPaste() throws {
        let pasteboard = makeScratchPasteboard()
        let url = URL(fileURLWithPath: "/tmp/sample.png")

        XCTAssertTrue(FileActions().copyFile(url, to: pasteboard))

        let pasted = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        XCTAssertEqual(pasted, [url])
    }

    private func makeScratchPasteboard() -> NSPasteboard {
        let name = "FileActionsTests.\(UUID().uuidString)"
        addTeardownBlock { NSPasteboard(name: NSPasteboard.Name(name)).releaseGlobally() }
        return NSPasteboard(name: NSPasteboard.Name(name))
    }

    private func makeSolidImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func renameError(for newBaseName: String) -> FileActionError? {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let original = root.appendingPathComponent("old.png")
        FileManager.default.createFile(atPath: original.path, contents: Data("x".utf8))

        do {
            _ = try FileActions().rename(original, to: newBaseName)
            return nil
        } catch let error as FileActionError {
            return error
        } catch {
            XCTFail("Unexpected error: \(error)")
            return nil
        }
    }
}
