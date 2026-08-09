import AppKit
import FoveaCore
import SwiftUI

struct InspectorView: View {
    let metadata: ImageMetadata?
    var onClose: () -> Void = {}

    /// 侧栏保留圆角和窗口环境底图之间的间距。
    var cornerRadius: CGFloat { GlassMetrics.panelCornerRadius }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(AppStrings.text("inspector.title"))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .help(AppStrings.text("inspector.close"))
                    .accessibilityLabel(AppStrings.text("inspector.close"))
                }

                if let metadata {
                    copyableRow(AppStrings.text("inspector.file"), metadata.url.lastPathComponent)
                    copyableRow(AppStrings.text("inspector.path"), metadata.url.path)
                    row(AppStrings.text("inspector.format"), metadata.format.displayName)
                    copyableRow(AppStrings.text("inspector.pixels"), "\(metadata.pixelWidth) x \(metadata.pixelHeight)")
                    row(AppStrings.text("inspector.size"), Self.fileSizeText(metadata.fileSize))
                    row(AppStrings.text("inspector.modified"), Self.dateText(metadata.modifiedAt))
                    if let capturedAt = metadata.capturedAt {
                        copyableRow(AppStrings.text("inspector.captured"), Self.dateText(capturedAt))
                    }
                    if let camera = Self.cameraText(metadata) {
                        row(AppStrings.text("inspector.camera"), camera)
                    }
                    if let colorSpace = metadata.colorSpace { row(AppStrings.text("inspector.colorSpace"), colorSpace) }
                    if let colorProfile = metadata.colorProfile { row(AppStrings.text("inspector.colorProfile"), colorProfile) }
                    if let bitDepth = metadata.bitDepth { row(AppStrings.text("inspector.bitDepth"), "\(bitDepth)-bit") }
                    if let orientation = metadata.orientation { row(AppStrings.text("inspector.orientation"), "\(orientation)") }
                    if let exposureTime = metadata.exposureTime {
                        row(AppStrings.text("inspector.exposureTime"), Self.exposureTimeText(exposureTime))
                    }
                    if let aperture = metadata.aperture {
                        row(AppStrings.text("inspector.aperture"), String(format: "f/%.1f", aperture))
                    }
                    if let isoSpeed = metadata.isoSpeed {
                        row(AppStrings.text("inspector.isoSpeed"), "ISO \(isoSpeed)")
                    }
                    if let focalLength = metadata.focalLength {
                        row(AppStrings.text("inspector.focalLength"), String(format: "%.1f mm", focalLength))
                    }
                    Button(AppStrings.text("inspector.reveal")) {
                        NSWorkspace.shared.activateFileViewerSelecting([metadata.url])
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                } else {
                    Text(AppStrings.text("inspector.noImage"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
        .frame(width: GlassMetrics.inspectorWidth, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }

    private func copyableRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            row(label, value)
            Spacer(minLength: 4)
            CopyButton(label: label, value: value)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12))
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    static func fileSizeText(_ bytes: Int64?) -> String {
        guard let bytes else { return AppStrings.text("inspector.unknown") }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func dateText(_ date: Date?) -> String {
        guard let date else { return AppStrings.text("inspector.unknown") }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func cameraText(_ metadata: ImageMetadata) -> String? {
        [metadata.cameraMake, metadata.cameraModel]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .nilIfEmpty
    }

    static func exposureTimeText(_ seconds: Double) -> String {
        guard seconds > 0 else { return AppStrings.text("inspector.unknown") }
        if seconds < 1 {
            return "1/\(Int((1 / seconds).rounded())) s"
        }
        return String(format: "%.2f s", seconds)
    }
}

/// 一行信息右侧的复制按钮。
///
/// 原来按下去只有系统那点极轻的按压效果，复制成没复制成全靠猜。现在图标换成
/// 对钩并着强调色，同时整颗按钮鼓一下，过一会儿再退回去。复制这种动作没有可见
/// 结果，反馈就得由按钮自己给足。
private struct CopyButton: View {
    let label: String
    let value: String

    /// 对钩停留多久。短了看不清，长了会让人以为按钮卡住。
    static let confirmationDuration: Duration = .milliseconds(1_200)

    @State private var didCopy = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            confirm()
        } label: {
            Image(systemName: didCopy ? "checkmark.circle.fill" : "doc.on.doc")
                .foregroundStyle(didCopy ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .scaleEffect(didCopy ? 1.18 : 1)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help(AppStrings.text(didCopy ? "inspector.copied" : "inspector.copy"))
        .accessibilityLabel("\(AppStrings.text("inspector.copy")) \(label)")
        .accessibilityValue(didCopy ? AppStrings.text("inspector.copied") : "")
    }

    private func confirm() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
            didCopy = true
        }
        Task {
            try? await Task.sleep(for: Self.confirmationDuration)
            withAnimation(.easeOut(duration: 0.2)) {
                didCopy = false
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// 格式的显示名由 SupportedImageFormat.displayName 提供，这里不再重复一份。
