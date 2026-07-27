import AppKit

/// 首次使用时浮在图片上的操作提示条。
///
/// 外壳是玻璃面板，内容直接挂进玻璃里。提示条本身不再画背景色。
final class UsageHintView: NSView {
    var onDismiss: (() -> Void)?
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let dismissButton = NSButton()
    private let panel = GlassPanelView(cornerRadius: GlassMetrics.controlCornerRadius)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        panel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel)

        messageLabel.stringValue = AppStrings.text("usageHint.message")
        messageLabel.font = .systemFont(ofSize: 12, weight: .medium)
        messageLabel.maximumNumberOfLines = 3
        dismissButton.title = AppStrings.text("usageHint.dismiss")
        // 提示条已经是玻璃，按钮再叠一层玻璃会糊成一团，这里保持无边框。
        dismissButton.bezelStyle = .inline
        dismissButton.target = self
        dismissButton.action = #selector(dismiss(_:))
        dismissButton.setAccessibilityLabel(dismissButton.title)
        let stack = NSStackView(views: [messageLabel, dismissButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: trailingAnchor),
            panel.topAnchor.constraint(equalTo: topAnchor),
            panel.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: panel.contentView.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: panel.contentView.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: panel.contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: panel.contentView.bottomAnchor, constant: -10),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 430)
        ])
        setAccessibilityRole(.group)
        setAccessibilityLabel(AppStrings.text("usageHint.accessibilityLabel"))
    }

    @objc private func dismiss(_ sender: Any?) { onDismiss?() }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
