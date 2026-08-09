import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageEditingError: Error, Equatable {
    case cannotCreateContext
    case cannotCreateImage
    case unsupportedSaveFormat
    case cannotCreateDestination
    case saveFailed
}

public final class ImageEditingService {
    public init() {}

    public static func writableSaveFormats() -> [SupportedImageFormat] {
        [.png, .jpeg, .tiff, .bmp, .heic, .heif].filter { format in
            guard let uti = uti(for: format) else { return false }
            let destinationTypes = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
            return destinationTypes.contains(uti)
        }
    }

    public func apply(_ operations: [EditOperation], to image: CGImage) throws -> CGImage {
        try operations.reduce(image) { current, operation in
            switch operation {
            case .rotateClockwise:
                return try transform(current, radians: -.pi / 2, scaleX: 1, scaleY: 1)
            case .rotateCounterClockwise:
                return try transform(current, radians: .pi / 2, scaleX: 1, scaleY: 1)
            case .mirrorHorizontal:
                return try transform(current, radians: 0, scaleX: -1, scaleY: 1)
            case .mirrorVertical:
                return try transform(current, radians: 0, scaleX: 1, scaleY: -1)
            case .crop(let rect):
                guard let cropped = current.cropping(to: rect.integral) else {
                    throw ImageEditingError.cannotCreateImage
                }
                return cropped
            }
        }
    }

    public func save(
        _ image: CGImage,
        to url: URL,
        format: SupportedImageFormat,
        metadataSourceURL: URL? = nil
    ) throws {
        guard format.canAttemptSafeWrite, let uti = Self.uti(for: format) else {
            throw ImageEditingError.unsupportedSaveFormat
        }

        let metadata = metadataSourceURL.flatMap {
            sanitizedMetadata(from: $0, for: format, outputImage: image)
        }
        let properties = Self.applyingCompression(to: metadata, format: format)

        let temporaryURL = url
            .deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).fovea-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        guard let destination = CGImageDestinationCreateWithURL(
            temporaryURL as CFURL,
            uti as CFString,
            1,
            nil
        ) else {
            throw ImageEditingError.cannotCreateDestination
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageEditingError.saveFailed
        }

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func sanitizedMetadata(
        from sourceURL: URL,
        for format: SupportedImageFormat,
        outputImage: CGImage
    ) -> [CFString: Any]? {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }

        var properties: [CFString: Any] = [:]
        for key in Self.compatibleRootKeys {
            properties[key] = sourceProperties[key]
        }

        if Self.supportsRichMetadata(format) {
            for key in Self.compatibleMetadataDictionaryKeys {
                guard let dictionary = sourceProperties[key] as? [CFString: Any] else { continue }
                properties[key] = Self.removingStaleThumbnailFields(from: dictionary)
            }
        }

        properties[kCGImagePropertyOrientation] = 1
        properties[kCGImagePropertyPixelWidth] = outputImage.width
        properties[kCGImagePropertyPixelHeight] = outputImage.height

        if var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = outputImage.width
            exif[kCGImagePropertyExifPixelYDimension] = outputImage.height
            properties[kCGImagePropertyExifDictionary] = exif
        }

        if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            for key in Self.staleTIFFStorageKeys {
                tiff.removeValue(forKey: key)
            }
            properties[kCGImagePropertyTIFFDictionary] = tiff
        }

        return properties
    }

    /// 有损格式的写出质量。
    ///
    /// 不设这一项时 ImageIO 按接近无损写，一张两百 KB 的 JPEG 转一圈能涨到好几 MB。
    /// 0.92 在肉眼几乎看不出差别的前提下把体积压回正常量级。
    public static let lossyCompressionQuality: CGFloat = 0.92

    /// TIFF 的 LZW 压缩代号。
    ///
    /// 四种无损方案在一张 7952×5304 的照片上实测：无压缩 120.7 MB，
    /// PackBits 121.5 MB，Deflate 53.0 MB，LZW 48.1 MB。LZW 最小，
    /// 兼容性也最好，所以选它。
    public static let tiffLZWCompression = 5

    /// 补上写文件时的压缩设置。
    ///
    /// `CGImageDestination` 默认既不压 TIFF 也不给有损格式定质量，
    /// 于是一张小图改完会写出一个几十倍大的文件。按格式分别补齐。
    static func applyingCompression(
        to properties: [CFString: Any]?,
        format: SupportedImageFormat
    ) -> [CFString: Any] {
        var result = properties ?? [:]
        switch format {
        case .tiff:
            // 合并进已有的 TIFF 字典，不要整个覆盖掉元数据。
            var tiff = result[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            tiff[kCGImagePropertyTIFFCompression] = tiffLZWCompression
            result[kCGImagePropertyTIFFDictionary] = tiff
        case .jpeg, .heic, .heif:
            result[kCGImageDestinationLossyCompressionQuality] = lossyCompressionQuality
        default:
            // PNG 自带 deflate，BMP 本身无压缩，其余格式只读，不走写入路径。
            break
        }
        return result
    }

    private static var compatibleRootKeys: [CFString] {
        [
            kCGImagePropertyDPIWidth,
            kCGImagePropertyDPIHeight,
            kCGImagePropertyColorModel,
            kCGImagePropertyProfileName
        ]
    }

    private static var compatibleMetadataDictionaryKeys: [CFString] {
        [
            kCGImagePropertyExifDictionary,
            kCGImagePropertyExifAuxDictionary,
            kCGImagePropertyGPSDictionary,
            kCGImagePropertyTIFFDictionary,
            kCGImagePropertyIPTCDictionary
        ]
    }

    private static var staleTIFFStorageKeys: [CFString] {
        [
            kCGImagePropertyTIFFCompression,
            kCGImagePropertyTIFFPhotometricInterpretation,
            kCGImagePropertyTIFFTileWidth,
            kCGImagePropertyTIFFTileLength
        ]
    }

    private static func supportsRichMetadata(_ format: SupportedImageFormat) -> Bool {
        switch format {
        case .jpeg, .tiff, .heic, .heif:
            return true
        default:
            return false
        }
    }

    private static func removingStaleThumbnailFields(from dictionary: [CFString: Any]) -> [CFString: Any] {
        dictionary.reduce(into: [CFString: Any]()) { result, entry in
            let normalizedKey = (entry.key as String).lowercased()
            guard !normalizedKey.contains("thumbnail"),
                  normalizedKey != "jpeginterchangeformat",
                  normalizedKey != "jpeginterchangeformatlength" else {
                return
            }

            if let nested = entry.value as? [CFString: Any] {
                result[entry.key] = removingStaleThumbnailFields(from: nested)
            } else {
                result[entry.key] = entry.value
            }
        }
    }

    private func transform(_ image: CGImage, radians: CGFloat, scaleX: CGFloat, scaleY: CGFloat) throws -> CGImage {
        let rotated = abs(radians) == .pi / 2
        let width = rotated ? image.height : image.width
        let height = rotated ? image.width : image.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImageEditingError.cannotCreateContext
        }

        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.rotate(by: radians)
        context.scaleBy(x: scaleX, y: scaleY)
        context.draw(
            image,
            in: CGRect(
                x: -CGFloat(image.width) / 2,
                y: -CGFloat(image.height) / 2,
                width: CGFloat(image.width),
                height: CGFloat(image.height)
            )
        )

        guard let output = context.makeImage() else {
            throw ImageEditingError.cannotCreateImage
        }
        return output
    }

    private static func uti(for format: SupportedImageFormat) -> String? {
        switch format {
        case .jpeg:
            return UTType.jpeg.identifier
        case .png:
            return UTType.png.identifier
        case .tiff:
            return UTType.tiff.identifier
        case .bmp:
            return UTType.bmp.identifier
        case .heic:
            return UTType.heic.identifier
        case .heif:
            let heifIdentifier = UTType.heif.identifier
            let destinationTypes = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
            return destinationTypes.contains(heifIdentifier) ? heifIdentifier : nil
        default:
            // 其余格式一律只读，没有写出目标。
            return nil
        }
    }
}
