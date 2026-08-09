import AppKit

/// macOS 26 的玻璃面板。
///
/// 内容加到 `contentView` 上，玻璃负责材质、圆角和背景折射。窗口 chrome、
/// 悬浮控件和信息面板都用它，保证整个应用只有一套材质来源。
@MainActor
final class GlassPanelView: NSView {
    let contentView = NSView()
    private let glass = NSGlassEffectView()

    var cornerRadius: CGFloat {
        get { glass.cornerRadius }
        set { glass.cornerRadius = newValue }
    }

    var glassStyle: NSGlassEffectView.Style {
        get { glass.style }
        set { glass.style = newValue }
    }

    var tintColor: NSColor? {
        get { glass.tintColor }
        set { glass.tintColor = newValue }
    }

    init(cornerRadius: CGFloat = 0, style: NSGlassEffectView.Style = .regular) {
        super.init(frame: .zero)
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.cornerRadius = cornerRadius
        glass.style = style
        contentView.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView = contentView
        addSubview(glass)

        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: glass.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: glass.bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 面板本身不吃事件，命中测试交给内容。窗口 chrome 需要这个来保持拖动和双击。
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === glass ? self : hit
    }
}
