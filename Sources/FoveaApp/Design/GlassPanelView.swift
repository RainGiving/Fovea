import AppKit

/// macOS 26 的玻璃面板。
///
/// 内容加到 `contentView` 上，玻璃负责材质、圆角和背景折射。
/// 信息面板和临时控件使用它，贴边 chrome 则与画布共用环境底图。
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

/// 贴边 chrome 直接叠在画布的环境底图上，只加一层渐变染色保证可读性。
@MainActor
final class AmbientChromeView: NSView {
    enum Edge {
        case top
        case bottom
    }

    let contentView = NSView()
    private let edge: Edge
    private let gradient = CAGradientLayer()

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
        wantsLayer = true
        gradient.actions = ["bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(gradient)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        refreshGradient()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        gradient.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshGradient()
    }

    private func refreshGradient() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let base = NSColor.windowBackgroundColor
            switch edge {
            case .top:
                gradient.startPoint = CGPoint(x: 0.5, y: 1)
                gradient.endPoint = CGPoint(x: 0.5, y: 0)
                gradient.colors = [
                    base.withAlphaComponent(0.58).cgColor,
                    base.withAlphaComponent(0.22).cgColor,
                    base.withAlphaComponent(0).cgColor
                ]
            case .bottom:
                gradient.startPoint = CGPoint(x: 0.5, y: 1)
                gradient.endPoint = CGPoint(x: 0.5, y: 0)
                gradient.colors = [
                    base.withAlphaComponent(0).cgColor,
                    base.withAlphaComponent(0.26).cgColor,
                    base.withAlphaComponent(0.62).cgColor
                ]
            }
            gradient.locations = [0, 0.42, 1]
        }
    }
}
