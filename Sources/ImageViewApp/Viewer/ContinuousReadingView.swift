import AppKit
import ImageViewCore

struct ContinuousReadingPage {
    let item: ImageItem
    let image: DecodedImage?
}

final class ContinuousReadingView: NSView {
    /// 上下各预解码多少页。页面按预览分辨率解码之后单页成本降了一个量级，
    /// 窗口可以开得比原来大得多，滚动时不容易撞到还没解出来的页。
    static let preloadRadius = 6
    static let maximumDecodedPageCount = preloadRadius * 2 + 1
    static let maximumDecodedByteCost = ImageCache.defaultFullImageCostLimit

    private let scrollView = NSScrollView()
    private let clipView = ContinuousReadingClipView()
    private let document = ContinuousReadingDocumentView()
    private var currentItemID: ImageItem.ID?
    private var focusUpdateTimer: Timer?
    private var isApplyingPages = false

    var onFocusedItemChanged: ((ImageItem.ID) -> Void)?
    var onContextMenuRequested: (() -> NSMenu?)? {
        didSet { document.onContextMenuRequested = onContextMenuRequested }
    }

    var documentViewForTesting: NSView { document }
    var testingPageCount: Int { document.pages.count }
    var testingDecodedPageCount: Int { document.pages.filter { $0.image != nil }.count }
    var testingPageURLs: [URL] { document.pages.map { $0.item.url } }
    var testingLastNearestLookupCount: Int { document.lastNearestLookupCount }

    override init(frame frameRect: NSRect = .zero) {
        super.init(frame: frameRect)
        wantsLayer = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.contentView = clipView
        scrollView.documentView = document
        clipView.onBoundsOriginChanged = { [weak self] in self?.scheduleFocusUpdate() }
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(AppStrings.text("viewer.continuousReading.accessibilityLabel"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let width = max(scrollView.contentSize.width, 1)
        let height = document.requiredHeight(for: width)
        document.frame = NSRect(x: 0, y: 0, width: width, height: max(height, scrollView.contentSize.height))
    }

    func apply(pages: [ContinuousReadingPage], currentItemID: ImageItem.ID?) {
        precondition(
            pages.filter { $0.image != nil }.count <= Self.maximumDecodedPageCount,
            "continuous reading must keep a bounded decoded window"
        )
        let previousID = self.currentItemID
        let previousFrame = previousID.flatMap(document.frame(for:))
        let previousOffsetFromPage = previousFrame.map {
            scrollView.contentView.bounds.minY - $0.minY
        }
        let shouldRevealCurrent = previousID != currentItemID
        isApplyingPages = true
        self.currentItemID = currentItemID
        document.pages = pages
        needsLayout = true
        layoutSubtreeIfNeeded()
        if shouldRevealCurrent, let currentItemID,
           let frame = document.frame(for: currentItemID) {
            scroll(toDocumentY: frame.minY - 12)
        } else if let currentItemID,
                  let previousOffsetFromPage,
                  let frame = document.frame(for: currentItemID) {
            scroll(toDocumentY: frame.minY + previousOffsetFromPage)
        }
        isApplyingPages = false
    }

    func testingScrollToItem(with id: ImageItem.ID) {
        guard let frame = document.frame(for: id) else { return }
        scroll(toDocumentY: frame.midY - scrollView.contentSize.height / 2)
        publishFocusedItemIfNeeded()
    }

    private func scroll(toDocumentY y: CGFloat) {
        let maximumY = max(0, document.bounds.height - scrollView.contentSize.height)
        scrollView.contentView.scroll(to: CGPoint(x: 0, y: min(max(0, y), maximumY)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func scheduleFocusUpdate() {
        guard !isApplyingPages else { return }
        focusUpdateTimer?.invalidate()
        focusUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.publishFocusedItemIfNeeded() }
        }
    }

    private func publishFocusedItemIfNeeded() {
        guard !isApplyingPages,
              let focusedID = document.nearestItemID(toDocumentY: scrollView.contentView.bounds.midY),
              focusedID != currentItemID else { return }
        currentItemID = focusedID
        onFocusedItemChanged?(focusedID)
    }
}

private final class ContinuousReadingClipView: NSClipView {
    var onBoundsOriginChanged: (() -> Void)?

    override func setBoundsOrigin(_ newOrigin: NSPoint) {
        let didChange = bounds.origin != newOrigin
        super.setBoundsOrigin(newOrigin)
        if didChange { onBoundsOriginChanged?() }
    }
}

private final class ContinuousReadingDocumentView: NSView {
    var onContextMenuRequested: (() -> NSMenu?)?

    /// 右击落在文档视图上，直接在这里给出菜单，不依赖响应链继续向上冒泡。
    override func menu(for event: NSEvent) -> NSMenu? {
        onContextMenuRequested?() ?? super.menu(for: event)
    }

    var pages: [ContinuousReadingPage] = [] {
        didSet {
            itemIndexByID = Dictionary(
                pages.enumerated().map { ($0.element.item.id, $0.offset) },
                uniquingKeysWith: { first, _ in first }
            )
            cachedLayoutWidth = nil
            cachedPageFrames = []
            needsDisplay = true
        }
    }
    private var itemIndexByID: [ImageItem.ID: Int] = [:]
    private var cachedLayoutWidth: CGFloat?
    private var cachedPageFrames: [CGRect] = []
    private(set) var lastNearestLookupCount = 0

    override var isFlipped: Bool { true }

    func requiredHeight(for width: CGFloat) -> CGFloat {
        pageFrames(for: width).last?.maxY ?? 0
    }

    func frame(for itemID: ImageItem.ID) -> CGRect? {
        guard let index = itemIndexByID[itemID] else { return nil }
        let frames = pageFrames(for: bounds.width)
        return frames.indices.contains(index) ? frames[index] : nil
    }

    func nearestItemID(toDocumentY y: CGFloat) -> ImageItem.ID? {
        let frames = pageFrames(for: bounds.width)
        guard !frames.isEmpty else {
            lastNearestLookupCount = 0
            return nil
        }

        var lowerBound = 0
        var upperBound = frames.count
        var lookupCount = 0
        while lowerBound < upperBound {
            lookupCount += 1
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if frames[middle].midY < y {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        lastNearestLookupCount = lookupCount
        let upperIndex = min(lowerBound, frames.count - 1)
        let lowerIndex = max(0, upperIndex - 1)
        let nearestIndex = abs(frames[lowerIndex].midY - y) <= abs(frames[upperIndex].midY - y)
            ? lowerIndex
            : upperIndex
        return pages[nearestIndex].item.id
    }

    override func draw(_ dirtyRect: NSRect) {
        // 底色跟随系统外观。以前写死黑色，配上很淡的占位块之后
        // 未解码的页面看起来就是一整片黑，像是坏了。
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        let frames = pageFrames(for: bounds.width)
        var lowerBound = 0
        var upperBound = frames.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if frames[middle].maxY < dirtyRect.minY {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        var index = lowerBound
        while index < frames.count, frames[index].minY <= dirtyRect.maxY {
            let page = pages[index]
            let frame = frames[index]
            guard let image = page.image else {
                // 解码窗口之外的页面画成一块看得见的待载占位，
                // 而不是一片和背景分不开的色块。
                drawPlaceholder(in: frame)
                index += 1
                continue
            }
            NSImage(cgImage: image.cgImage, size: frame.size).draw(
                in: frame,
                from: .zero,
                operation: .copy,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            index += 1
        }
    }

    /// 待载页面的占位：一块圆角浅色底加一个图片轮廓，
    /// 让人一眼看出这里是还没解出来的图，不是空白或故障。
    private func drawPlaceholder(in frame: CGRect) {
        let path = NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12)
        NSColor.quaternaryLabelColor.withAlphaComponent(0.16).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let side = min(frame.width, frame.height) * 0.16
        guard side > 8,
              let symbol = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)?
                  .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: side, weight: .light)) else {
            return
        }
        let box = NSRect(
            x: frame.midX - symbol.size.width / 2,
            y: frame.midY - symbol.size.height / 2,
            width: symbol.size.width,
            height: symbol.size.height
        )
        symbol.draw(in: box, from: .zero, operation: .sourceOver, fraction: 0.28, respectFlipped: true, hints: nil)
    }

    private func pageFrames(for width: CGFloat) -> [CGRect] {
        if let cachedLayoutWidth,
           abs(cachedLayoutWidth - width) < 0.5,
           cachedPageFrames.count == pages.count {
            return cachedPageFrames
        }
        let horizontalInset: CGFloat = 16
        let gap: CGFloat = 18
        let contentWidth = max(width - horizontalInset * 2, 1)
        var y: CGFloat = 16
        var frames: [CGRect] = []
        frames.reserveCapacity(pages.count)
        for page in pages {
            let aspectHeight: CGFloat
            if let image = page.image, image.cgImage.width > 0 {
                aspectHeight = contentWidth * CGFloat(image.cgImage.height) / CGFloat(image.cgImage.width)
            } else {
                aspectHeight = min(contentWidth * 0.75, 420)
            }
            let frame = CGRect(x: horizontalInset, y: y, width: contentWidth, height: max(aspectHeight, 1))
            y = frame.maxY + gap
            frames.append(frame)
        }
        cachedLayoutWidth = width
        cachedPageFrames = frames
        return frames
    }
}
