import XCTest
@testable import ImageViewCore

final class SupportedImageFormatTests: XCTestCase {
    func testRequiredExtensionsAreSupported() {
        let extensions = ["jpg", "jpeg", "png", "gif", "tif", "tiff", "bmp", "heic", "heif", "webp", "avif", "svg"]
        for ext in extensions {
            XCTAssertNotNil(SupportedImageFormat(fileExtension: ext), ext)
        }
    }

    func testUnsupportedExtensionReturnsNil() {
        XCTAssertNil(SupportedImageFormat(fileExtension: "txt"))
    }

    func testExtendedFormatsAreRecognized() {
        let expected: [String: SupportedImageFormat] = [
            "jxl": .jpegXL, "jp2": .jpeg2000, "ico": .ico, "psd": .psd,
            "tga": .targa, "exr": .openEXR, "hdr": .radiance, "icns": .icns,
            "ppm": .netpbm, "dds": .dds, "sgi": .sgi,
            "cr3": .rawPhoto, "nef": .rawPhoto, "arw": .rawPhoto, "dng": .rawPhoto
        ]
        for (ext, format) in expected {
            XCTAssertEqual(SupportedImageFormat(fileExtension: ext), format, ext)
        }
    }

    func testEveryFormatHasExtensionsAndTypeIdentifiers() {
        for format in SupportedImageFormat.allCases {
            XCTAssertFalse(format.descriptor.extensions.isEmpty, "\(format) 缺后缀")
            XCTAssertFalse(format.descriptor.typeIdentifiers.isEmpty, "\(format) 缺 UTI")
            XCTAssertFalse(format.displayName.isEmpty, "\(format) 缺显示名")
        }
    }

    func testNoExtensionIsClaimedByTwoFormats() {
        var owner: [String: SupportedImageFormat] = [:]
        for format in SupportedImageFormat.allCases {
            for ext in format.descriptor.extensions {
                XCTAssertNil(owner[ext], "后缀 \(ext) 被 \(owner[ext]!) 和 \(format) 同时认领")
                owner[ext] = format
            }
        }
    }

    func testOnlyRoundTrippableFormatsAreWritable() {
        let writable = SupportedImageFormat.allCases.filter(\.canAttemptSafeWrite)
        XCTAssertEqual(Set(writable), Set([.jpeg, .png, .tiff, .bmp, .heic, .heif]))
    }
}
