import Foundation

/// 另存为时的默认文件名。
///
/// 在原名后面加 `_1`，同目录下已经占用就往后数 `_2`、`_3`，
/// 直到找到没被占用的名字。
public enum SaveAsNaming {
    /// 最多往后试多少个序号。到顶还没空位就带上时间戳兜底，避免死循环。
    public static let maximumSuffix = 9_999

    /// 已经带 `_数字` 后缀的名字继续往后数，不会叠成 `photo_1_1`。
    public static func baseNameStrippingSuffix(_ name: String) -> (base: String, index: Int) {
        guard let separator = name.range(of: "_", options: .backwards) else { return (name, 0) }
        let tail = String(name[separator.upperBound...])
        guard !tail.isEmpty, tail.allSatisfy(\.isNumber), let index = Int(tail) else {
            return (name, 0)
        }
        return (String(name[..<separator.lowerBound]), index)
    }

    /// 给出一个同目录下未被占用的候选 URL。
    ///
    /// - Parameters:
    ///   - url: 原文件。
    ///   - fileExists: 判断某个路径是否已存在，测试时可替换。
    public static func proposedURL(
        for url: URL,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let directory = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let (base, existingIndex) = baseNameStrippingSuffix(url.deletingPathExtension().lastPathComponent)

        var index = max(1, existingIndex + 1)
        while index <= maximumSuffix {
            let candidate = candidateURL(directory: directory, base: base, index: index, ext: ext)
            if !fileExists(candidate) { return candidate }
            index += 1
        }

        // 序号用尽，退回时间戳，保证总能给出一个不冲突的名字。
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return candidateURL(directory: directory, base: base, index: nil, suffix: stamp, ext: ext)
    }

    private static func candidateURL(
        directory: URL,
        base: String,
        index: Int?,
        suffix: String? = nil,
        ext: String
    ) -> URL {
        let tail = index.map(String.init) ?? (suffix ?? "1")
        let name = "\(base)_\(tail)"
        let file = ext.isEmpty ? name : "\(name).\(ext)"
        return directory.appendingPathComponent(file)
    }
}
