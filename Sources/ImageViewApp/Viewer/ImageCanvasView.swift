import AppKit
import ImageViewCore

final class ImageCanvasView: NSView {
    static let trackpadNavigationThreshold: CGFloat = 80
    static let minimumManualPixelScale: CGFloat = 0.1
    static let maximumManualPixelScale: CGFloat = 12

    enum DisplayMode: Equatable {
        case fit
        case fitWidth
        case manual
    }

    private enum TrackpadScrollAxis {
        case horizontal
        case vertical
    }

    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onTransformChanged: ((CGFloat) -> Void)?
    var onContextMenuRequested: (() -> NSMenu?)?
    private var lastDragLocation: CGPoint?
    private var trackpadScrollAxis: TrackpadScrollAxis?
    private var accumulatedTrackpadDeltaX: CGFloat = 0
    private var didNavigateDuringTrackpadScroll = false
    private var isApplyingDisplayMode = false
    private var lastManualPixelScale: CGFloat?

    private(set) var displayMode: DisplayMode = .fit

    /// 图片和底色各占一层，缩放平移只改图层几何，不重画像素。
    ///
    /// 原来每帧都要把整张图重采样一遍画进 `draw(_:)`，一张四千万像素的照片
    /// 光是这一步就吃满一帧的预算，拖动和捏合都跟不上手。交给图层之后合成
    /// 由 GPU 做，主线程只写几个数。
    private let backdropLayer = CALayer()
    private let imageLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func configureLayers() {
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.backgroundColor = backgroundColor.cgColor

        // 几何改动一律不要隐式动画，否则拖动会拖出一条 0.25 秒的尾巴。
        //
        // 抑制写在图层自己的 actions 上，不包 CATransaction。翻页时
        // `playNavigationTransition` 会往画布图层挂一条推入过渡，显式的
        // begin/commit 有可能把内容先提交出去，过渡就没有前一帧可以推。
        let staticActions: [String: CAAction] = [
            "position": NSNull(),
            "bounds": NSNull(),
            "contents": NSNull(),
            "transform": NSNull(),
            "hidden": NSNull(),
            "opacity": NSNull()
        ]
        backdropLayer.actions = staticActions
        backdropLayer.contentsGravity = .resize
        backdropLayer.magnificationFilter = .linear
        backdropLayer.opacity = Float(Self.backdropAlpha)
        backdropLayer.isHidden = true

        imageLayer.actions = staticActions
        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .linear
        imageLayer.minificationFilter = .trilinear
        imageLayer.isHidden = true

        layer?.addSublayer(backdropLayer)
        layer?.addSublayer(imageLayer)
        updateLayerContentsScale()
    }

    var backgroundColor: NSColor = .black {
        didSet {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer?.backgroundColor = backgroundColor.cgColor
            }
        }
    }

    var image: DecodedImage? {
        didSet {
            currentAnimationFrameIndex = 0
            configureAnimation()
            rebuildBackdrop()
            if displayMode == .fitWidth { zoomToFitWidth() }
            refreshLayers()
            onTransformChanged?(scale)
        }
    }

    /// 玻璃 chrome 压在画布上，底下得有东西才折射得出来。
    ///
    /// 把当前图片缩成很小一张缓存下来，绘制时再放大铺满整个视图，
    /// 放大过程本身就把它糊成一层柔和的底色。图片仍然完整画在上面，
    /// 留白区域拿到的是这张图自己的颜色，而不是一块死板的灰。
    private var backdropImage: CGImage?

    /// 采样边长。取这么小是为了让放大后自然模糊，同时几乎不花时间。
    static let backdropSampleSize = 24

    /// 底色的不透明度。压住一些，避免和图片本身抢注意力。
    static let backdropAlpha: CGFloat = 0.6

    static func makeBackdrop(from source: CGImage, sampleSize: Int = backdropSampleSize) -> CGImage? {
        let side = max(1, sampleSize)
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }

    /// 按短边铺满，长边溢出，保证整个视图都被盖住。
    static func aspectFillRect(imageSize: CGSize, in area: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return area }
        let scale = max(area.width / imageSize.width, area.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: area.midX - size.width / 2,
            y: area.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func rebuildBackdrop() {
        guard let image else {
            backdropImage = nil
            return
        }
        backdropImage = Self.makeBackdrop(from: image.cgImage)
    }

    /// 换图或换帧时把内容塞进图层，随后只更新几何。
    private func refreshLayers() {
        backdropLayer.contents = backdropImage
        backdropLayer.isHidden = backdropImage == nil
        imageLayer.contents = displayedCGImage
        imageLayer.isHidden = displayedCGImage == nil
        updateLayerGeometry()
    }

    private var displayedCGImage: CGImage? {
        guard let image else { return nil }
        return image.animationFrames.indices.contains(currentAnimationFrameIndex)
            ? image.animationFrames[currentAnimationFrameIndex].cgImage
            : image.cgImage
    }

    /// 把当前的缩放、平移和查看旋转写进图层。
    private func updateLayerGeometry() {
        if let backdropImage, bounds.width > 0, bounds.height > 0 {
            backdropLayer.frame = Self.aspectFillRect(
                imageSize: CGSize(width: backdropImage.width, height: backdropImage.height),
                in: bounds
            )
        }

        guard let drawRect = imageDrawRect, displayedCGImage != nil else {
            imageLayer.isHidden = true
            return
        }
        imageLayer.isHidden = false
        // 图层先按未旋转的尺寸摆好，再整体转过去，
        // 这样 `imageDrawRect` 那套已经换过宽高的算法可以原样沿用。
        let unrotated = viewRotationQuarterTurns % 2 == 0
            ? drawRect.size
            : CGSize(width: drawRect.height, height: drawRect.width)
        imageLayer.bounds = CGRect(origin: .zero, size: unrotated)
        imageLayer.position = CGPoint(x: drawRect.midX, y: drawRect.midY)
        imageLayer.transform = Self.contentTransform(quarterTurns: viewRotationQuarterTurns)
    }

    /// 查看旋转就是绕 z 轴转，不要再叠任何镜像。
    ///
    /// 宿主视图是翻转的，合成时图层内容本身不受影响，加 y 轴镜像会让图片
    /// 上下颠倒。这里只保留旋转，坐标系和原来 `draw(_:)` 用的那个 y 向下的
    /// 上下文一致，所以正角度在屏幕上看就是顺时针，一档对应顺时针 90 度。
    ///
    /// 注意不要用 `CALayer.render(in:)` 验证这件事。它走的是离屏光栅化，
    /// 对翻转几何的处理和屏幕合成不一样，会得出需要镜像的错误结论。
    static func contentTransform(quarterTurns: Int) -> CATransform3D {
        CATransform3DMakeRotation(CGFloat(quarterTurns) * .pi / 2, 0, 0, 1)
    }

    private func updateLayerContentsScale() {
        let scaleFactor = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contentsScale = scaleFactor
        backdropLayer.contentsScale = scaleFactor
        imageLayer.contentsScale = scaleFactor
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateLayerContentsScale()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = backgroundColor.cgColor
        }
    }

    override func layout() {
        super.layout()
        updateLayerGeometry()
    }

    private var animationTimer: Timer?
    private(set) var currentAnimationFrameIndex = 0
    var isAnimating: Bool { animationTimer != nil }

    var scale: CGFloat = 1.0 {
        didSet {
            if !isApplyingDisplayMode {
                displayMode = .manual
                lastManualPixelScale = pixelScale
            }
            updateLayerGeometry()
            onTransformChanged?(scale)
        }
    }

    var offset: CGPoint = .zero {
        didSet { updateLayerGeometry() }
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// The rendered size of one image pixel in screen logical points.
    var pixelScale: CGFloat? {
        guard let fittedScale else { return nil }
        return fittedScale * scale
    }

    /// 查看时的旋转，按 90 度一档计。
    ///
    /// 只改显示，不动像素，也不产生待保存的修改。换一张图就归零。
    /// 真正要改文件的旋转在编辑模式里做。
    var viewRotationQuarterTurns: Int = 0 {
        didSet {
            // 在 didSet 里赋值不会再次触发 didSet，这里归一化到 0...3。
            viewRotationQuarterTurns = ((viewRotationQuarterTurns % 4) + 4) % 4
            guard viewRotationQuarterTurns != oldValue else { return }
            reapplyDisplayModeAfterAreaChange()
            updateLayerGeometry()
        }
    }

    /// 奇数档旋转会把宽高对调，布局要按转过之后的尺寸算。
    private var displayPixelSize: CGSize? {
        guard let image else { return nil }
        let width = CGFloat(image.cgImage.width)
        let height = CGFloat(image.cgImage.height)
        return viewRotationQuarterTurns % 2 == 0
            ? CGSize(width: width, height: height)
            : CGSize(width: height, height: width)
    }

    /// 玻璃 chrome 覆盖在画布上方，图片按去掉 chrome 的可见区域居中，
    /// 背景仍然铺满整个视图，这样玻璃底下有内容可以折射。
    var contentInsets: NSEdgeInsets = NSEdgeInsetsZero {
        didSet {
            guard !areInsetsEqual(oldValue, contentInsets) else { return }
            reapplyDisplayModeAfterAreaChange()
            updateLayerGeometry()
        }
    }

    var contentBounds: CGRect {
        CGRect(
            x: bounds.minX + contentInsets.left,
            y: bounds.minY + contentInsets.top,
            width: max(0, bounds.width - contentInsets.left - contentInsets.right),
            height: max(0, bounds.height - contentInsets.top - contentInsets.bottom)
        )
    }

    private func areInsetsEqual(_ lhs: NSEdgeInsets, _ rhs: NSEdgeInsets) -> Bool {
        lhs.top == rhs.top && lhs.left == rhs.left && lhs.bottom == rhs.bottom && lhs.right == rhs.right
    }

    private var fittedScale: CGFloat? {
        let area = contentBounds
        guard let size = displayPixelSize, area.width > 0, area.height > 0 else { return nil }
        return min(area.width / size.width, area.height / size.height)
    }

    var imageDrawRect: CGRect? {
        let area = contentBounds
        guard area.width > 0, area.height > 0 else { return nil }

        let imageSize = displayPixelSize ?? .zero
        guard let fittedScale else { return nil }
        let drawSize = CGSize(width: imageSize.width * fittedScale * scale, height: imageSize.height * fittedScale * scale)
        return CGRect(
            x: area.minX + (area.width - drawSize.width) / 2 + offset.x,
            y: area.minY + (area.height - drawSize.height) / 2 + offset.y,
            width: drawSize.width,
            height: drawSize.height
        )
    }

    func pixelCropRect(for canvasRect: CGRect) -> CGRect? {
        guard let image,
              let drawRect = imageDrawRect else {
            return nil
        }

        let visibleRect = canvasRect.standardized.intersection(drawRect)
        guard visibleRect.width > 0, visibleRect.height > 0 else {
            return nil
        }

        let scaleX = CGFloat(image.cgImage.width) / drawRect.width
        let scaleY = CGFloat(image.cgImage.height) / drawRect.height
        let pixelRect = CGRect(
            x: (visibleRect.minX - drawRect.minX) * scaleX,
            y: (visibleRect.minY - drawRect.minY) * scaleY,
            width: visibleRect.width * scaleX,
            height: visibleRect.height * scaleY
        ).integral
        let sourceBounds = CGRect(x: 0, y: 0, width: image.cgImage.width, height: image.cgImage.height)
        let clippedRect = pixelRect.intersection(sourceBounds)
        return clippedRect.width > 0 && clippedRect.height > 0 ? clippedRect : nil
    }

    func resetViewTransform() {
        isApplyingDisplayMode = true
        displayMode = .fit
        scale = 1.0
        isApplyingDisplayMode = false
        offset = .zero
    }

    func zoomToActualSize() {
        setManualPixelScale(1)
    }

    func zoomToFitWidth() {
        let area = contentBounds
        guard let size = displayPixelSize, let fittedScale, fittedScale > 0, area.width > 0 else { return }
        let widthPixelScale = area.width / size.width
        isApplyingDisplayMode = true
        displayMode = .fitWidth
        scale = widthPixelScale / fittedScale
        isApplyingDisplayMode = false
        offset = clampedOffset(for: .zero)
    }

    func setManualPixelScale(_ requestedPixelScale: CGFloat, around point: CGPoint? = nil) {
        guard let fittedScale, fittedScale > 0 else { return }
        let previousScale = scale
        let clampedPixelScale = min(
            max(requestedPixelScale, Self.minimumManualPixelScale),
            Self.maximumManualPixelScale
        )
        let targetScale = clampedPixelScale / fittedScale
        isApplyingDisplayMode = true
        displayMode = .manual
        lastManualPixelScale = fittedScale * targetScale
        scale = targetScale
        isApplyingDisplayMode = false

        if let point, previousScale > 0 {
            let ratio = targetScale / previousScale
            let center = CGPoint(x: contentBounds.midX, y: contentBounds.midY)
            let anchor = CGPoint(x: point.x - center.x, y: point.y - center.y)
            offset = clampedOffset(for: CGPoint(
                x: anchor.x - (anchor.x - offset.x) * ratio,
                y: anchor.y - (anchor.y - offset.y) * ratio
            ))
        } else {
            offset = .zero
        }
    }

    func setManualPercentage(_ percentage: CGFloat, around point: CGPoint? = nil) {
        setManualPixelScale(percentage / 100, around: point)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let previousMode = displayMode
        let preservedPixelScale = displayMode == .manual ? (lastManualPixelScale ?? pixelScale) : nil
        super.setFrameSize(newSize)
        applyPreservedScale(previousMode: previousMode, preservedPixelScale: preservedPixelScale)
        // 适应窗口模式下 scale 不变，走不到它的 didSet，几何要在这里补一次。
        updateLayerGeometry()
    }

    /// 内边距变化等价于可见区域变化，缩放状态按与改变窗口尺寸相同的规则延续。
    private func reapplyDisplayModeAfterAreaChange() {
        let preservedPixelScale = displayMode == .manual ? (lastManualPixelScale ?? pixelScale) : nil
        applyPreservedScale(previousMode: displayMode, preservedPixelScale: preservedPixelScale)
    }

    private func applyPreservedScale(previousMode: DisplayMode, preservedPixelScale: CGFloat?) {
        if previousMode == .fitWidth {
            zoomToFitWidth()
            return
        }
        guard let preservedPixelScale, let fittedScale, fittedScale > 0 else { return }
        isApplyingDisplayMode = true
        scale = preservedPixelScale / fittedScale
        isApplyingDisplayMode = false
        offset = clampedOffset(for: offset)
    }

    func zoom(by delta: CGFloat, around point: CGPoint) {
        if let pixelScale {
            setManualPixelScale(pixelScale * delta, around: point)
            return
        }

        // Keep the transform helpers useful before an image is assigned. Once an
        // image exists, zoom limits are expressed in real image-pixel scale above.
        let previousScale = scale
        let targetScale = min(max(previousScale * delta, 0.1), 12)
        scale = targetScale
        guard previousScale > 0 else { return }
        let ratio = targetScale / previousScale
        let center = CGPoint(x: contentBounds.midX, y: contentBounds.midY)
        let anchor = CGPoint(x: point.x - center.x, y: point.y - center.y)
        offset = clampedOffset(for: CGPoint(
            x: anchor.x - (anchor.x - offset.x) * ratio,
            y: anchor.y - (anchor.y - offset.y) * ratio
        ))
    }

    func pan(by delta: CGPoint) {
        offset = clampedOffset(for: CGPoint(x: offset.x + delta.x, y: offset.y + delta.y))
    }

    func clampedOffset(for proposedOffset: CGPoint) -> CGPoint {
        let area = contentBounds
        guard image != nil,
              area.width > 0,
              area.height > 0 else { return proposedOffset }
        let imageSize = displayPixelSize ?? .zero
        guard let fittedScale else { return proposedOffset }
        let drawSize = CGSize(width: imageSize.width * fittedScale * scale, height: imageSize.height * fittedScale * scale)
        let horizontalLimit = max(0, (drawSize.width - area.width) / 2)
        let verticalLimit = max(0, (drawSize.height - area.height) / 2)
        return CGPoint(
            x: min(max(proposedOffset.x, -horizontalLimit), horizontalLimit),
            y: min(max(proposedOffset.y, -verticalLimit), verticalLimit)
        )
    }

    func handleScroll(
        deltaX: CGFloat,
        deltaY: CGFloat,
        at point: CGPoint,
        modifierFlags: NSEvent.ModifierFlags = [],
        phase: NSEvent.Phase = [],
        momentumPhase: NSEvent.Phase = [],
        hasPreciseScrollingDeltas: Bool = true,
        isDirectionInvertedFromDevice _: Bool = false
    ) {
        // AppKit has already applied the user's scrolling preference to deltaX/Y.
        // Use those delivered values consistently for navigation, zoom, and panning.

        if modifierFlags.contains(.option) || modifierFlags.contains(.command) {
            resetTrackpadScrollState()
            guard abs(deltaY) > 0.1 else { return }
            let zoomDelta = max(0.7, min(1.3, 1.0 + (deltaY * 0.01)))
            zoom(by: zoomDelta, around: point)
            return
        }

        if scale > 1.01 {
            resetTrackpadScrollState()
            pan(by: CGPoint(x: -deltaX, y: -deltaY))
            return
        }

        if !momentumPhase.isEmpty {
            resetTrackpadScrollState()
            return
        }

        guard hasPreciseScrollingDeltas else { return }
        if phase.contains(.began) {
            resetTrackpadScrollState()
        }
        defer {
            if phase.contains(.ended) || phase.contains(.cancelled) {
                resetTrackpadScrollState()
            }
        }

        if trackpadScrollAxis == nil, abs(deltaX) > 0.1 || abs(deltaY) > 0.1 {
            trackpadScrollAxis = abs(deltaX) > abs(deltaY) ? .horizontal : .vertical
        }
        guard trackpadScrollAxis == .horizontal else { return }

        accumulatedTrackpadDeltaX += deltaX
        guard !didNavigateDuringTrackpadScroll,
              abs(accumulatedTrackpadDeltaX) >= Self.trackpadNavigationThreshold else {
            return
        }

        didNavigateDuringTrackpadScroll = true
        accumulatedTrackpadDeltaX > 0 ? onNext?() : onPrevious?()
    }

    private func resetTrackpadScrollState() {
        trackpadScrollAxis = nil
        accumulatedTrackpadDeltaX = 0
        didNavigateDuringTrackpadScroll = false
    }

    func beginMouseDrag(at point: CGPoint) {
        lastDragLocation = point
    }

    func continueMouseDrag(to point: CGPoint) {
        guard scale > 1.01,
              let lastDragLocation else {
            self.lastDragLocation = point
            return
        }

        pan(by: CGPoint(x: point.x - lastDragLocation.x, y: point.y - lastDragLocation.y))
        self.lastDragLocation = point
    }

    func endMouseDrag() {
        lastDragLocation = nil
    }

    func toggleFitOrActualSize() {
        if displayMode == .fit || displayMode == .fitWidth {
            setManualPixelScale(lastManualPixelScale ?? 1)
        } else {
            resetViewTransform()
        }
    }

    override func mouseDown(with event: NSEvent) {
        beginMouseDrag(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        continueMouseDrag(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        endMouseDrag()
    }

    /// 用 `menu(for:)` 而非 `rightMouseDown`，control 点击和触控板双指点按都会走到这里。
    override func menu(for event: NSEvent) -> NSMenu? {
        onContextMenuRequested?() ?? super.menu(for: event)
    }

    override func scrollWheel(with event: NSEvent) {
        handleScroll(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            at: convert(event.locationInWindow, from: nil),
            modifierFlags: event.modifierFlags,
            phase: event.phase,
            momentumPhase: event.momentumPhase,
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas,
            isDirectionInvertedFromDevice: event.isDirectionInvertedFromDevice
        )
    }

    func advanceAnimationFrame() {
        guard let image, !image.animationFrames.isEmpty else { return }
        currentAnimationFrameIndex = (currentAnimationFrameIndex + 1) % image.animationFrames.count
        imageLayer.contents = displayedCGImage
        scheduleNextAnimationFrame()
    }

    private func configureAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        guard image?.animationFrames.isEmpty == false else { return }
        scheduleNextAnimationFrame()
    }

    private func scheduleNextAnimationFrame() {
        animationTimer?.invalidate()
        guard let image,
              image.animationFrames.indices.contains(currentAnimationFrameIndex) else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: image.animationFrames[currentAnimationFrameIndex].duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.advanceAnimationFrame()
            }
        }
    }
}
