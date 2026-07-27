import AppKit

@MainActor
final class PageNavigationButton: NSButton {
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false

    override var acceptsFirstResponder: Bool { true }

    override var isEnabled: Bool {
        didSet {
            if !isEnabled {
                isHovered = false
                isPressed = false
            }
            refreshAppearance()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = isEnabled
        refreshAppearance()
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        refreshAppearance()
        super.mouseExited(with: event)
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        isPressed = flag && isEnabled
        refreshAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    /// 玻璃 bezel 自己负责材质和按压反馈，这里只调符号的颜色：
    /// 悬停时提到强调色，禁用时压到三级灰。
    func refreshAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if !isEnabled {
                contentTintColor = .tertiaryLabelColor
            } else if isPressed || isHovered {
                contentTintColor = .controlAccentColor
            } else {
                contentTintColor = .labelColor
            }
        }
        needsDisplay = true
    }

    var testingShowsHover: Bool { isHovered && isEnabled && !isPressed }
    var testingShowsPressed: Bool { isPressed && isEnabled }

    func setHoveredForTesting(_ hovered: Bool) {
        isHovered = hovered && isEnabled
        refreshAppearance()
    }
}

@MainActor
final class PageNavigationOverlayView: NSView {
    static let controlSize = CGSize(width: 44, height: 64)

    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?

    private let previousButton = PageNavigationButton()
    private let nextButton = PageNavigationButton()
    private var pointerTrackingAreas: [NSTrackingArea] = []

    override init(frame frameRect: NSRect = .zero) {
        super.init(frame: frameRect)
        wantsLayer = true
        configure(
            previousButton,
            symbol: "chevron.left",
            description: AppStrings.text("menu.view.previousImage"),
            action: #selector(showPrevious)
        )
        configure(
            nextButton,
            symbol: "chevron.right",
            description: AppStrings.text("menu.view.nextImage"),
            action: #selector(showNext)
        )
        addSubview(previousButton)
        addSubview(nextButton)

        NSLayoutConstraint.activate([
            previousButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            previousButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: Self.controlSize.width),
            previousButton.heightAnchor.constraint(equalToConstant: Self.controlSize.height),
            nextButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            nextButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: Self.controlSize.width),
            nextButton.heightAnchor.constraint(equalToConstant: Self.controlSize.height)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    /// 指针此刻是否真的压在某颗按钮上。
    ///
    /// 不能只靠 mouseEntered / mouseExited 记状态。控件隐藏期间指针移进来不会
    /// 产生进入事件，等控件淡入时指针已经停在按钮上，程序却仍以为指针在别处，
    /// 于是自动隐藏照常触发，用户点下去就落空。这里直接查当前鼠标位置兜底。
    var isPointerOverControls: Bool {
        guard let window, !isHidden else { return false }
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let local = convert(windowPoint, from: nil)
        return [previousButton, nextButton].contains { !$0.isHidden && $0.frame.contains(local) }
    }

    func update(previousEnabled: Bool, nextEnabled: Bool) {
        previousButton.isEnabled = previousEnabled
        nextButton.isEnabled = nextEnabled
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // 传进来的点在父视图坐标系里，按钮的 frame 在本视图坐标系里，
        // 中间这次换算不能省。少了它，可点区域会整体偏移浮层原点那么多，
        // 正好是下边栏的高度，指针压在按钮上半截时点下去落空，
        // 往下挪一点又能点中，看起来就是按钮偶发失灵。
        let local = superview.map { convert(point, from: $0) } ?? point
        for button in [previousButton, nextButton] where !button.isHidden {
            if let hitView = button.hitTest(local) { return hitView }
        }
        return nil
    }

    override func updateTrackingAreas() {
        pointerTrackingAreas.forEach(removeTrackingArea)
        pointerTrackingAreas = [previousButton, nextButton].map { button in
            let rect = convert(button.bounds, from: button)
            let trackingArea = NSTrackingArea(
                rect: rect,
                options: [.activeInKeyWindow, .mouseEnteredAndExited],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
            return trackingArea
        }
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerEntered?()
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        onPointerExited?()
        super.mouseExited(with: event)
    }

    override func layout() {
        super.layout()
        updateTrackingAreas()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        for button in [previousButton, nextButton] {
            button.refreshAppearance()
        }
    }

    @objc private func showPrevious() {
        onPrevious?()
    }

    @objc private func showNext() {
        onNext?()
    }

    private func configure(
        _ button: NSButton,
        symbol: String,
        description: String,
        action: Selector
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        button.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: description
        )?.withSymbolConfiguration(symbolConfiguration)
        button.imageScaling = .scaleProportionallyDown
        // 玻璃 bezel 自带材质、圆角和阴影，不再手工画图层。
        button.bezelStyle = .glass
        button.isBordered = true
        button.wantsLayer = true
        button.target = self
        button.action = action
        button.toolTip = description
        button.focusRingType = .default
        if let cell = button.cell as? NSButtonCell {
            cell.isBordered = true
        }
        // 符号颜色由 refreshAppearance 决定，构建时先定一次，
        // 否则要等到第一次悬停才会着色。
        (button as? PageNavigationButton)?.refreshAppearance()
    }

    #if DEBUG
    var debugPreviousButton: PageNavigationButton { previousButton }
    var debugNextButton: PageNavigationButton { nextButton }
    func performDebugPrevious() { showPrevious() }
    func performDebugNext() { showNext() }
    #endif
}
