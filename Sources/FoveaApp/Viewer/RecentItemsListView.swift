import AppKit
import FoveaCore

/// 空状态里的「最近打开」列表。
///
/// 每一条是一整行：左边一张缩略图，右边是文件名和它所在的文件夹。整行都能点，
/// 指针扫过时整行亮起来。原来每个文件是一颗按文字宽度撑开的胶囊按钮，五条挤在
/// 一起宽窄不齐，也看不出哪一条是从哪个文件夹来的。
final class RecentItemsListView: NSView {
    var onOpen: ((URL) -> Void)?
    var onClear: (() -> Void)?

    /// 列表宽度固定。让每一行左对齐，行与行之间才有一条整齐的竖边。
    static let listWidth: CGFloat = 340

    /// 最多列出这么多条。再多就把空状态撑得比画面还长。
    static let maximumItemCount = 5

    private let headingLabel = NSTextField(labelWithString: "")
    private let clearButton = NSButton()
    private let rowStack = NSStackView()
    private let thumbnailProvider: ThumbnailProvider
    private var rows: [RecentItemRowView] = []

    init(
        preferredLanguages: [String] = Locale.preferredLanguages,
        thumbnailProvider: ThumbnailProvider = ThumbnailProvider(maxPixelSize: RecentItemRowView.thumbnailPixelSize)
    ) {
        self.thumbnailProvider = thumbnailProvider
        super.init(frame: .zero)

        headingLabel.stringValue = AppStrings.text("emptyState.recent", preferredLanguages: preferredLanguages)
        headingLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        headingLabel.textColor = .secondaryLabelColor

        clearButton.title = AppStrings.text("emptyState.clearRecent", preferredLanguages: preferredLanguages)
        clearButton.isBordered = false
        clearButton.font = .systemFont(ofSize: 11)
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.target = self
        clearButton.action = #selector(clear(_:))
        clearButton.setAccessibilityLabel(clearButton.title)

        // 标题靠左，清除靠右。中间那段空白交给 NSStackView 的分隔距离，
        // 不塞占位视图：裸 NSView 没有基线，按基线对齐的堆栈会算不出布局。
        let header = NSStackView(views: [headingLabel, clearButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .fill
        header.spacing = 8
        headingLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headingLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        clearButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        rowStack.orientation = .vertical
        rowStack.alignment = .leading
        rowStack.spacing = 2

        let stack = NSStackView(views: [header, rowStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: Self.listWidth),
            header.widthAnchor.constraint(equalTo: widthAnchor),
            rowStack.widthAnchor.constraint(equalTo: widthAnchor)
        ])
    }

    func apply(_ urls: [URL]) {
        let visible = Array(urls.prefix(Self.maximumItemCount))
        isHidden = visible.isEmpty

        for row in rows {
            rowStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        rows = visible.map { url in
            let row = RecentItemRowView(url: url, thumbnailProvider: thumbnailProvider)
            row.onOpen = { [weak self] url in self?.onOpen?(url) }
            rowStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rowStack.widthAnchor).isActive = true
            return row
        }
    }

    @objc private func clear(_ sender: Any?) {
        onClear?()
    }

    var itemCountForTesting: Int { rows.count }
    var itemTitlesForTesting: [String] { rows.map(\.titleForTesting) }
    var itemSubtitlesForTesting: [String] { rows.map(\.subtitleForTesting) }
    var headingTextForTesting: String { headingLabel.stringValue }
    var clearTitleForTesting: String { clearButton.title }

    func openItemForTesting(at index: Int) {
        guard rows.indices.contains(index) else { return }
        rows[index].openForTesting()
    }

    func performClearForTesting() {
        clear(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

/// 最近打开里的一行。
final class RecentItemRowView: NSView {
    var onOpen: ((URL) -> Void)?

    static let rowHeight: CGFloat = 40
    static let thumbnailSide: CGFloat = 28

    /// 缩略图按屏幕上的边长取两倍像素，视网膜屏上才不糊。
    static let thumbnailPixelSize: CGFloat = thumbnailSide * 2

    private let url: URL
    private let thumbnailView = RecentThumbnailView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private var isHovered = false
    private var isPressed = false
    private var hoverTrackingArea: NSTrackingArea?
    private var thumbnailRequest: ThumbnailRequest?

    init(url: URL, thumbnailProvider: ThumbnailProvider) {
        self.url = url
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = GlassMetrics.controlCornerRadius
        layer?.cornerCurve = .continuous

        titleLabel.stringValue = url.lastPathComponent
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        // 这类文件名大多是同一串前缀加一个时间戳，掐尾巴会把扩展名一起掐掉，
        // 从中间省略才能同时看见开头和后缀。
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.cell?.truncatesLastVisibleLine = true

        subtitleLabel.stringValue = Self.folderDescription(for: url)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail

        let labels = NSStackView(views: [titleLabel, subtitleLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1

        let content = NSStackView(views: [thumbnailView, labels])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.rowHeight),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            content.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        toolTip = url.path
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(url.lastPathComponent)

        thumbnailView.showsPlaceholder = true
        loadThumbnail(using: thumbnailProvider)
    }

    deinit {
        thumbnailRequest?.cancel()
    }

    /// 缩略图解不出来就退回系统给这个文件的图标，那一格不留空白。
    private func loadThumbnail(using provider: ThumbnailProvider) {
        guard let format = SupportedImageFormat(fileExtension: url.pathExtension) else {
            thumbnailView.showFileIcon(for: url)
            return
        }
        thumbnailRequest = provider.loadThumbnail(for: ImageItem(url: url, format: format)) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let image):
                self.thumbnailView.show(image)
            case .failure:
                self.thumbnailView.showFileIcon(for: self.url)
            }
        }
    }

    /// 副标题写它所在的文件夹，同名文件放在不同地方时才分得清。
    private static func folderDescription(for url: URL) -> String {
        let folder = url.deletingLastPathComponent()
        let name = FileManager.default.displayName(atPath: folder.path)
        return name.isEmpty ? folder.path : name
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
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        let wasPressed = isPressed
        isPressed = false
        updateAppearance()
        guard wasPressed, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onOpen?(url)
    }

    /// 整行是一块可点区域，着色也铺满整行，比一颗按文字宽度撑开的胶囊好读。
    private func updateAppearance() {
        let background: CGColor?
        if isPressed {
            background = NSColor.controlAccentColor.withAlphaComponent(GlassMetrics.pressedTintAlpha).cgColor
        } else if isHovered {
            background = NSColor.controlAccentColor.withAlphaComponent(GlassMetrics.hoverTintAlpha).cgColor
        } else {
            background = nil
        }
        guard let layer else { return }
        if Motion.canAnimate(self), layer.backgroundColor != background {
            let animation = CABasicAnimation(keyPath: "backgroundColor")
            animation.fromValue = layer.presentation()?.backgroundColor ?? layer.backgroundColor
            animation.toValue = background
            animation.duration = Motion.quick
            animation.timingFunction = Motion.entrance
            layer.add(animation, forKey: "motion.tint")
        }
        layer.backgroundColor = background
    }

    var titleForTesting: String { titleLabel.stringValue }
    var subtitleForTesting: String { subtitleLabel.stringValue }
    var showsHoverForTesting: Bool { isHovered && !isPressed }

    func setHoveredForTesting(_ hovered: Bool) {
        isHovered = hovered
        updateAppearance()
    }

    func openForTesting() {
        onOpen?(url)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

/// 一行左边那张方形缩略图。
///
/// 图按短边铺满再裁掉溢出的部分，一列缩略图才是同样大小的方块，
/// 不会因为原图长宽比不同而参差不齐。
final class RecentThumbnailView: NSView {
    var showsPlaceholder = false {
        didSet { needsDisplay = true }
    }

    private let imageLayer = CALayer()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        layer?.addSublayer(imageLayer)
        updateBackground()

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: RecentItemRowView.thumbnailSide),
            heightAnchor.constraint(equalToConstant: RecentItemRowView.thumbnailSide)
        ])
    }

    override func layout() {
        super.layout()
        // 图层几何不走隐式动画，换图和布局都当场落位。
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        imageLayer.contentsScale = window?.backingScaleFactor ?? 2
        CATransaction.commit()
    }

    func show(_ image: NSImage) {
        var rect = CGRect(origin: .zero, size: image.size)
        imageLayer.contents = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        showsPlaceholder = false
        updateBackground()
    }

    func showFileIcon(for url: URL) {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        var rect = CGRect(origin: .zero, size: icon.size)
        imageLayer.contents = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        // 系统图标本身带留白，铺满会把它拉变形，按原比例放进去就好。
        imageLayer.contentsGravity = .resizeAspect
        showsPlaceholder = false
        updateBackground()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    /// 图还没到时留一块很淡的底，位置先占住，不会等图到了才把整行撑开。
    private func updateBackground() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = imageLayer.contents == nil
                ? NSColor.quaternaryLabelColor.withAlphaComponent(0.35).cgColor
                : NSColor.clear.cgColor
        }
    }

    var hasImageForTesting: Bool { imageLayer.contents != nil }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
