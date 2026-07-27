import AppKit

/// 浮在图片上方的胶卷条容器。
///
/// 材质由玻璃负责。胶卷内容加到 `contentView` 上，才会被放进玻璃里。
/// 显示与否只看开关，所以这里不再跟踪指针。
@MainActor
final class FilmstripOverlayView: NSView {
    private let panel = GlassPanelView(cornerRadius: GlassMetrics.panelCornerRadius)

    /// 胶卷内容挂在这里，位于玻璃内部。
    var contentView: NSView { panel.contentView }

    override init(frame frameRect: NSRect = .zero) {
        super.init(frame: frameRect)
        wantsLayer = true
        panel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: trailingAnchor),
            panel.topAnchor.constraint(equalTo: topAnchor),
            panel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var cornerRadius: CGFloat {
        get { panel.cornerRadius }
        set { panel.cornerRadius = newValue }
    }

}
