import AppKit
import FoveaCore

@MainActor
final class FilmstripView: NSScrollView {
    static let regularThumbnailSize = CGSize(width: 72, height: 64)
    /// 选中态保持同样的占位尺寸，只用描边和亮度表达，换图时整排不会反复重排。
    static let selectedThumbnailSize = regularThumbnailSize
    static let thumbnailDecodeMaxPixelSize: CGFloat = 192
    static let retainedItemRadius = 20
    static let maximumRetainedItemCount = retainedItemRadius * 2 + 1

    /// 缩略图的圆角，和玻璃面板里的次级控件取同一档。
    static let thumbnailCornerRadius = GlassMetrics.controlCornerRadius

    /// 当前这张周围那圈描边的粗细。
    static let selectionRingWidth: CGFloat = 2

    /// 非当前缩略图压暗一档，让当前这张自己亮出来。
    static let unselectedThumbnailAlpha: CGFloat = 0.55

    /// 指针压上来时抬到这一档，作为可以点的提示。
    static let hoveredThumbnailAlpha: CGFloat = 0.85

    /// 亮度变化的时长。比滑动短一些，跟手不拖沓。
    static let thumbnailFadeDuration: TimeInterval = 0.1

    /// 描边在旧缩略图和新缩略图之间交叉收放，避免选中框硬跳。
    static let selectionRingTransitionDuration: TimeInterval = 0.18

    private final class FilmstripButton: NSButton {
        /// 同一个 URL 的条目会在扫描前后带不同的修改时间和大小，
        /// 复用按钮时把这份数据换成新的，选中判定和回调都按最新的走。
        var item: ImageItem
        var thumbnailRequest: ThumbnailRequest?
        private(set) var isCurrent = false
        private var widthConstraint: NSLayoutConstraint!
        private var heightConstraint: NSLayoutConstraint!

        init(item: ImageItem, isSelected: Bool) {
            self.item = item
            super.init(frame: .zero)
            title = item.url.deletingPathExtension().lastPathComponent
            configure(isSelected: isSelected)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            nil
        }

        deinit {
            thumbnailRequest?.cancel()
        }

        func configure(isSelected: Bool) {
            if widthConstraint == nil {
                let thumbnailSize = FilmstripView.regularThumbnailSize
                widthConstraint = widthAnchor.constraint(equalToConstant: thumbnailSize.width)
                heightConstraint = heightAnchor.constraint(equalToConstant: thumbnailSize.height)
                widthConstraint.isActive = true
                heightConstraint.isActive = true
            } else if isCurrent == isSelected {
                // 选中态没变就什么都不用做。
                return
            }
            isCurrent = isSelected
            refreshSelectionAppearance()
        }

        /// 缩略图先按格子的宽高比居中裁一刀再放进去，铺满整格。
        ///
        /// 横幅照片按比例缩进方格里，上下会剩两条空带，一排看下来像是没加载完。
        /// 裁切只是取原图的一个子区域，不重新采样，代价可以忽略。
        func setThumbnail(_ thumbnail: NSImage) {
            guard let sourceThumbnail = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                image = thumbnail
                return
            }
            contentTintColor = nil
            let target = FilmstripView.regularThumbnailSize
            imageScaling = .scaleProportionallyUpOrDown
            image = NSImage(
                cgImage: FilmstripView.centerCropped(
                    sourceThumbnail,
                    toAspectRatio: target.width / target.height
                ),
                size: target
            )
        }

        /// 解不出来的那张给一个居中的占位符号，这时候不该裁切也不该铺满。
        func setFallback(_ fallback: NSImage?) {
            imageScaling = .scaleProportionallyDown
            image = fallback
            contentTintColor = .tertiaryLabelColor
        }

        /// 选中态用一圈强调色描边表示，不再靠系统 bezel 画一块底板。
        private func refreshSelectionAppearance() {
            wantsLayer = true
            layer?.cornerRadius = FilmstripView.thumbnailCornerRadius
            layer?.masksToBounds = true
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer?.borderColor = NSColor.controlAccentColor.cgColor
            }
            let targetBorderWidth = isCurrent ? FilmstripView.selectionRingWidth : 0
            let currentBorderWidth = layer?.presentation()?.borderWidth ?? layer?.borderWidth ?? 0
            layer?.borderWidth = targetBorderWidth
            if window != nil, abs(currentBorderWidth - targetBorderWidth) > 0.01 {
                let ringAnimation = CABasicAnimation(keyPath: "borderWidth")
                ringAnimation.fromValue = currentBorderWidth
                ringAnimation.toValue = targetBorderWidth
                ringAnimation.duration = FilmstripView.selectionRingTransitionDuration
                ringAnimation.timingFunction = Motion.navigation
                layer?.add(ringAnimation, forKey: "filmstrip.selectionRing")
            }
            let targetAlpha = FilmstripView.thumbnailAlpha(isSelected: isCurrent, isHovered: isHovered)
            // 亮度变化淡过去，选中和悬停都不再是硬跳。没上屏时直接落值。
            guard window != nil, abs(alphaValue - targetAlpha) > 0.001 else {
                alphaValue = targetAlpha
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = FilmstripView.thumbnailFadeDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = targetAlpha
            }
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            refreshSelectionAppearance()
        }

        // 去掉 bezel 之后按钮不再有系统提供的悬停反馈，指针压上来时抬一档亮度补上。
        private var isHovered = false
        private var hoverTrackingArea: NSTrackingArea?

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
            isHovered = true
            refreshSelectionAppearance()
            super.mouseEntered(with: event)
        }

        override func mouseExited(with event: NSEvent) {
            isHovered = false
            refreshSelectionAppearance()
            super.mouseExited(with: event)
        }

        func setHoveredForTesting(_ hovered: Bool) {
            isHovered = hovered
            refreshSelectionAppearance()
        }
    }

    /// 当前这张全亮，指针压着的抬一档，其余压暗，一排看下去焦点只有一个。
    static func thumbnailAlpha(isSelected: Bool, isHovered: Bool) -> CGFloat {
        if isSelected { return 1 }
        return isHovered ? hoveredThumbnailAlpha : unselectedThumbnailAlpha
    }

    /// 按目标宽高比从中心裁出最大的一块。
    static func centerCropped(_ image: CGImage, toAspectRatio aspectRatio: CGFloat) -> CGImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        guard width > 0, height > 0, aspectRatio > 0 else { return image }

        var cropWidth = width
        var cropHeight = height
        if width / height > aspectRatio {
            cropWidth = height * aspectRatio
        } else {
            cropHeight = width / aspectRatio
        }
        let rect = CGRect(
            x: ((width - cropWidth) / 2).rounded(.down),
            y: ((height - cropHeight) / 2).rounded(.down),
            width: max(1, cropWidth.rounded(.down)),
            height: max(1, cropHeight.rounded(.down))
        )
        return image.cropping(to: rect) ?? image
    }

    private let stack = NSStackView()
    private let leadingSpacer = NSView()
    private let trailingSpacer = NSView()
    private let thumbnailProvider: ThumbnailProvider
    private var leadingSpacerWidthConstraint: NSLayoutConstraint!
    private var trailingSpacerWidthConstraint: NSLayoutConstraint!
    private weak var selectedButton: FilmstripButton?
    private var lastViewportWidth: CGFloat = -1
    private var isUpdatingCenteredLayout = false
    private var allItems: [ImageItem] = []
    private var retainedItems: [ImageItem] = []
    private var recenterLink: CADisplayLink?
    private var recenterTargetX: CGFloat?
    private var recenterVelocityX: CGFloat = 0
    private var lastRecenterTimestamp: CFTimeInterval?

    var onSelect: ((ImageItem) -> Void)?
    /// 横向滚动位置变化时回调，滑杆靠它跟随。
    var onScrollProgressChanged: ((CGFloat) -> Void)?

    /// 可滚动的总距离。内容没超出视口时为 0。
    private var scrollableWidth: CGFloat {
        max(0, (documentView?.frame.width ?? 0) - contentSize.width)
    }

    /// 当前横向滚动进度，0 是最左，1 是最右。内容不足一屏时恒为 0。
    var scrollProgress: CGFloat {
        get {
            let range = scrollableWidth
            guard range > 0 else { return 0 }
            return min(max(contentView.bounds.minX / range, 0), 1)
        }
        set {
            stopRecenterAnimation()
            let range = scrollableWidth
            guard range > 0 else { return }
            let clamped = min(max(newValue, 0), 1)
            contentView.scroll(to: CGPoint(x: clamped * range, y: contentView.bounds.minY))
            reflectScrolledClipView(contentView)
        }
    }

    /// 内容是否长到需要滑杆。只有一屏放不下时滑杆才有意义。
    var isScrollable: Bool { scrollableWidth > 1 }

    init(thumbnailProvider: ThumbnailProvider = ThumbnailProvider(maxPixelSize: thumbnailDecodeMaxPixelSize)) {
        self.thumbnailProvider = thumbnailProvider
        super.init(frame: .zero)
        hasHorizontalScroller = false
        hasVerticalScroller = false
        autohidesScrollers = true
        borderType = .noBorder
        drawsBackground = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        leadingSpacerWidthConstraint = leadingSpacer.widthAnchor.constraint(equalToConstant: 0)
        trailingSpacerWidthConstraint = trailingSpacer.widthAnchor.constraint(equalToConstant: 0)
        leadingSpacerWidthConstraint.isActive = true
        trailingSpacerWidthConstraint.isActive = true
        stack.addArrangedSubview(leadingSpacer)
        stack.addArrangedSubview(trailingSpacer)
        documentView = stack

        // 用滚轮或触控板滑动胶卷条时，滑杆要跟着走。
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewBoundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: contentView
        )
    }

    @objc private func clipViewBoundsChanged() {
        onScrollProgressChanged?(scrollProgress)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window == nil else { return }
        recenterLink?.invalidate()
        recenterLink = nil
        stopRecenterAnimation()
    }

    override func scrollWheel(with event: NSEvent) {
        stopRecenterAnimation()
        super.scrollWheel(with: event)
    }

    func apply(items: [ImageItem], current: ImageItem?, animated: Bool = false) {
        let contentChanged = items != allItems
        allItems = items
        guard let current,
              let currentIndex = items.firstIndex(where: { $0.id == current.id }) else {
            if !retainedItems.isEmpty || selectedButton != nil {
                rebuild(items: [], current: nil)
            } else {
                contentView.scroll(to: .zero)
                reflectScrolledClipView(contentView)
            }
            return
        }

        if contentChanged || !retainedItems.contains(where: { $0.id == current.id }) {
            rebuild(items: Self.retainedWindow(in: items, centeredAt: currentIndex), current: current)
        } else {
            updateSelection(current: current)
            // 选择变化不再改变任何格子的尺寸，文档几何保持不动，直接更新滚动位置。
            centerSelectedThumbnail(animated: animated)
        }
    }

    /// 重建保留窗口里的按钮。
    ///
    /// 还留在窗口里的条目沿用原来的按钮，已经解好的缩略图和正在跑的请求都不动。
    /// 打开一张图时导航状态会连发两次，先是只含当前项的临时列表，扫完目录再发
    /// 完整列表。整排推倒重来会把第一次已经开始的解码全部取消，当前这张还得
    /// 重新排队，排在它前面的二十来张解完才轮到它，看起来就是别的格子都有图，
    /// 唯独正中间放大的那格空着，过一阵才补上。
    private func rebuild(items: [ImageItem], current: ImageItem?) {
        var reusableButtons: [URL: FilmstripButton] = [:]
        for case let button as FilmstripButton in stack.arrangedSubviews {
            reusableButtons[button.item.id] = button
        }
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0) }

        retainedItems = items
        selectedButton = nil
        lastViewportWidth = -1
        stack.addArrangedSubview(leadingSpacer)

        var pendingLoads: [FilmstripButton] = []
        for item in items {
            let isSelected = item.id == current?.id
            let button: FilmstripButton
            if let reused = reusableButtons.removeValue(forKey: item.id) {
                button = reused
                button.item = item
                button.configure(isSelected: isSelected)
            } else {
                button = makeButton(item: item, isSelected: isSelected)
                pendingLoads.append(button)
            }
            stack.addArrangedSubview(button)
            if isSelected {
                selectedButton = button
            }
        }

        // 掉出窗口的按钮连同还没解完的请求一起丢掉。
        for button in reusableButtons.values {
            button.thumbnailRequest?.cancel()
            button.removeFromSuperview()
        }

        stack.addArrangedSubview(trailingSpacer)

        // 当前这张先排，别的按加载顺序跟上。
        if let selectedButton, pendingLoads.contains(where: { $0 === selectedButton }) {
            loadThumbnail(for: selectedButton.item, into: selectedButton, priority: .high)
        }
        for button in pendingLoads where button !== selectedButton {
            loadThumbnail(for: button.item, into: button)
        }

        updateCenteredLayout(force: true)
    }

    private func makeButton(item: ImageItem, isSelected: Bool) -> FilmstripButton {
        let button = FilmstripButton(item: item, isSelected: isSelected)
        // 不要系统 bezel。它会在缩略图后面铺一块底板，横幅照片按比例缩进去
        // 就在上下露出两条亮带。这里改成图片自己铺满圆角方格。
        button.isBordered = false
        button.bezelStyle = .shadowlessSquare
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyUpOrDown
        button.toolTip = item.url.lastPathComponent
        button.setButtonType(.momentaryPushIn)
        button.target = self
        button.action = #selector(selectItem(_:))
        return button
    }

    private func updateSelection(current: ImageItem) {
        selectedButton = nil
        for case let button as FilmstripButton in stack.arrangedSubviews {
            let isSelected = button.item.id == current.id
            button.configure(isSelected: isSelected)
            if isSelected {
                selectedButton = button
            }
        }
    }

    override func layout() {
        super.layout()
        updateCenteredLayout()
    }

    #if DEBUG
    func debugButtons() -> [NSButton] {
        stack.arrangedSubviews.compactMap { $0 as? NSButton }
    }

    func performDebugSelection(_ button: NSButton) {
        selectItem(button)
    }

    func debugSelectedCenterInViewport() -> CGFloat? {
        selectedButton?.frame.midX
    }

    func debugSelectedTitle() -> String? { selectedButton?.title }

    func debugIsSelected(_ button: NSButton) -> Bool {
        (button as? FilmstripButton)?.isCurrent ?? false
    }

    func debugSetHovered(_ button: NSButton, _ hovered: Bool) {
        (button as? FilmstripButton)?.setHoveredForTesting(hovered)
    }

    func debugLeadingSpacerWidth() -> CGFloat { leadingSpacer.frame.width }
    func debugTrailingSpacerWidth() -> CGFloat { trailingSpacer.frame.width }
    #endif

    static func thumbnailSize(isSelected: Bool) -> CGSize {
        isSelected ? selectedThumbnailSize : regularThumbnailSize
    }

    static func retainedWindow(in items: [ImageItem], centeredAt index: Int) -> [ImageItem] {
        guard items.indices.contains(index) else { return [] }
        let lowerBound = max(items.startIndex, index - retainedItemRadius)
        let upperBound = min(items.endIndex, index + retainedItemRadius + 1)
        return Array(items[lowerBound..<upperBound])
    }

    @objc private func selectItem(_ sender: NSButton) {
        guard let button = sender as? FilmstripButton else { return }
        onSelect?(button.item)
    }

    private func updateCenteredLayout(force: Bool = false, animated: Bool = false) {
        guard !isUpdatingCenteredLayout else { return }
        let viewportWidth = contentView.bounds.width
        let viewportChanged = abs(viewportWidth - lastViewportWidth) > 0.5
        guard viewportWidth > 0, force || viewportChanged else { return }

        isUpdatingCenteredLayout = true
        defer { isUpdatingCenteredLayout = false }
        lastViewportWidth = viewportWidth

        guard selectedButton != nil else {
            leadingSpacerWidthConstraint.constant = 0
            trailingSpacerWidthConstraint.constant = 0
            resizeDocumentToFit()
            contentView.scroll(to: .zero)
            reflectScrolledClipView(contentView)
            return
        }

        // 留白只跟视口宽度有关，翻页时它不变，不用每次重算。
        // 选中那格的宽度是定值，也不必先清零量一遍再摆回去。
        if viewportChanged {
            let spacerWidth = max(0, (viewportWidth - Self.selectedThumbnailSize.width) / 2 - stack.spacing)
            leadingSpacerWidthConstraint.constant = spacerWidth
            trailingSpacerWidthConstraint.constant = spacerWidth
        }
        resizeDocumentToFit()
        centerSelectedThumbnail(animated: animated)
    }

    private func resizeDocumentToFit() {
        stack.layoutSubtreeIfNeeded()
        let fittingSize = stack.fittingSize
        // 容器尺寸没变就不重复走布局。
        guard abs(stack.frame.width - fittingSize.width) > 0.5
            || abs(stack.frame.height - fittingSize.height) > 0.5 else { return }
        stack.frame.size = fittingSize
        stack.needsLayout = true
        stack.layoutSubtreeIfNeeded()
    }

    private func centerSelectedThumbnail(animated: Bool = false) {
        guard let selectedButton else { return }
        let selectedCenter = selectedButton.frame.midX
        let maximumOrigin = max(0, stack.frame.width - contentView.bounds.width)
        let originX = min(max(0, selectedCenter - contentView.bounds.width / 2), maximumOrigin)
        let target = NSPoint(x: originX, y: 0)

        guard animated, Motion.canAnimate(self), abs(contentView.bounds.minX - originX) > 0.1 else {
            finishRecenter(at: target)
            return
        }

        recenterTargetX = originX
        if recenterLink == nil {
            let link = displayLink(target: self, selector: #selector(stepRecenterAnimation))
            link.add(to: .main, forMode: .common)
            recenterLink = link
        }
        recenterLink?.isPaused = false
    }

    /// 胶片条采用临界阻尼附近的连续弹簧。连续翻页只改终点并保留当前速度，
    /// 缩略图不会在每次按键时停住再重新起步。
    static let recenterSpringStiffness: CGFloat = 400
    static let recenterSpringDamping: CGFloat = 38

    @objc private func stepRecenterAnimation() {
        guard let targetX = recenterTargetX else {
            recenterLink?.isPaused = true
            return
        }
        let now = CACurrentMediaTime()
        let deltaTime = min(max(now - (lastRecenterTimestamp ?? now - 1 / 60), 1 / 240), 1 / 30)
        lastRecenterTimestamp = now
        let next = Self.recenterSpringStep(
            position: contentView.bounds.minX,
            velocity: recenterVelocityX,
            target: targetX,
            deltaTime: CGFloat(deltaTime)
        )
        recenterVelocityX = next.velocity
        contentView.scroll(to: CGPoint(x: next.position, y: 0))
        reflectScrolledClipView(contentView)

        if abs(next.position - targetX) < 0.12, abs(next.velocity) < 2 {
            finishRecenter(at: CGPoint(x: targetX, y: 0))
        }
    }

    static func recenterSpringStep(
        position: CGFloat,
        velocity: CGFloat,
        target: CGFloat,
        deltaTime: CGFloat
    ) -> (position: CGFloat, velocity: CGFloat) {
        let displacement = position - target
        let acceleration = -recenterSpringStiffness * displacement - recenterSpringDamping * velocity
        let nextVelocity = velocity + acceleration * deltaTime
        return (position + nextVelocity * deltaTime, nextVelocity)
    }

    private func finishRecenter(at target: CGPoint) {
        stopRecenterAnimation()
        contentView.scroll(to: target)
        reflectScrolledClipView(contentView)
    }

    private func stopRecenterAnimation() {
        recenterTargetX = nil
        recenterVelocityX = 0
        lastRecenterTimestamp = nil
        recenterLink?.isPaused = true
    }

    /// 解不出来的图给一个占位符号，空着一格看起来像是加载卡住了。
    private static var thumbnailFallbackImage: NSImage? {
        NSImage(systemSymbolName: "photo", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 20, weight: .light))
    }

    private func loadThumbnail(
        for item: ImageItem,
        into button: FilmstripButton,
        priority: ThumbnailPriority = .normal
    ) {
        button.thumbnailRequest = thumbnailProvider.loadThumbnail(for: item, priority: priority) { [weak button] result in
            Task { @MainActor [weak button] in
                guard let button, button.item.id == item.id else { return }
                switch result {
                case .success(let thumbnail):
                    button.setThumbnail(thumbnail)
                case .failure:
                    button.setFallback(Self.thumbnailFallbackImage)
                }
            }
        }
    }
}
