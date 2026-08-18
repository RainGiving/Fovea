import AppKit

final class EmptyStateView: NSView {
    var onOpenRequested: (() -> Void)?
    var onBrowseFolderRequested: (() -> Void)?
    var onOpenRecentRequested: ((URL) -> Void)?
    var onClearRecentRequested: (() -> Void)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(labelWithString: "")
    private let openButton = NSButton()
    private let browseFolderButton = NSButton()
    private let recentList: RecentItemsListView

    init(preferredLanguages: [String] = Locale.preferredLanguages) {
        recentList = RecentItemsListView(preferredLanguages: preferredLanguages)
        super.init(frame: .zero)

        let text: (String) -> String = {
            AppStrings.text($0, preferredLanguages: preferredLanguages)
        }

        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 42, weight: .regular)
        iconView.image = NSImage(
            systemSymbolName: "photo.on.rectangle.angled",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(symbolConfiguration)
        iconView.contentTintColor = .tertiaryLabelColor
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setAccessibilityElement(false)

        titleLabel.stringValue = text("emptyState.title")
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center

        messageLabel.stringValue = text("emptyState.message")
        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 2
        messageLabel.lineBreakMode = .byWordWrapping

        openButton.title = text("emptyState.open")
        // 空状态直接坐在画布上，按钮用真玻璃；打开是首选动作，走主色。
        openButton.bezelStyle = .glass
        openButton.tintProminence = .primary
        openButton.target = self
        openButton.action = #selector(requestOpen(_:))
        openButton.setAccessibilityLabel(openButton.title)

        browseFolderButton.title = text("emptyState.browseFolder")
        browseFolderButton.bezelStyle = .glass
        browseFolderButton.target = self
        browseFolderButton.action = #selector(requestBrowseFolder(_:))
        browseFolderButton.setAccessibilityLabel(browseFolderButton.title)

        let buttonStack = NSStackView(views: [openButton, browseFolderButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 8

        recentList.onOpen = { [weak self] url in self?.onOpenRecentRequested?(url) }
        recentList.onClear = { [weak self] in self?.onClearRecentRequested?() }

        let stack = NSStackView(views: [iconView, titleLabel, messageLabel, buttonStack, recentList])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(14, after: messageLabel)
        // 最近打开是另一件事，和上面那组动作之间留出一段，两块才分得开。
        stack.setCustomSpacing(24, after: buttonStack)
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 360)
        ])
    }

    func applyRecentItems(_ urls: [URL]) {
        recentList.apply(urls)
    }

    @objc private func requestOpen(_ sender: Any?) {
        onOpenRequested?()
    }

    @objc private func requestBrowseFolder(_ sender: Any?) {
        onBrowseFolderRequested?()
    }

    var titleTextForTesting: String { titleLabel.stringValue }
    var messageTextForTesting: String { messageLabel.stringValue }
    var buttonTitleForTesting: String { openButton.title }
    var browseFolderButtonTitleForTesting: String { browseFolderButton.title }
    var recentListForTesting: RecentItemsListView { recentList }

    func performOpenForTesting() {
        requestOpen(nil)
    }

    func performBrowseFolderForTesting() {
        requestBrowseFolder(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
