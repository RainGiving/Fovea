import AppKit
import ImageViewCore

final class FolderBrowserCellView: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("FolderBrowserCellView")

    private let thumbnailView = NSImageView()
    private let filenameField = NSTextField(labelWithString: "")
    private var thumbnailRequest: ThumbnailRequest?
    private var accessibilityPosition: Int?
    private var accessibilityTotal: Int?
    private(set) var testingAppearanceRefreshCount = 0

    var testingFilename: String {
        filenameField.stringValue
    }

    var testingImage: NSImage? {
        thumbnailView.image
    }

    var testingShowsSelection: Bool {
        view.layer?.borderWidth == 1
    }

    var testingSelectionBackgroundColor: CGColor? {
        view.layer?.backgroundColor
    }

    override var isSelected: Bool {
        didSet { updateSelectionAppearance() }
    }

    override func loadView() {
        let appearanceView = FolderBrowserAppearanceTrackingView()
        appearanceView.onEffectiveAppearanceChanged = { [weak self] in
            guard let self else { return }
            self.testingAppearanceRefreshCount += 1
            self.updateSelectionAppearance()
        }
        view = appearanceView
        view.translatesAutoresizingMaskIntoConstraints = false

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 8
        thumbnailView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        filenameField.translatesAutoresizingMaskIntoConstraints = false
        filenameField.alignment = .center
        filenameField.lineBreakMode = .byTruncatingMiddle
        filenameField.maximumNumberOfLines = 2
        filenameField.font = .systemFont(ofSize: 12)

        view.addSubview(thumbnailView)
        view.addSubview(filenameField)

        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            thumbnailView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            thumbnailView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            thumbnailView.heightAnchor.constraint(equalToConstant: 118),

            filenameField.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 6),
            filenameField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            filenameField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            filenameField.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -6)
        ])

        updateSelectionAppearance()
    }

    func configure(
        with item: ImageItem,
        thumbnailProvider: ThumbnailProvider,
        position: Int? = nil,
        total: Int? = nil
    ) {
        thumbnailRequest?.cancel()
        representedObject = item
        accessibilityPosition = position
        accessibilityTotal = total
        filenameField.stringValue = item.url.deletingPathExtension().lastPathComponent
        thumbnailView.image = nil
        thumbnailView.alphaValue = 1
        updateAccessibility()

        thumbnailRequest = thumbnailProvider.loadThumbnail(for: item) { [weak self, itemID = item.id] result in
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let currentItem = self.representedObject as? ImageItem,
                      currentItem.id == itemID else {
                    return
                }

                if case let .success(image) = result {
                    self.showThumbnail(image)
                }
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailRequest?.cancel()
        thumbnailRequest = nil
        representedObject = nil
        accessibilityPosition = nil
        accessibilityTotal = nil
        filenameField.stringValue = ""
        thumbnailView.image = nil
        thumbnailView.alphaValue = 1
    }

    /// 缩略图解出来之后淡进来。
    ///
    /// 一屏几十格各自在不同时刻落位，硬切会让整片网格闪个不停。
    private func showThumbnail(_ image: NSImage) {
        thumbnailView.image = image
        guard Motion.canAnimate(thumbnailView) else { return }
        thumbnailView.alphaValue = 0
        Motion.run(in: thumbnailView, duration: Motion.standard) {
            thumbnailView.animator().alphaValue = 1
        }
    }

    /// 网格里每格都套一层玻璃太重，选中态用一层染色加描边，
    /// 圆角与浮层保持同一套度量。
    private func updateSelectionAppearance() {
        view.wantsLayer = true
        view.layer?.cornerRadius = GlassMetrics.controlCornerRadius
        var background = NSColor.clear.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            background = isSelected
                ? NSColor.selectedContentBackgroundColor.withAlphaComponent(GlassMetrics.hoverTintAlpha).cgColor
                : NSColor.clear.cgColor
            view.layer?.borderColor = NSColor.keyboardFocusIndicatorColor.withAlphaComponent(0.65).cgColor
        }
        applySelectionLayer(background: background, borderWidth: isSelected ? 1 : 0)
        filenameField.font = .systemFont(ofSize: 12, weight: isSelected ? .semibold : .regular)
        updateAccessibility()
    }

    /// 选中的那层底色和描边淡着变。
    ///
    /// 框选一片图时格子接连点亮，硬切看着像在闪。模型值当场写好，
    /// 读到的一直是最终状态，动画只负责这一段怎么走过去。
    private func applySelectionLayer(background: CGColor, borderWidth: CGFloat) {
        guard let layer = view.layer else { return }
        if Motion.canAnimate(view), layer.backgroundColor != background || layer.borderWidth != borderWidth {
            let fade = CABasicAnimation(keyPath: "backgroundColor")
            fade.fromValue = layer.presentation()?.backgroundColor ?? layer.backgroundColor
            fade.toValue = background
            let border = CABasicAnimation(keyPath: "borderWidth")
            border.fromValue = layer.presentation()?.borderWidth ?? layer.borderWidth
            border.toValue = borderWidth
            for animation in [fade, border] {
                animation.duration = Motion.quick
                animation.timingFunction = Motion.entrance
            }
            layer.add(fade, forKey: "motion.selectionFill")
            layer.add(border, forKey: "motion.selectionBorder")
        }
        layer.backgroundColor = background
        layer.borderWidth = borderWidth
    }

    private func updateAccessibility() {
        guard let item = representedObject as? ImageItem else { return }
        var parts = [item.url.lastPathComponent, item.format.rawValue.uppercased()]
        if let accessibilityPosition, let accessibilityTotal {
            parts.append(String(
                format: AppStrings.text("folderBrowser.item.position"),
                accessibilityPosition,
                accessibilityTotal
            ))
        }
        parts.append(AppStrings.text(isSelected ? "folderBrowser.item.selected" : "folderBrowser.item.notSelected"))
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(parts.joined(separator: ", "))
        view.setAccessibilitySelected(isSelected)
    }
}

private final class FolderBrowserAppearanceTrackingView: NSView {
    var onEffectiveAppearanceChanged: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChanged?()
    }
}
