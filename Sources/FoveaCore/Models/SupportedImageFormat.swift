import Foundation
import UniformTypeIdentifiers

public enum SupportedImageFormat: String, CaseIterable, Sendable, Hashable {
    // 日常格式。
    case jpeg
    case png
    case gif
    case tiff
    case bmp
    case heic
    case heif
    case webp
    case avif
    case svg
    // 扩展格式。系统的 ImageIO 都能解码，只读不写。
    case jpeg2000
    case jpegXL
    case ico
    case psd
    case targa
    case openEXR
    case radiance
    case icns
    case netpbm
    case dds
    case sgi
    case rawPhoto
    case heicSequence
    case avci
    case mpo

    /// 一种格式的全部信息：认哪些后缀、对应哪些 UTI、界面上怎么显示。
    ///
    /// 集中成一张表，加格式时只改这里，不用再去翻好几个 switch。
    public struct Descriptor: Sendable {
        public let extensions: [String]
        /// 首项是代表类型，其余是同族别名。相机 RAW 每个厂商各有一个 UTI，所以是数组。
        public let typeIdentifiers: [String]
        public let displayName: String
    }

    public var descriptor: Descriptor {
        switch self {
        case .jpeg:
            return Descriptor(extensions: ["jpg", "jpeg"], typeIdentifiers: ["public.jpeg"], displayName: "JPEG")
        case .png:
            return Descriptor(extensions: ["png"], typeIdentifiers: ["public.png"], displayName: "PNG")
        case .gif:
            return Descriptor(extensions: ["gif"], typeIdentifiers: ["com.compuserve.gif"], displayName: "GIF")
        case .tiff:
            return Descriptor(extensions: ["tif", "tiff"], typeIdentifiers: ["public.tiff"], displayName: "TIFF")
        case .bmp:
            return Descriptor(extensions: ["bmp"], typeIdentifiers: ["com.microsoft.bmp"], displayName: "BMP")
        case .heic:
            return Descriptor(extensions: ["heic"], typeIdentifiers: ["public.heic"], displayName: "HEIC")
        case .heif:
            return Descriptor(extensions: ["heif"], typeIdentifiers: ["public.heif"], displayName: "HEIF")
        case .webp:
            return Descriptor(extensions: ["webp"], typeIdentifiers: ["org.webmproject.webp"], displayName: "WebP")
        case .avif:
            return Descriptor(extensions: ["avif"], typeIdentifiers: ["public.avif"], displayName: "AVIF")
        case .svg:
            return Descriptor(extensions: ["svg"], typeIdentifiers: ["public.svg-image"], displayName: "SVG")
        case .jpeg2000:
            return Descriptor(
                extensions: ["jp2", "jpf", "jpx", "j2k", "j2c"],
                typeIdentifiers: ["public.jpeg-2000"],
                displayName: "JPEG 2000"
            )
        case .jpegXL:
            return Descriptor(extensions: ["jxl"], typeIdentifiers: ["public.jpeg-xl"], displayName: "JPEG XL")
        case .ico:
            return Descriptor(extensions: ["ico"], typeIdentifiers: ["com.microsoft.ico"], displayName: "ICO")
        case .psd:
            return Descriptor(
                extensions: ["psd"],
                typeIdentifiers: ["com.adobe.photoshop-image"],
                displayName: "Photoshop"
            )
        case .targa:
            return Descriptor(extensions: ["tga"], typeIdentifiers: ["com.truevision.tga-image"], displayName: "TGA")
        case .openEXR:
            return Descriptor(extensions: ["exr"], typeIdentifiers: ["com.ilm.openexr-image"], displayName: "OpenEXR")
        case .radiance:
            return Descriptor(extensions: ["hdr"], typeIdentifiers: ["public.radiance"], displayName: "Radiance HDR")
        case .icns:
            return Descriptor(extensions: ["icns"], typeIdentifiers: ["com.apple.icns"], displayName: "Apple Icon")
        case .netpbm:
            return Descriptor(
                extensions: ["pbm", "pgm", "ppm", "pfm"],
                typeIdentifiers: ["public.pbm"],
                displayName: "Netpbm"
            )
        case .dds:
            return Descriptor(extensions: ["dds"], typeIdentifiers: ["com.microsoft.dds"], displayName: "DDS")
        case .sgi:
            return Descriptor(extensions: ["sgi"], typeIdentifiers: ["com.sgi.sgi-image"], displayName: "SGI")
        case .rawPhoto:
            return Descriptor(
                extensions: [
                    "dng", "cr2", "cr3", "crw", "nef", "nrw", "arw", "srf", "sr2", "raf",
                    "orf", "ori", "rw2", "pef", "srw", "erf", "dcr", "mrw", "mos", "rwl",
                    "iiq", "3fr", "fff", "dxo", "raw"
                ],
                typeIdentifiers: [
                    "com.adobe.raw-image",
                    "com.canon.cr2-raw-image", "com.canon.cr3-raw-image", "com.canon.crw-raw-image",
                    "com.nikon.raw-image", "com.nikon.nrw-raw-image", "com.nikon.nefx-raw-image",
                    "com.sony.arw-raw-image", "com.sony.raw-image", "com.sony.sr2-raw-image",
                    "com.fuji.raw-image", "com.olympus.raw-image", "com.olympus.or-raw-image",
                    "com.olympus.sr-raw-image", "com.panasonic.raw-image", "com.panasonic.rw2-raw-image",
                    "com.pentax.raw-image", "com.samsung.raw-image", "com.epson.raw-image",
                    "com.kodak.raw-image", "com.konicaminolta.raw-image", "com.leafamerica.raw-image",
                    "com.leica.raw-image", "com.leica.rwl-raw-image", "com.phaseone.raw-image",
                    "com.hasselblad.3fr-raw-image", "com.hasselblad.fff-raw-image", "com.dxo.raw-image"
                ],
                displayName: "RAW"
            )
        case .heicSequence:
            return Descriptor(extensions: ["heics"], typeIdentifiers: ["public.heics"], displayName: "HEIC Sequence")
        case .avci:
            return Descriptor(extensions: ["avci"], typeIdentifiers: ["public.avci"], displayName: "AVCI")
        case .mpo:
            return Descriptor(extensions: ["mpo"], typeIdentifiers: ["public.mpo-image"], displayName: "MPO")
        }
    }

    /// 后缀到格式的反查表。同一个后缀只归属一种格式，先声明的先占。
    private static let formatsByExtension: [String: SupportedImageFormat] = {
        var table: [String: SupportedImageFormat] = [:]
        for format in SupportedImageFormat.allCases {
            for ext in format.descriptor.extensions where table[ext] == nil {
                table[ext] = format
            }
        }
        return table
    }()

    public init?(fileExtension: String) {
        let normalized = fileExtension
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard let format = Self.formatsByExtension[normalized] else { return nil }
        self = format
    }

    public var displayName: String { descriptor.displayName }

    /// 应用能安全写回的格式。RAW、PSD 这类只读，改完必须另存为别的格式。
    public var canAttemptSafeWrite: Bool {
        switch self {
        case .jpeg, .png, .tiff, .bmp, .heic, .heif:
            return true
        case .gif, .webp, .avif, .svg, .jpeg2000, .jpegXL, .ico, .psd, .targa,
             .openEXR, .radiance, .icns, .netpbm, .dds, .sgi, .rawPhoto,
             .heicSequence, .avci, .mpo:
            return false
        }
    }

    public var contentType: UTType? {
        switch self {
        case .jpeg:
            return .jpeg
        case .png:
            return .png
        case .gif:
            return .gif
        case .tiff:
            return .tiff
        case .bmp:
            return .bmp
        case .heic:
            return .heic
        case .heif:
            return .heif
        case .webp:
            return UTType.webP
        case .svg:
            return UTType.svg
        default:
            return UTType(descriptor.typeIdentifiers[0])
                ?? UTType(filenameExtension: descriptor.extensions[0])
        }
    }

    public var imageIOTypeIdentifier: String? {
        switch self {
        case .avif:
            return "public.avif"
        default:
            return contentType?.identifier ?? descriptor.typeIdentifiers.first
        }
    }

    /// 声明给 LaunchServices 的全部 UTI，Info.plist 和默认应用注册都用这个。
    public var typeIdentifiers: [String] { descriptor.typeIdentifiers }
}
