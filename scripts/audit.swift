#!/usr/bin/env swift
import Foundation

// Fovea 代码审计。
//
// 用法：swift scripts/audit.swift [--strict]
//
// 逐项检查整个工程里容易积累的问题：本地化缺漏、强制解包、可访问性缺失、
// 死代码、遗留 TODO、主线程上的同步磁盘读写等。
// 加 --strict 时任何一条 error 都会让进程以非零码退出，可以挂进 CI。

let root = FileManager.default.currentDirectoryPath
let strict = CommandLine.arguments.contains("--strict")

enum Severity: String {
    case error = "错误"
    case warning = "警告"
    case info = "提示"
}

struct Finding {
    let severity: Severity
    let rule: String
    let file: String
    let line: Int?
    let message: String
}

/// 基线：已经看过并判定可接受的条目，降级为提示。
///
/// 目的是让新问题不被旧噪声淹没。同一规则在别的文件里新出现，照样报警告。
let baseline: [(rule: String, file: String, reason: String)] = {
    let path = root + "/scripts/audit-baseline.txt"
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    return text.components(separatedBy: .newlines).compactMap { line in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        let parts = trimmed.components(separatedBy: "|")
        guard parts.count >= 3 else { return nil }
        return (parts[0], parts[1], parts[2])
    }
}()

var findings: [Finding] = []
var acceptedCount = 0
func report(_ severity: Severity, _ rule: String, _ file: String, _ line: Int?, _ message: String) {
    if severity != .error,
       baseline.contains(where: { $0.rule == rule && $0.file == file }) {
        acceptedCount += 1
        return
    }
    findings.append(Finding(severity: severity, rule: rule, file: file, line: line, message: message))
}

func relative(_ path: String) -> String {
    path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : path
}

func swiftFiles(under directory: String) -> [String] {
    let base = root + "/" + directory
    guard let walker = FileManager.default.enumerator(atPath: base) else { return [] }
    return walker.compactMap { entry in
        guard let name = entry as? String, name.hasSuffix(".swift") else { return nil }
        return base + "/" + name
    }
}

let sourceFiles = swiftFiles(under: "Sources")
let testFiles = swiftFiles(under: "Tests")
var contents: [String: [String]] = [:]
for path in sourceFiles + testFiles {
    contents[path] = (try? String(contentsOfFile: path, encoding: .utf8))?
        .components(separatedBy: .newlines) ?? []
}
let allSource = sourceFiles.compactMap { contents[$0]?.joined(separator: "\n") }.joined(separator: "\n")
let allTests = testFiles.compactMap { contents[$0]?.joined(separator: "\n") }.joined(separator: "\n")

// MARK: 本地化

func stringsKeys(_ path: String) -> [String: Int] {
    guard let text = try? String(contentsOfFile: root + "/" + path, encoding: .utf8) else { return [:] }
    var keys: [String: Int] = [:]
    for (index, line) in text.components(separatedBy: .newlines).enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("\""), let close = trimmed.dropFirst().firstIndex(of: "\"") else { continue }
        keys[String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])] = index + 1
    }
    return keys
}

let zhPath = "Sources/FoveaApp/Resources/zh-Hans.lproj/Localizable.strings"
let enPath = "Sources/FoveaApp/Resources/en.lproj/Localizable.strings"
let zh = stringsKeys(zhPath)
let en = stringsKeys(enPath)

for key in en.keys.sorted() where zh[key] == nil {
    report(.error, "localization.missing", zhPath, nil, "英文有 \(key)，中文缺失")
}
for key in zh.keys.sorted() where en[key] == nil {
    report(.error, "localization.missing", enPath, nil, "中文有 \(key)，英文缺失")
}

// 代码里出现过的所有字符串字面量。
//
// 不能只匹配 AppStrings.text("…")：文案还会经由局部闭包（`text("a.b")`）、
// 菜单表的 titleKey 参数、常量等间接传进去，只认直接调用会把大量在用的 key
// 误报成无人引用。改成收集全部字面量再取交集。
var referencedKeys = Set<String>()
for path in sourceFiles {
    for line in contents[path] ?? [] {
        guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
        var rest = Substring(line)
        while let open = rest.firstIndex(of: "\"") {
            let after = rest[rest.index(after: open)...]
            guard let close = after.firstIndex(of: "\"") else { break }
            referencedKeys.insert(String(after[..<close]))
            rest = after[after.index(after: close)...]
        }
    }
}
// 反过来查「引用了但没定义」时不能用宽集合，那里面全是普通字符串。
// 只认 AppStrings.text("…") 这种明确的取文案调用。
var explicitKeys = Set<String>()
for path in sourceFiles {
    for line in contents[path] ?? [] {
        var rest = Substring(line)
        while let call = rest.range(of: "AppStrings.text(\"") {
            let after = rest[call.upperBound...]
            guard let close = after.firstIndex(of: "\"") else { break }
            explicitKeys.insert(String(after[..<close]))
            rest = after[close...]
        }
    }
}
for key in explicitKeys.sorted() where zh[key] == nil && en[key] == nil {
    report(.error, "localization.undefined", "Sources", nil, "代码引用了未定义的文案 key: \(key)")
}
for key in zh.keys.sorted() where !referencedKeys.contains(key) && !key.hasPrefix("help.") {
    report(.info, "localization.unused", zhPath, zh[key], "文案 \(key) 没有被任何代码引用")
}

// MARK: 逐行规则

for path in sourceFiles {
    let file = relative(path)
    for (index, raw) in (contents[path] ?? []).enumerated() {
        let line = index + 1
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("//") else { continue }

        // 强制解包和强制 try。测试里可以，产品代码里不行。
        if raw.range(of: #"[a-zA-Z0-9_\)\]]!\s*\."#, options: .regularExpression) != nil,
           !trimmed.contains("try!"), !trimmed.contains("as!") {
            report(.warning, "force.unwrap", file, line, "疑似强制解包，崩溃点：\(trimmed.prefix(80))")
        }
        if trimmed.contains("try!") {
            report(.error, "force.try", file, line, "强制 try 会在失败时直接崩溃")
        }
        if trimmed.contains("fatalError(") && !trimmed.contains("无法") && !file.contains("main.swift") {
            report(.warning, "fatal.error", file, line, "fatalError 会终止应用，确认这是不可恢复的情形")
        }

        // 主线程同步磁盘读写
        if trimmed.contains("contentsOfFile:") || trimmed.contains("Data(contentsOf:") {
            report(.warning, "sync.io", file, line, "同步读盘，确认不在主线程")
        }

        // 魔数颜色
        if raw.range(of: #"alphaComponent\(0\.[0-9]"#, options: .regularExpression) != nil,
           !file.contains("GlassMetrics") {
            report(.info, "magic.alpha", file, line, "透明度硬编码，考虑收进 GlassMetrics")
        }

        // 遗留标记
        for marker in ["TODO", "FIXME", "HACK", "XXX"] where trimmed.contains(marker) {
            report(.warning, "leftover.marker", file, line, "遗留 \(marker) 标记")
        }

        // print 调试残留
        if trimmed.hasPrefix("print(") {
            report(.warning, "debug.print", file, line, "调试用 print 残留")
        }
    }
}

// MARK: 生命周期与内存

for path in sourceFiles {
    let file = relative(path)
    let lines = contents[path] ?? []
    let text = lines.joined(separator: "\n")

    // 定时器要能被停掉，否则它会一直持有目标
    let timers = text.components(separatedBy: "Timer.scheduledTimer").count - 1
    if timers > 0, !text.contains("invalidate()") {
        report(.error, "timer.leak", file, nil, "创建了 \(timers) 个 Timer 但文件里没有 invalidate")
    }

    // 通知观察者
    if text.contains("addObserver(") , !text.contains("removeObserver"), !text.contains("deinit") {
        report(.warning, "observer.leak", file, nil, "注册了通知观察者但没有注销，也没有 deinit")
    }

    for (index, raw) in lines.enumerated() {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("//") else { continue }

        if trimmed.contains(" as! ") {
            report(.error, "force.cast", file, index + 1, "强制类型转换失败会崩溃")
        }

        // 逃逸闭包里直接用 self，且没有弱引用捕获
        if trimmed.contains("{ [weak self]") || trimmed.contains("{ [unowned self]") { continue }
        if raw.range(of: #"^\s*\w+\s*=\s*\{$"#, options: .regularExpression) != nil {
            // 属性上挂闭包，看后面几行有没有直接摸 self
            let window = lines[(index + 1)..<min(index + 8, lines.count)].joined(separator: "\n")
            if window.contains("self.") {
                report(.warning, "retain.cycle", file, index + 1, "闭包直接捕获 self，检查是否需要 [weak self]")
            }
        }
    }
}

// MARK: 体量

for path in sourceFiles {
    let file = relative(path)
    let lines = contents[path] ?? []
    if lines.count > 1_200 {
        report(.warning, "file.size", file, nil, "\(lines.count) 行，考虑按职责拆分")
    }

    var functionStart: Int?
    var depth = 0
    for (index, raw) in lines.enumerated() {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if functionStart == nil, trimmed.contains("func "), trimmed.hasSuffix("{") {
            functionStart = index
            depth = 1
            continue
        }
        guard let start = functionStart else { continue }
        depth += raw.filter { $0 == "{" }.count - raw.filter { $0 == "}" }.count
        if depth <= 0 {
            let length = index - start
            if length > 80 {
                let name = lines[start].trimmingCharacters(in: .whitespaces).prefix(60)
                report(.warning, "function.size", file, start + 1, "函数长 \(length) 行：\(name)")
            }
            functionStart = nil
        }
    }
}

// MARK: 可访问性

for path in sourceFiles {
    let file = relative(path)
    let text = contents[path]?.joined(separator: "\n") ?? ""
    let buttonCount = text.components(separatedBy: "NSButton(").count - 1
    let labelled = text.components(separatedBy: "setAccessibilityLabel").count - 1
        + text.components(separatedBy: "accessibilityDescription").count - 1
    if buttonCount > 0, labelled == 0 {
        report(.warning, "a11y.button", file, nil, "\(buttonCount) 个按钮但没有任何可访问性标签")
    }
}

// MARK: 死代码

// 只在自己文件里出现一次的内部类型，很可能已经没人用了
for path in sourceFiles {
    let file = relative(path)
    for (index, raw) in (contents[path] ?? []).enumerated() {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        for keyword in ["private func ", "private var ", "private static func "] {
            guard trimmed.hasPrefix(keyword) else { continue }
            let tail = trimmed.dropFirst(keyword.count)
            let name = String(tail.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
            guard name.count > 2 else { continue }
            let own = contents[path]?.joined(separator: "\n") ?? ""
            let uses = own.components(separatedBy: name).count - 1
            if uses <= 1 {
                report(.warning, "dead.code", file, index + 1, "私有成员 \(name) 只出现在声明处，可能已无人调用")
            }
        }
    }
}

// MARK: 测试覆盖

for path in sourceFiles {
    let file = relative(path)
    guard file.hasPrefix("Sources/FoveaCore/"), !file.hasSuffix("FoveaCore.swift") else { continue }
    let type = (file as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "")
    if !allTests.contains(type) {
        report(.info, "test.coverage", file, nil, "核心类型 \(type) 在测试里没有出现")
    }
}

// MARK: 结构一致性

if allSource.contains("NSVisualEffectView") {
    report(.warning, "design.legacy", "Sources", nil, "仍有 NSVisualEffectView，应统一到 NSGlassEffectView")
}
for legacy in ["bezelStyle = .rounded", "bezelStyle = .regularSquare"] where allSource.contains(legacy) {
    report(.warning, "design.legacy", "Sources", nil, "仍有旧按钮样式 \(legacy)")
}

// MARK: 输出

let order: [Severity] = [.error, .warning, .info]
print("Fovea 代码审计")
print("扫描 \(sourceFiles.count) 个源文件，\(testFiles.count) 个测试文件\n")

for severity in order {
    let group = findings.filter { $0.severity == severity }
    guard !group.isEmpty else { continue }
    print("── \(severity.rawValue) \(group.count) 条 ──")
    let byRule = Dictionary(grouping: group, by: \.rule)
    for rule in byRule.keys.sorted() {
        let items = byRule[rule]!
        print("\n  [\(rule)] \(items.count) 处")
        for item in items.prefix(12) {
            let location = item.line.map { "\(item.file):\($0)" } ?? item.file
            print("    \(location)  \(item.message)")
        }
        if items.count > 12 { print("    …… 另有 \(items.count - 12) 处") }
    }
    print("")
}

let errors = findings.filter { $0.severity == .error }.count
let warnings = findings.filter { $0.severity == .warning }.count
let infos = findings.filter { $0.severity == .info }.count
print("合计：错误 \(errors)，警告 \(warnings)，提示 \(infos)，已接受 \(acceptedCount)")

if strict && errors > 0 {
    print("\n严格模式下存在错误，退出码 1")
    exit(1)
}
