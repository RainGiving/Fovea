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

    func refreshAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let backgroundColor: NSColor
            if isPressed {
                backgroundColor = .controlAccentColor.withAlphaComponent(0.24)
            } else if isHovered {
                backgroundColor = .controlAccentColor.withAlphaComponent(0.15)
            } else {
                backgroundColor = PageNavigationOverlayView.backgroundColor.withAlphaComponent(0.92)
            }
            layer?.backgroundColor = backgroundColor.cgColor
            contentTintColor = isEnabled ? .labelColor : .tertiaryLabelColor
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
    static var backgroundColor: NSColor { .windowBackgroundColor }
    static var borderColor: NSColor { .separatorColor }

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

    static func borderWidth(forBackingScaleFactor scaleFactor: CGFloat) -> CGFloat {
        1 / max(1, scaleFactor)
    }

    func update(previousEnabled: Bool, nextEnabled: Bool) {
        previousButton.isEnabled = previousEnabled
        nextButton.isEnabled = nextEnabled
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        for button in [previousButton, nextButton] where !button.isHidden {
            // NSView.hitTest expects a point in the receiver's superview
            // coordinate system. Both buttons are direct children, so the
            // overlay point must be passed through unchanged.
            if let hitView = button.hitTest(point) { return hitView }
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
        updateButtonLayers()
        updateTrackingAreas()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateButtonLayers()
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
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.wantsLayer = true
        button.target = self
        button.action = action
        button.toolTip = description
        button.focusRingType = .default
    }

    private func updateButtonLayers() {
        let scale = window?.backingScaleFactor ?? layer?.contentsScale ?? 1
        for button in [previousButton, nextButton] {
            button.layer?.cornerRadius = 14
            button.layer?.borderWidth = Self.borderWidth(forBackingScaleFactor: scale)
            button.layer?.borderColor = Self.borderColor.cgColor
            button.layer?.shadowColor = NSColor.black.withAlphaComponent(0.2).cgColor
            button.layer?.shadowOpacity = 0.34
            button.layer?.shadowRadius = 7
            button.layer?.shadowOffset = CGSize(width: 0, height: -2)
            button.refreshAppearance()
        }
    }

    #if DEBUG
    var debugPreviousButton: PageNavigationButton { previousButton }
    var debugNextButton: PageNavigationButton { nextButton }
    func performDebugPrevious() { showPrevious() }
    func performDebugNext() { showNext() }
    #endif
}
