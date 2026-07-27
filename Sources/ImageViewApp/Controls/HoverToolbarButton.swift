import AppKit

@MainActor
final class HoverToolbarButton: NSButton {
    static let controlSize = NSSize(width: 24, height: 24)

    static func acceptsMouseClick(clickCount: Int) -> Bool {
        clickCount == 1
    }

    /// 开关型按钮打开时用强调色着色，和菜单里的勾选状态对应。
    var isOnState = false {
        didSet {
            guard isOnState != oldValue else { return }
            updateAppearance()
            // 开关翻面时图标鼓一下。着色的变化很轻，单靠颜色不容易察觉到
            // 这一下按下去到底有没有生效。
            Motion.pop(self, scale: 1.18, duration: 0.28)
        }
    }

    private var isHovered = false
    private var isPressed = false
    private var focusedForTesting: Bool?
    private var hoverTrackingArea: NSTrackingArea?
    private(set) var testingAppearanceRefreshCount = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override var intrinsicContentSize: NSSize { Self.controlSize }

    override var acceptsFirstResponder: Bool { true }

    override var isEnabled: Bool {
        didSet {
            if !isEnabled {
                isHovered = false
                isPressed = false
            }
            updateAppearance()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInActiveApp, .inVisibleRect, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = isEnabled
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        guard Self.acceptsMouseClick(clickCount: event.clickCount) else { return }
        super.mouseDown(with: event)
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        isPressed = flag && isEnabled
        updateAppearance()
        animatePressFeedback(pressed: isPressed)
    }

    /// 按下时轻微缩一下再弹回，给点击一个可感知的回应。
    ///
    /// 系统的玻璃 bezel 自带这个反馈，无边框按钮没有，所以手工补上。
    /// 缩放绕视图中心做。AppKit 每次改 frame 都会把图层的 anchorPoint 按回
    /// 原点，改 anchorPoint 撑不过下一次布局，中心点只能写进变换里。
    private func animatePressFeedback(pressed: Bool) {
        Motion.setScale(
            self,
            pressed ? Self.pressedScale : 1,
            duration: pressed ? 0.09 : 0.16,
            timing: pressed ? Motion.entrance : Motion.springy
        )
    }

    static let pressedScale: CGFloat = 0.88

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        needsDisplay = true
        return becameFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let resignedFirstResponder = super.resignFirstResponder()
        needsDisplay = true
        return resignedFirstResponder
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        testingAppearanceRefreshCount += 1
        updateAppearance()
    }

    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        guard testingShowsFocus else { return }
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 5, yRadius: 5).fill()
    }

    var testingShowsHover: Bool { isEnabled && isHovered && !isPressed }
    var testingShowsPressed: Bool { isEnabled && isPressed }
    var testingShowsFocus: Bool {
        focusedForTesting ?? (window?.firstResponder === self)
    }

    func setHoveredForTesting(_ hovered: Bool) {
        isHovered = hovered && isEnabled
        updateAppearance()
    }

    func setFocusedForTesting(_ focused: Bool) {
        focusedForTesting = focused
        needsDisplay = true
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.controlSize.width),
            heightAnchor.constraint(equalToConstant: Self.controlSize.height)
        ])
        bezelStyle = .toolbar
        isBordered = false
        imagePosition = .imageOnly
        focusRingType = .default
        wantsLayer = true
        layer?.cornerRadius = GlassMetrics.controlCornerRadius
        updateAppearance()
    }

    /// 按钮坐在玻璃标题栏里，再叠一层玻璃会互相打架，
    /// 所以状态只用一层很淡的强调色，和系统工具栏按钮的行为一致。
    private func updateAppearance() {
        let backgroundColor: NSColor?
        if testingShowsPressed {
            backgroundColor = NSColor.controlAccentColor.withAlphaComponent(GlassMetrics.pressedTintAlpha)
        } else if testingShowsHover {
            backgroundColor = NSColor.controlAccentColor.withAlphaComponent(GlassMetrics.hoverTintAlpha)
        } else {
            backgroundColor = nil
        }
        applyBackgroundTint(backgroundColor?.cgColor)
        if !isEnabled {
            contentTintColor = .secondaryLabelColor
        } else {
            contentTintColor = isOnState ? .controlAccentColor : .labelColor
        }
        needsDisplay = true
    }

    /// 悬停的那层淡色渐变过去，指针扫过一排按钮时不会闪成一串硬块。
    ///
    /// 模型值当场写好，读到的始终是目标色，动画只负责这段过渡怎么走。
    private func applyBackgroundTint(_ color: CGColor?) {
        guard let layer else { return }
        if Motion.canAnimate(self), layer.backgroundColor != color {
            let animation = CABasicAnimation(keyPath: "backgroundColor")
            animation.fromValue = layer.presentation()?.backgroundColor ?? layer.backgroundColor
            animation.toValue = color
            animation.duration = Motion.quick
            animation.timingFunction = Motion.entrance
            layer.add(animation, forKey: "motion.tint")
        }
        layer.backgroundColor = color
    }
}
