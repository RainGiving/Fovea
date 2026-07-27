import AppKit
import Combine
import ImageViewCore
import SwiftUI

private final class LocalEventMonitor: @unchecked Sendable {
    private var token: Any?

    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) {
        token = NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
    }

    func invalidate() {
        guard let token else { return }
        NSEvent.removeMonitor(token)
        self.token = nil
    }

    deinit {
        if let token {
            NSEvent.removeMonitor(token)
        }
    }
}

@MainActor
final class MainWindowController: NSWindowController, NSGestureRecognizerDelegate {
    static let externalFileCheckInterval: TimeInterval = 2
    static let titleBarHeight: CGFloat = 32
    static let bottomBarHeight: CGFloat = 28
    static let bottomBarInfoSymbolName = "info.circle"
    static let bottomBarStatusToInfoSpacing: CGFloat = 8
    static let filmstripOverlayHeight: CGFloat = 118
    static let overlayAutoHideDelay: TimeInterval = 1.8
    static let overlayFadeOutDuration: TimeInterval = 0.18
    static func titleBarBrowseFolderToolTip(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        AppStrings.text("titleBar.showFolder", preferredLanguages: preferredLanguages)
    }

    var onSuccessfulOpen: ((URL) -> Void)? {
        didSet { viewModel.onSuccessfulOpen = onSuccessfulOpen }
    }
    var onOpenRequested: (() -> Void)?
    var onBrowseFolderRequested: (() -> Void)?
    var onOpenRecentRequested: ((URL) -> Void)?
    var onClearRecentRequested: (() -> Void)?
    private(set) var hasAssignedOpenRequest = false
    var onWindowDidBecomeKey: ((MainWindowController) -> Void)?
    var onWindowDidClose: ((MainWindowController) -> Void)?
    enum MenuCommand: Equatable {
        case fileOperationRequiringCurrentItem
        case copyImage
        case navigation
        case canvasSizing
        case startCropping
        case editOperation(EditOperation)
        case saveEdits
        case saveEditsAs
        case discardEdits
        case undoEdit
        case redoEdit
    }

    enum KeyAction: Equatable {
        case showPrevious
        case showNext
        case closeWindow
        case moveToTrash
        case toggleZoom
        case toggleFullscreen
        case startCropping
        case applyCrop
        case cancelCrop
        case endEditing
        case passThrough
    }

    enum UnsavedChangesChoice: Equatable {
        case save
        case discard
        case cancel
    }

    enum UnsavedChangesResolution: Equatable {
        case proceed
        case stayOnCurrentImage
    }

    enum MoveConflictChoice: Equatable {
        case skipConflicts
        case keepBoth
        case cancel
    }

    struct BatchActionDialogProvider {
        var confirmTrash: ((Int) -> Bool)?
        var chooseDestinationFolder: (() -> URL?)?
        var chooseMoveConflict: (([String]) -> MoveConflictChoice)?
        var requestRenameParameters: ((
            [ImageItem],
            BatchRenameSheetController.PlanRename,
            @escaping (BatchRenameSheetController.RenameParameters, BatchRenamePlan) -> Void
        ) -> Void)?

        init(
            confirmTrash: ((Int) -> Bool)? = nil,
            chooseDestinationFolder: (() -> URL?)? = nil,
            chooseMoveConflict: (([String]) -> MoveConflictChoice)? = nil,
            requestRenameParameters: ((
                [ImageItem],
                BatchRenameSheetController.PlanRename,
                @escaping (BatchRenameSheetController.RenameParameters, BatchRenamePlan) -> Void
            ) -> Void)? = nil
        ) {
            self.confirmTrash = confirmTrash
            self.chooseDestinationFolder = chooseDestinationFolder
            self.chooseMoveConflict = chooseMoveConflict
            self.requestRenameParameters = requestRenameParameters
        }
    }

    struct RecoveryAlertPresentation: Equatable {
        let folderURL: URL
        let title: String
        let message: String
        let details: String
    }

    struct PageControlAvailability: Equatable {
        let previous: Bool
        let next: Bool
    }

    private enum ContentRoute: Equatable {
        case viewer(URL)
        case folder(URL)
    }

    private struct FolderRouteState {
        let session: FolderSession?
        let isLoading: Bool
    }

    private let viewModel = ViewerViewModel()
    private let folderBrowserViewModel: FolderBrowserViewModel
    private let settings: AppSettings
    private let rootView = RootInteractionView()
    private let titleBarView = GlassPanelView()
    private let titleLabel = NSTextField(labelWithString: "ImageView")
    private let titleBarGridButton = HoverToolbarButton()
    private let titleBarFilmstripButton = HoverToolbarButton()
    private let titleBarEditButton = HoverToolbarButton()
    private let titleBarMoreButton = HoverToolbarButton()
    private let titleBarControlsStack = NSStackView()
    private lazy var titleBarDoubleClickRecognizer = NSClickGestureRecognizer(
        target: self,
        action: #selector(toggleWindowZoom(_:))
    )
    private let canvas = ImageCanvasView()
    private let continuousReadingView = ContinuousReadingView()
    private let folderBrowserView = FolderBrowserView()
    private let emptyStateView = EmptyStateView()
    private let errorStateView = ErrorStateView()
    private let cropOverlay = CropOverlayView()
    private let cropControlsView = NSHostingView(rootView: EditControlsView(onCancel: {}, onApply: {}))
    private let inspectorView = NSHostingView(rootView: InspectorView(metadata: nil))
    private let bottomBarView = GlassPanelView()
    private let bottomDimensionLabel = NSTextField(labelWithString: "— × — px")
    private let bottomPageLabel = NSTextField(labelWithString: "0 / 0")
    private let bottomZoomLabel = NSTextField(labelWithString: "100%")
    private lazy var bottomZoomClickRecognizer = NSClickGestureRecognizer(
        target: self,
        action: #selector(showZoomMenu(_:))
    )
    private let bottomInfoButton = NSButton()
    private let filmstripOverlayView = FilmstripOverlayView()
    private let filmstripView = FilmstripView()
    /// 胶卷条下方的滑杆，拖动可以快速扫过整个目录。
    private let filmstripSlider = NSSlider()
    private let pageNavigationOverlayView = PageNavigationOverlayView()
    private let usageHintView = UsageHintView()
    private var cancellables: Set<AnyCancellable> = []
    private var gestureCoordinator: GestureCoordinator?
    private var keyMonitor: LocalEventMonitor?
    private var outsideClickMonitor: LocalEventMonitor?
    private var displayedItemURL: URL?
    private var associatedViewerURL: URL?
    private var externalFileCheckTimer: Timer?
    private var filmstripVisibilityGeneration = 0
    private var pageControlsHideTimer: Timer?
    private var pageControlsVisibilityGeneration = 0
    private var usageHintTimer: Timer?
    /// 是否处在「编辑图片」模式。裁切框、编辑控制条和真实旋转都由它决定。
    private(set) var isEditingImage = false
    /// 当前选择的裁切比例，跨图片保留。
    private var cropAspectRatio: CropAspectRatio = .free
    /// 上一次重置查看旋转时对应的条目，用来区分换图和编辑后重绘。
    private var lastViewRotationItemID: ImageItem.ID?
    /// 这一次换图该往哪个方向滑。翻页时设，画面更新后消费掉。
    private var pendingNavigationSlide: CATransitionSubtype?
    /// 正在拖滑杆。此时忽略胶卷条回传的进度，避免自己推自己。
    private var isDraggingFilmstripSlider = false
    private var inspectorTrailingConstraint: NSLayoutConstraint!
    private var inspectorTopConstraint: NSLayoutConstraint!
    private var inspectorBottomConstraint: NSLayoutConstraint!
    /// 信息面板的固定宽度，停靠时画布让出的正是这个宽度。
    private var filmstripCenterXConstraint: NSLayoutConstraint!
    private var filmstripTrailingConstraint: NSLayoutConstraint!
    private var filmstripWidthConstraint: NSLayoutConstraint!
    private var titleBarHeightConstraint: NSLayoutConstraint!
    private var bottomBarHeightConstraint: NSLayoutConstraint!
    private var isInspectorDocked = false
    private var isPointerOverPageControls = false
    private var folderRetryTask: Task<Void, Never>?
    private var continuousReadingTask: Task<Void, Never>?
    private var continuousReadingFocusID: ImageItem.ID?
    private var isInFullScreen = false
    private var fullScreenChromeHideTimer: Timer?
    private var lastAnnouncedLoadedURL: URL?
    private var folderRetryGeneration: UInt64 = 0
    private var isFolderBrowserMode = false
    /// 全屏里 chrome 会自动收起，重算图片内边距时要知道当下是收着还是展开。
    private var isChromeVisible = true
    private var currentFolderBrowserItems: [ImageItem] = []
    private var currentRoute: ContentRoute? {
        didSet { updateTitleBarControlAvailability() }
    }
    private var backRoute: ContentRoute? {
        didSet { updateTitleBarControlAvailability() }
    }
    private var forwardRoute: ContentRoute? {
        didSet { updateTitleBarControlAvailability() }
    }
    private var activeBatchRenameSheet: BatchRenameSheetController?
    var batchActionDialogProviderForTesting: BatchActionDialogProvider?
    var recoveryAlertPresenterForTesting: ((RecoveryAlertPresentation) -> Void)?
    var accessibilityAnnouncementHandlerForTesting: ((String) -> Void)?
    private var unsavedChangesChoiceForTesting: UnsavedChangesChoice?
    private var editDestinationChoiceForTesting: EditDestinationChoice?

    convenience init(
        settings: AppSettings = .shared,
        folderBrowserViewModel: FolderBrowserViewModel = FolderBrowserViewModel()
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "ImageView"
        self.init(window: window, settings: settings, folderBrowserViewModel: folderBrowserViewModel)
        setup()
    }

    init(
        window: NSWindow?,
        settings: AppSettings = .shared,
        folderBrowserViewModel: FolderBrowserViewModel = FolderBrowserViewModel()
    ) {
        self.settings = settings
        self.folderBrowserViewModel = folderBrowserViewModel
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        folderRetryTask?.cancel()
        continuousReadingTask?.cancel()
        keyMonitor?.invalidate()
        outsideClickMonitor?.invalidate()
        let folderBrowserViewModel = folderBrowserViewModel
        folderBrowserViewModel.invalidateOpenFolderRequest()
        Task { @MainActor in
            folderBrowserViewModel.cancelOpenFolderRequest()
        }
    }

    func open(url: URL) {
        hasAssignedOpenRequest = true
        confirmUnsavedEditsIfNeeded(for: .opening) { [weak self] in
            guard let self else { return }
            self.currentRoute = .viewer(url.standardizedFileURL)
            self.associatedViewerURL = nil
            self.backRoute = nil
            self.forwardRoute = nil
            self.openImageUsingExistingPipeline(url)
        }
    }

    private func openImageUsingExistingPipeline(_ url: URL) {
        exitFolderBrowserMode()
        cancelCrop(nil)
        let viewModel = viewModel
        Task { [weak viewModel] in
            await viewModel?.open(url: url)
        }
    }

    func openFolder(url: URL) {
        invalidateFolderRetry()
        hasAssignedOpenRequest = true
        currentRoute = .folder(url.standardizedFileURL)
        associatedViewerURL = nil
        backRoute = nil
        forwardRoute = nil
        enterFolderBrowserMode()
        Task { [weak self] in
            guard let self else { return }
            await self.folderBrowserViewModel.openFolder(url)
        }
    }

    private func setup() {
        window?.delegate = self
        window?.titlebarAppearsTransparent = true
        window?.titleVisibility = .hidden
        window?.center()
        rootView.wantsLayer = true
        window?.acceptsMouseMovedEvents = true
        rootView.onFileDropped = { [weak self] url in
            guard let self else { return }
            if Self.isDirectoryURL(url) {
                self.openFolder(url: url)
            } else {
                self.open(url: url)
            }
        }
        emptyStateView.onOpenRequested = { [weak self] in
            self?.onOpenRequested?()
        }
        emptyStateView.onBrowseFolderRequested = { [weak self] in
            self?.onBrowseFolderRequested?()
        }
        emptyStateView.onOpenRecentRequested = { [weak self] url in
            self?.onOpenRecentRequested?(url)
        }
        emptyStateView.onClearRecentRequested = { [weak self] in
            self?.onClearRecentRequested?()
        }
        errorStateView.onRetryRequested = { [weak self] in
            self?.onOpenRequested?()
        }
        rootView.onPointerMoved = { [weak self] in
            guard let self else { return }
            self.hideUsageHint()
            self.revealFullScreenChromeIfNeeded()
            guard !self.isFolderBrowserMode else { return }
            self.revealPageControls()
        }
        pageNavigationOverlayView.onPrevious = { [weak self] in
            self?.navigateToPreviousImage()
        }
        pageNavigationOverlayView.onNext = { [weak self] in
            self?.navigateToNextImage()
        }
        pageNavigationOverlayView.onPointerEntered = { [weak self] in
            self?.isPointerOverPageControls = true
            self?.cancelPageControlsAutoHide()
        }
        pageNavigationOverlayView.onPointerExited = { [weak self] in
            self?.isPointerOverPageControls = false
            self?.schedulePageControlsAutoHide()
        }
        configureContentBars()
        canvas.autoresizingMask = [.width, .height]
        canvas.translatesAutoresizingMaskIntoConstraints = false
        window?.contentView = rootView
        rootView.addSubview(canvas)
        rootView.addSubview(continuousReadingView)
        rootView.addSubview(folderBrowserView)
        rootView.addSubview(emptyStateView)
        rootView.addSubview(errorStateView)
        rootView.addSubview(titleBarView)
        rootView.addSubview(bottomBarView)
        rootView.addSubview(filmstripOverlayView)
        rootView.addSubview(pageNavigationOverlayView)
        rootView.addSubview(inspectorView)
        rootView.addSubview(usageHintView)
        bottomBarView.contentView.addSubview(bottomDimensionLabel)
        bottomBarView.contentView.addSubview(bottomPageLabel)
        bottomBarView.contentView.addSubview(bottomZoomLabel)
        bottomBarView.contentView.addSubview(bottomInfoButton)
        filmstripOverlayView.contentView.addSubview(filmstripView)
        filmstripOverlayView.contentView.addSubview(filmstripSlider)
        rootView.addSubview(cropOverlay)
        rootView.addSubview(cropControlsView)
        folderBrowserView.translatesAutoresizingMaskIntoConstraints = false
        continuousReadingView.translatesAutoresizingMaskIntoConstraints = false
        continuousReadingView.isHidden = true
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        errorStateView.translatesAutoresizingMaskIntoConstraints = false
        inspectorView.translatesAutoresizingMaskIntoConstraints = false
        usageHintView.translatesAutoresizingMaskIntoConstraints = false
        usageHintView.isHidden = true
        usageHintView.onDismiss = { [weak self] in self?.hideUsageHint() }
        for label in [bottomDimensionLabel, bottomPageLabel, bottomZoomLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
        }
        bottomInfoButton.translatesAutoresizingMaskIntoConstraints = false
        filmstripOverlayView.translatesAutoresizingMaskIntoConstraints = false
        filmstripView.translatesAutoresizingMaskIntoConstraints = false
        configureFilmstripSlider()
        pageNavigationOverlayView.translatesAutoresizingMaskIntoConstraints = false
        cropOverlay.translatesAutoresizingMaskIntoConstraints = false
        cropControlsView.translatesAutoresizingMaskIntoConstraints = false
        cropOverlay.isHidden = true
        cropControlsView.isHidden = true
        activateLayoutConstraints()

        updateCanvasContentInsets(chromeVisible: true)
        canvas.onNext = { [weak self] in self?.navigateToNextImage() }
        canvas.onPrevious = { [weak self] in self?.navigateToPreviousImage() }
        canvas.onContextMenuRequested = { [weak self] in self?.makeImageContextMenu() }
        continuousReadingView.onContextMenuRequested = { [weak self] in self?.makeImageContextMenu() }
        continuousReadingView.onFocusedItemChanged = { [weak self] itemID in
            guard let self else { return }
            self.continuousReadingFocusID = itemID
            self.refreshContinuousReadingWindow()
        }
        canvas.onTransformChanged = { [weak self] _ in
            self?.updateZoomStatus()
        }
        gestureCoordinator = GestureCoordinator(canvas: canvas)
        filmstripView.onSelect = { [weak self] item in
            self?.selectImage(item)
        }
        folderBrowserView.onOpenItem = { [weak self] item in
            self?.openFolderBrowserItem(item)
        }
        folderBrowserView.onSelectionChanged = { [weak self] selectedIDs in
            self?.folderBrowserViewModel.setSelection(Array(selectedIDs))
        }
        folderBrowserView.onSearchChanged = { [weak self] searchText in
            self?.folderBrowserViewModel.searchText = searchText
        }
        folderBrowserView.onSortChanged = { [weak self] sortMode in
            self?.folderBrowserViewModel.setSortMode(sortMode)
        }
        folderBrowserView.onTypeFilterChanged = { [weak self] formats in
            self?.folderBrowserViewModel.setAllowedFormats(formats)
        }
        folderBrowserView.onClearFilters = { [weak self] in
            self?.folderBrowserViewModel.clearFilters()
        }
        folderBrowserView.onRetryFolder = { [weak self] in
            self?.startFolderRetry()
        }
        folderBrowserView.onChooseAnotherFolder = { [weak self] in
            self?.onBrowseFolderRequested?()
        }
        folderBrowserView.onMoveToTrash = { [weak self] in
            self?.moveSelectedFolderBrowserItemsToTrash()
        }
        folderBrowserView.onMoveToFolder = { [weak self] in
            self?.moveSelectedFolderBrowserItemsToFolder()
        }
        folderBrowserView.onBatchRename = { [weak self] in
            self?.renameSelectedFolderBrowserItems()
        }
        folderBrowserView.onCancelOperation = { [weak self] in
            self?.folderBrowserViewModel.cancelCurrentOperation()
        }
        folderBrowserView.onUndoLastOperation = { [weak self] in
            self?.folderBrowserViewModel.undoLastBatchOperation()
        }
        folderBrowserView.onShowOperationDetails = { [weak self] details in
            self?.presentBatchOperationDetails(details)
        }
        folderBrowserViewModel.onItemURLMutation = { [weak self] mutation in
            self?.applyFolderItemURLMutation(mutation)
        }
        folderBrowserViewModel.onRecoveryRequired = { [weak self] folderURL, failures in
            self?.presentRecoveryRequiredAlert(folderURL: folderURL, failures: failures)
        }

        viewModel.$currentImage
            .sink { [weak self] image in
                guard let self else { return }
                self.canvas.image = image
                // 查看时的旋转属于「这一张怎么看」，换一张就归零。
                // 编辑产生的新图不算换图，所以按条目 id 判断而不是按图片对象。
                let itemID = self.viewModel.navigationState?.currentItem?.id
                if itemID != self.lastViewRotationItemID {
                    self.lastViewRotationItemID = itemID
                    self.canvas.viewRotationQuarterTurns = 0
                }
                self.updateContinuousReadingPresentation()
                self.updateFilmstripVisibility(hasLoadedImage: image != nil)
                let slide = self.pendingNavigationSlide
                self.pendingNavigationSlide = nil
                guard self.settings.animatesNavigationTransitions,
                      !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                      image != nil else { return }
                self.playNavigationTransition(slide: slide)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            folderBrowserViewModel.$session,
            folderBrowserViewModel.$isLoading,
            folderBrowserViewModel.$loadErrorMessage
        )
            .sink { [weak self] session, isLoading, loadErrorMessage in
                guard let self else { return }
                let items = session?.visibleItems ?? []
                if self.currentFolderBrowserItems != items {
                    self.currentFolderBrowserItems = items
                    self.folderBrowserView.applyItems(items)
                }
                self.folderBrowserView.applyFilter(session?.filter ?? FolderFilter())
                self.folderBrowserView.applyCounts(
                    total: session?.items.count ?? 0,
                    visible: session?.visibleItems.count ?? 0,
                    selected: self.folderBrowserViewModel.selectedItemIDs.count
                )
                self.folderBrowserView.applyPresentation(Self.folderBrowserPresentation(
                    session: session,
                    isLoading: isLoading,
                    loadErrorMessage: loadErrorMessage
                ))
                self.updateTitleBarControlAvailability(
                    folderState: FolderRouteState(session: session, isLoading: isLoading)
                )
                self.updateWindowTitle(viewerTitle: self.viewModel.displayTitle)
            }
            .store(in: &cancellables)

        folderBrowserViewModel.$selectedItemIDs
            .removeDuplicates()
            .sink { [weak self] selectedItemIDs in
                guard let self else { return }
                self.folderBrowserView.applySelection(Set(selectedItemIDs))
                self.folderBrowserView.applyCounts(
                    total: self.folderBrowserViewModel.session?.items.count ?? 0,
                    visible: self.folderBrowserViewModel.session?.visibleItems.count ?? 0,
                    selected: selectedItemIDs.count
                )
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4(
            folderBrowserViewModel.$operationMessage,
            folderBrowserViewModel.$operationFailures,
            folderBrowserViewModel.$operationRecoveryFailures,
            folderBrowserViewModel.$isOperating
        )
            .sink { [weak self] message, failures, recoveryFailures, isOperating in
                self?.folderBrowserView.applyOperationStatus(
                    message: message,
                    failures: failures,
                    recoveryFailures: recoveryFailures,
                    isOperating: isOperating
                )
            }
            .store(in: &cancellables)

        folderBrowserViewModel.$operationProgress
            .sink { [weak self] progress in
                self?.folderBrowserView.applyProgress(progress)
            }
            .store(in: &cancellables)

        folderBrowserViewModel.$canUndoLastBatchOperation
            .sink { [weak self] isAvailable in
                self?.folderBrowserView.applyUndoAvailability(isAvailable)
            }
            .store(in: &cancellables)

        viewModel.$displayTitle
            .sink { [weak self] title in
                self?.updateWindowTitle(viewerTitle: title)
            }
            .store(in: &cancellables)

        viewModel.$errorMessage
            .sink { [weak self] message in
                self?.errorStateView.message = message ?? ""
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            viewModel.$currentImage,
            viewModel.$loadPhase,
            viewModel.$errorMessage
        )
            .sink { [weak self] image, loadPhase, errorMessage in
                guard let self else { return }
                self.updateEmptyStatePresentation(
                    hasCurrentImage: image != nil,
                    loadPhase: loadPhase,
                    hasError: errorMessage != nil
                )
                self.announceLoadedImageIfNeeded(hasImage: image != nil, loadPhase: loadPhase)
                // 能不能编辑取决于当前这张解到了哪一步。@Published 在 willSet 时
                // 发布，此刻 viewModel 上的属性还没写回去，所以按发过来的这两个
                // 值算，不要回头去读 viewModel。
                self.updateTitleBarControlAvailability(
                    canEditCurrentImage: loadPhase == .full && image != nil
                )
                // 信息栏让出的那一条随「有没有图」变化，胶卷条也跟着它挪。
                self.updateInspectorPresentation(hasCurrentImage: image != nil)
                self.updateFilmstripVisibility(hasLoadedImage: image != nil)
            }
            .store(in: &cancellables)

        viewModel.$currentMetadata
            .sink { [weak self] metadata in
                guard let self else { return }
                self.updateInspector(metadata: metadata)
                self.updateDimensionStatus(metadata: metadata)
            }
            .store(in: &cancellables)

        viewModel.$navigationState
            .sink { [weak self] state in
                guard let self else { return }
                self.continuousReadingFocusID = state?.currentItem?.id
                let newURL = state?.currentItem?.url
                let didNavigate = self.displayedItemURL != nil
                    && Self.shouldResetCanvasTransform(from: self.displayedItemURL, to: newURL)
                if Self.shouldResetCanvasTransform(from: self.displayedItemURL, to: newURL) {
                    self.canvas.resetViewTransform()
                }
                self.displayedItemURL = newURL?.standardizedFileURL
                if case .viewer = self.currentRoute, let newURL {
                    self.currentRoute = .viewer(newURL.standardizedFileURL)
                    if self.associatedViewerURL != nil {
                        self.associatedViewerURL = newURL.standardizedFileURL
                    }
                }
                self.syncFilmstripContent(navigationState: state)
                let availability = Self.pageControlAvailability(
                    navigationState: state,
                    readingDirection: self.settings.readingDirection
                )
                self.pageNavigationOverlayView.update(
                    previousEnabled: availability.previous,
                    nextEnabled: availability.next
                )
                if Self.shouldDisplayPageControls(
                    itemCount: state?.items.count ?? 0,
                    isCropping: self.cropOverlay.isCropping
                ) {
                    if didNavigate {
                        self.revealPageControls()
                    }
                } else {
                    self.hidePageControls(immediately: true)
                }
                self.updatePageStatus(navigationState: state)
                self.updateTitleBarControlAvailability()
                self.updateContinuousReadingPresentation()
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.applySettings()
                }
            }
            .store(in: &cancellables)

        installKeyMonitor()
        installOutsideClickMonitor()
        applySettings()
        updateDimensionStatus(metadata: viewModel.currentMetadata)
        updatePageStatus(navigationState: viewModel.navigationState)
        let availability = Self.pageControlAvailability(
            navigationState: viewModel.navigationState,
            readingDirection: settings.readingDirection
        )
        pageNavigationOverlayView.update(
            previousEnabled: availability.previous,
            nextEnabled: availability.next
        )
        updateZoomStatus()
    }

    override func keyDown(with event: NSEvent) {
        guard !handleKeyDown(event) else { return }
        super.keyDown(with: event)
    }

    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldAttemptToRecognizeWith event: NSEvent
    ) -> Bool {
        guard gestureRecognizer === titleBarDoubleClickRecognizer else { return true }
        // hitTest 收的点在父视图坐标系里。原来换算到了标题栏自己的坐标系，
        // 标题栏贴着窗口顶边，两套坐标差着一整个窗口高度，命中永远落空，
        // 双击整条栏都没反应。
        let location = titleBarView.superview?.convert(event.locationInWindow, from: nil)
            ?? event.locationInWindow
        return shouldRecognizeTitleBarDoubleClick(hitView: titleBarView.hitTest(location))
    }

    /// 建立并激活整套布局约束。
    ///
    /// 从 setup 里分出来的一段。原来 setup 有 467 行，约束占了大头，
    /// 混在视图创建和回调接线中间很难读。
    private func activateLayoutConstraints() {
        inspectorTrailingConstraint = inspectorView.trailingAnchor.constraint(
            equalTo: rootView.trailingAnchor,
            constant: -GlassMetrics.floatingInset
        )
        inspectorTopConstraint = inspectorView.topAnchor.constraint(
            equalTo: titleBarView.bottomAnchor,
            constant: GlassMetrics.floatingInset
        )
        inspectorBottomConstraint = inspectorView.bottomAnchor.constraint(
            lessThanOrEqualTo: bottomBarView.topAnchor,
            constant: -GlassMetrics.floatingInset
        )
        // 胶卷条跟着图片可用的那块区域走。信息栏停靠时右边让出一条，
        // 胶卷条要往左收，否则会被压在面板底下。
        filmstripCenterXConstraint = filmstripOverlayView.centerXAnchor.constraint(equalTo: canvas.centerXAnchor)
        filmstripTrailingConstraint = filmstripOverlayView.trailingAnchor.constraint(
            lessThanOrEqualTo: canvas.trailingAnchor,
            constant: -GlassMetrics.floatingInset
        )
        // 窗口窄或者信息栏占了地方时，让位给上面那条上限，宽度自己缩。
        filmstripWidthConstraint = filmstripOverlayView.widthAnchor.constraint(
            equalTo: canvas.widthAnchor,
            multiplier: 0.72
        )
        filmstripWidthConstraint.priority = .defaultHigh
        titleBarHeightConstraint = titleBarView.heightAnchor.constraint(equalToConstant: Self.titleBarHeight)
        bottomBarHeightConstraint = bottomBarView.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight)
        NSLayoutConstraint.activate([
            titleBarView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            titleBarView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            titleBarView.topAnchor.constraint(equalTo: rootView.topAnchor),
            titleBarHeightConstraint,
            titleLabel.centerXAnchor.constraint(equalTo: titleBarView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: titleBarView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleBarControlsStack.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: titleBarView.trailingAnchor, constant: -72),
            titleBarControlsStack.leadingAnchor.constraint(equalTo: titleBarView.leadingAnchor, constant: 72),
            titleBarControlsStack.centerYAnchor.constraint(equalTo: titleBarView.centerYAnchor),
            bottomBarView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            bottomBarView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            bottomBarView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            bottomBarHeightConstraint,
            canvas.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            // 画布铺满整窗，图片靠 contentInsets 避开玻璃 chrome，
            // 底下的画面透过玻璃形成折射。
            canvas.topAnchor.constraint(equalTo: rootView.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            continuousReadingView.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            continuousReadingView.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            continuousReadingView.topAnchor.constraint(equalTo: canvas.topAnchor),
            continuousReadingView.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
            folderBrowserView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            folderBrowserView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            folderBrowserView.topAnchor.constraint(equalTo: titleBarView.bottomAnchor),
            folderBrowserView.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor),
            emptyStateView.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: canvas.centerYAnchor),
            emptyStateView.leadingAnchor.constraint(greaterThanOrEqualTo: canvas.leadingAnchor, constant: 24),
            emptyStateView.trailingAnchor.constraint(lessThanOrEqualTo: canvas.trailingAnchor, constant: -24),
            errorStateView.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            errorStateView.centerYAnchor.constraint(equalTo: canvas.centerYAnchor),
            errorStateView.leadingAnchor.constraint(greaterThanOrEqualTo: canvas.leadingAnchor, constant: 24),
            errorStateView.trailingAnchor.constraint(lessThanOrEqualTo: canvas.trailingAnchor, constant: -24),
            // 画布铺满整窗，所有浮层改挂到 chrome 的内沿上。
            // chrome 隐藏时两条栏的高度归零，浮层自然回到窗口边缘。
            inspectorTrailingConstraint,
            inspectorTopConstraint,
            inspectorBottomConstraint,
            usageHintView.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            usageHintView.topAnchor.constraint(equalTo: titleBarView.bottomAnchor, constant: 18),
            usageHintView.leadingAnchor.constraint(greaterThanOrEqualTo: canvas.leadingAnchor, constant: 20),
            usageHintView.trailingAnchor.constraint(lessThanOrEqualTo: canvas.trailingAnchor, constant: -20),
            bottomDimensionLabel.leadingAnchor.constraint(equalTo: bottomBarView.leadingAnchor, constant: 12),
            bottomDimensionLabel.trailingAnchor.constraint(lessThanOrEqualTo: bottomPageLabel.leadingAnchor, constant: -12),
            bottomDimensionLabel.centerYAnchor.constraint(equalTo: bottomBarView.centerYAnchor),
            bottomPageLabel.centerXAnchor.constraint(equalTo: bottomBarView.centerXAnchor),
            bottomPageLabel.centerYAnchor.constraint(equalTo: bottomBarView.centerYAnchor),
            bottomPageLabel.trailingAnchor.constraint(lessThanOrEqualTo: bottomZoomLabel.leadingAnchor, constant: -12),
            bottomZoomLabel.trailingAnchor.constraint(equalTo: bottomInfoButton.leadingAnchor, constant: -Self.bottomBarStatusToInfoSpacing),
            bottomZoomLabel.centerYAnchor.constraint(equalTo: bottomBarView.centerYAnchor),
            bottomInfoButton.trailingAnchor.constraint(equalTo: bottomBarView.trailingAnchor, constant: -8),
            bottomInfoButton.centerYAnchor.constraint(equalTo: bottomBarView.centerYAnchor),
            bottomInfoButton.widthAnchor.constraint(equalToConstant: 22),
            bottomInfoButton.heightAnchor.constraint(equalToConstant: 22),
            filmstripCenterXConstraint,
            // 胶卷条压在下边栏上方，不遮住 1 / 1 这一行状态。
            filmstripOverlayView.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor, constant: -14),
            filmstripWidthConstraint,
            filmstripOverlayView.heightAnchor.constraint(equalToConstant: Self.filmstripOverlayHeight),
            filmstripOverlayView.leadingAnchor.constraint(greaterThanOrEqualTo: canvas.leadingAnchor, constant: 16),
            filmstripTrailingConstraint,
            filmstripView.leadingAnchor.constraint(equalTo: filmstripOverlayView.contentView.leadingAnchor, constant: 10),
            filmstripView.trailingAnchor.constraint(equalTo: filmstripOverlayView.contentView.trailingAnchor, constant: -10),
            filmstripView.topAnchor.constraint(equalTo: filmstripOverlayView.contentView.topAnchor, constant: 10),
            filmstripView.bottomAnchor.constraint(equalTo: filmstripSlider.topAnchor, constant: -6),
            filmstripSlider.leadingAnchor.constraint(equalTo: filmstripOverlayView.contentView.leadingAnchor, constant: 14),
            filmstripSlider.trailingAnchor.constraint(equalTo: filmstripOverlayView.contentView.trailingAnchor, constant: -14),
            filmstripSlider.bottomAnchor.constraint(equalTo: filmstripOverlayView.contentView.bottomAnchor, constant: -8),
            pageNavigationOverlayView.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            pageNavigationOverlayView.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            pageNavigationOverlayView.topAnchor.constraint(equalTo: titleBarView.bottomAnchor),
            pageNavigationOverlayView.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor),
            cropOverlay.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            cropOverlay.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            cropOverlay.topAnchor.constraint(equalTo: canvas.topAnchor),
            cropOverlay.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
            cropControlsView.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            cropControlsView.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor, constant: -24)
        ])
    }

    @objc func renameCurrentImage(_ sender: Any?) {
        cancelCrop(nil)
        guard let item = viewModel.navigationState?.currentItem else {
            NSSound.beep()
            return
        }

        let alert = NSAlert()
        alert.messageText = AppStrings.text("viewer.rename.title")
        alert.informativeText = AppStrings.text("viewer.rename.message")
        let textField = NSTextField(string: item.url.deletingPathExtension().lastPathComponent)
        textField.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = textField
        alert.addButton(withTitle: AppStrings.text("viewer.rename.button"))
        alert.addButton(withTitle: AppStrings.text("viewer.rename.cancel"))

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = textField.stringValue
        confirmUnsavedEditsIfNeeded(for: .renaming) { [weak self] in
            self?.viewModel.renameCurrent(to: newName)
        }
    }

    @objc func revealCurrentImageInFinder(_ sender: Any?) {
        viewModel.revealCurrentInFinder()
    }

    /// 双击标题栏。行为跟随「系统设置 — 桌面与程序坞 — 双击标题栏来」，
    /// 和其他应用保持一致，不写死成放大。
    enum TitleBarDoubleClickAction: Equatable {
        case zoom
        case minimize
        case none

        /// 该键在全局域里，没设过时系统按放大处理。
        static func fromSystemPreference(_ rawValue: String?) -> TitleBarDoubleClickAction {
            switch rawValue {
            case "Minimize": .minimize
            case "None": .none
            default: .zoom
            }
        }
    }

    @objc func toggleWindowZoom(_ sender: Any?) {
        let action = TitleBarDoubleClickAction.fromSystemPreference(
            UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")
        )
        switch action {
        case .zoom:
            window?.zoom(sender)
        case .minimize:
            window?.miniaturize(sender)
        case .none:
            break
        }
    }

    @objc func copyCurrentImagePath(_ sender: Any?) {
        viewModel.copyCurrentPathToPasteboard()
    }

    @objc func copyCurrentImage(_ sender: Any?) {
        viewModel.copyCurrentImageToPasteboard()
    }

    @objc func copyCurrentImageFile(_ sender: Any?) {
        viewModel.copyCurrentFileToPasteboard()
    }

    @objc func openCurrentImageWithApplication(_ sender: Any?) {
        guard let applicationURL = (sender as? NSMenuItem)?.representedObject as? URL else { return }
        viewModel.openCurrentImage(withApplicationAt: applicationURL)
    }

    /// 每次右击都重建菜单，「打开方式」的候选应用随当前文件的格式变化。
    func makeImageContextMenu() -> NSMenu? {
        guard !isFolderBrowserMode, viewModel.navigationState?.currentItem != nil else { return nil }
        return ImageContextMenuBuilder.makeMenu(
            target: self,
            openWithApplications: viewModel.applicationURLsForCurrentImage()
        )
    }

    @objc func moveCurrentImageToTrash(_ sender: Any?) {
        cancelCrop(nil)
        guard confirmMoveCurrentImageToTrash() else { return }
        confirmUnsavedEditsIfNeeded(for: .movingToTrash) { [weak self] in
            self?.viewModel.moveCurrentToTrash()
        }
    }

    /// 旋转在两种状态下含义不同。
    ///
    /// 查看时只把画面转过来看，不动文件，也不产生待保存的修改。
    /// 进了编辑模式才是真的改像素，走 undo/redo 和保存流程。
    @objc func rotateClockwise(_ sender: Any?) {
        if isEditingImage {
            performEdit(.rotateClockwise)
        } else {
            rotateViewOnly(by: 1)
        }
    }

    @objc func rotateCounterClockwise(_ sender: Any?) {
        if isEditingImage {
            performEdit(.rotateCounterClockwise)
        } else {
            rotateViewOnly(by: -1)
        }
    }

    /// 翻转会改变像素，只在编辑模式里提供，控制条上有按钮。
    @objc func mirrorHorizontal(_ sender: Any?) {
        performEdit(.mirrorHorizontal)
    }

    @objc func mirrorVertical(_ sender: Any?) {
        performEdit(.mirrorVertical)
    }

    /// 测试用：绕过界面直接施加一次编辑，用来造出待保存状态。
    func performEditForTesting(_ operation: EditOperation) {
        performEdit(operation)
    }

    func setEditDestinationChoiceForTesting(_ choice: EditDestinationChoice?) {
        editDestinationChoiceForTesting = choice
    }

    private func rotateViewOnly(by quarterTurns: Int) {
        guard viewModel.currentImage != nil, !settings.usesContinuousReading else {
            NSSound.beep()
            return
        }
        canvas.viewRotationQuarterTurns += quarterTurns
        updateZoomStatus()
    }

    /// 进入编辑模式。裁切框和编辑控制条一起出现。
    @objc func startEditingImage(_ sender: Any?) {
        guard !settings.usesContinuousReading,
              viewModel.canEditCurrentImage,
              !isEditingImage else {
            NSSound.beep()
            return
        }

        // 查看时的旋转只是看的角度，进编辑先归零，
        // 否则裁切框的坐标和真实像素对不上。
        canvas.viewRotationQuarterTurns = 0
        guard let imageDrawRect = canvas.imageDrawRect else {
            NSSound.beep()
            return
        }

        isEditingImage = true
        cropOverlay.aspectRatio = cropAspectRatio
        cropOverlay.beginCropping(in: imageDrawRect)
        updateFilmstripVisibility()
        updateEditControls()
        window?.makeFirstResponder(cropOverlay)
    }

    /// 兼容旧的菜单项与快捷键，语义已经是「编辑图片」。
    @objc func startCropping(_ sender: Any?) {
        startEditingImage(sender)
    }

    /// 标题栏那颗按钮按第二下就退出编辑，不用再去按取消。
    @objc func toggleImageEditing(_ sender: Any?) {
        if isEditingImage {
            cancelCrop(sender)
        } else {
            startEditingImage(sender)
        }
    }

    /// 编辑按钮什么时候可按：有图、能改、不在文件夹网格里、也不在连续阅读里。
    static func canEditFromTitleBar(
        canEditCurrentImage: Bool,
        isFolderBrowserMode: Bool,
        usesContinuousReading: Bool
    ) -> Bool {
        canEditCurrentImage && !isFolderBrowserMode && !usesContinuousReading
    }

    @objc func applyCrop(_ sender: Any?) {
        guard viewModel.canEditCurrentImage, cropOverlay.isCropping else {
            NSSound.beep()
            return
        }

        // 选区和整张图一样大就说明用户只做了旋转翻转，不必再裁一刀。
        if let pixelCropRect = canvas.pixelCropRect(for: cropOverlay.cropRect),
           !Self.cropCoversWholeImage(pixelCropRect, imageSize: viewModel.currentImagePixelSize) {
            performEdit(.crop(pixelCropRect))
        }

        exitEditMode()
        promptToPersistEditsIfNeeded()
    }

    static func cropCoversWholeImage(_ rect: CGRect, imageSize: CGSize?) -> Bool {
        guard let imageSize, imageSize.width > 0, imageSize.height > 0 else { return false }
        let tolerance: CGFloat = 1
        return rect.minX <= tolerance
            && rect.minY <= tolerance
            && rect.width >= imageSize.width - tolerance * 2
            && rect.height >= imageSize.height - tolerance * 2
    }

    @objc func cancelCrop(_ sender: Any?) {
        exitEditMode()
    }

    private func exitEditMode() {
        isEditingImage = false
        cropOverlay.endCropping()
        updateEditControls()
        window?.makeFirstResponder(canvas)
    }

    func changeCropAspectRatio(_ ratio: CropAspectRatio) {
        cropAspectRatio = ratio
        cropOverlay.aspectRatio = ratio
        updateEditControls()
    }

    @objc func saveEdits(_ sender: Any?) {
        guard viewModel.canEditCurrentImage else {
            NSSound.beep()
            return
        }
        _ = viewModel.saveCurrentEdits()
    }

    @objc func saveEditsAs(_ sender: Any?) {
        guard viewModel.canEditCurrentImage, viewModel.hasUnsavedEdits else {
            NSSound.beep()
            return
        }

        let formats = ImageEditingService.writableSaveFormats()
        let panel = NSSavePanel()
        panel.allowedContentTypes = formats.compactMap(\.contentType)
        // 默认落在原图所在目录，文件名是原名加 _1，被占用就往后数。
        if let currentURL = viewModel.navigationState?.currentItem?.url {
            let proposed = SaveAsNaming.proposedURL(for: currentURL)
            panel.directoryURL = proposed.deletingLastPathComponent()
            panel.nameFieldStringValue = proposed.lastPathComponent
        } else {
            let baseName = URL(fileURLWithPath: viewModel.currentFilename)
                .deletingPathExtension().lastPathComponent
            panel.nameFieldStringValue = "\(baseName)_1.png"
        }
        guard panel.runModal() == .OK,
              let url = panel.url,
              let format = SupportedImageFormat(fileExtension: url.pathExtension) else {
            return
        }
        _ = viewModel.saveCurrentEdits(to: url, format: format)
    }

    @objc func discardEdits(_ sender: Any?) {
        guard viewModel.currentImage != nil else {
            NSSound.beep()
            return
        }
        _ = viewModel.discardCurrentEdits()
    }

    @objc func undoEdit(_ sender: Any?) {
        if !viewModel.undoEdit() { NSSound.beep() }
    }

    @objc func redoEdit(_ sender: Any?) {
        if !viewModel.redoEdit() { NSSound.beep() }
    }

    @objc func toggleFilmstrip(_ sender: Any?) {
        settings.showsFilmstrip.toggle()
        syncFilmstripContent(navigationState: viewModel.navigationState)
        updateFilmstripVisibility()
        updateTitleBarControlAvailability()
    }

    @objc func toggleInspector(_ sender: Any?) {
        settings.showsInspector.toggle()
    }

    @objc func toggleContinuousReading(_ sender: Any?) {
        guard !cropOverlay.isCropping else {
            NSSound.beep()
            return
        }
        settings.usesContinuousReading.toggle()
    }

    @objc func showPreviousImage(_ sender: Any?) {
        navigateToPreviousImage()
    }

    @objc func showNextImage(_ sender: Any?) {
        navigateToNextImage()
    }

    @objc func actualSize(_ sender: Any?) {
        canvas.zoomToActualSize()
    }

    @objc func zoomToFit(_ sender: Any?) {
        canvas.resetViewTransform()
    }

    @objc func zoomToFitWidth(_ sender: Any?) {
        canvas.zoomToFitWidth()
    }

    @objc private func setZoomPercentage(_ sender: NSMenuItem) {
        canvas.setManualPercentage(CGFloat(sender.tag))
    }

    @objc private func setCustomZoomPercentage(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = AppStrings.text("viewer.zoom.custom.title")
        alert.informativeText = AppStrings.text("viewer.zoom.custom.message")
        let currentPercentage = Int(((canvas.pixelScale ?? 1) * 100).rounded())
        let field = NSTextField(string: "\(currentPercentage)")
        field.frame = NSRect(x: 0, y: 0, width: 180, height: 24)
        field.setAccessibilityLabel(AppStrings.text("viewer.zoom.custom.field"))
        alert.accessoryView = field
        alert.addButton(withTitle: AppStrings.text("viewer.zoom.custom.apply"))
        alert.addButton(withTitle: AppStrings.text("viewer.zoom.custom.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn,
              let percentage = Double(field.stringValue),
              percentage.isFinite,
              percentage >= 10,
              percentage <= 1_200 else {
            return
        }
        canvas.setManualPercentage(CGFloat(percentage))
    }

    @objc private func showZoomMenu(_ sender: Any?) {
        let menu = NSMenu()
        let fitItem = NSMenuItem(
            title: AppStrings.text("menu.view.zoomToFit"),
            action: #selector(zoomToFit(_:)),
            keyEquivalent: ""
        )
        fitItem.target = self
        fitItem.state = canvas.displayMode == .fit ? .on : .off
        menu.addItem(fitItem)
        let fitWidthItem = NSMenuItem(
            title: AppStrings.text("menu.view.zoomToFitWidth"),
            action: #selector(zoomToFitWidth(_:)),
            keyEquivalent: ""
        )
        fitWidthItem.target = self
        fitWidthItem.state = canvas.displayMode == .fitWidth ? .on : .off
        menu.addItem(fitWidthItem)
        menu.addItem(.separator())

        for percentage in [50, 100, 200] {
            let item = NSMenuItem(
                title: "\(percentage)%",
                action: #selector(setZoomPercentage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = percentage
            if canvas.displayMode == .manual,
               let pixelScale = canvas.pixelScale,
               abs(pixelScale * 100 - CGFloat(percentage)) < 0.5 {
                item.state = .on
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let customItem = NSMenuItem(
            title: AppStrings.text("viewer.zoom.custom.menu"),
            action: #selector(setCustomZoomPercentage(_:)),
            keyEquivalent: ""
        )
        customItem.target = self
        menu.addItem(customItem)

        let location = NSPoint(x: bottomZoomLabel.bounds.minX, y: bottomZoomLabel.bounds.maxY + 4)
        menu.popUp(positioning: nil, at: location, in: bottomZoomLabel)
    }

    @objc func browseCurrentImageFolder(_ sender: Any?) {
        if case .folder = currentRoute {
            guard let viewerRoute = associatedViewerRoute() else {
                NSSound.beep()
                return
            }
            showRoute(viewerRoute, recordHistory: false)
            return
        }

        guard let viewerURL = currentViewerURL else {
            NSSound.beep()
            return
        }
        let folderURL = viewerURL.deletingLastPathComponent().standardizedFileURL
        associatedViewerURL = viewerURL.standardizedFileURL
        if folderBrowserViewModel.session?.folderURL.standardizedFileURL == folderURL {
            showRoute(.folder(folderURL), recordHistory: false)
            return
        }

        currentRoute = .folder(folderURL)
        enterFolderBrowserMode()
        invalidateFolderRetry()
        Task { [weak self] in
            guard let self else { return }
            await self.folderBrowserViewModel.openFolder(folderURL)
        }
    }

    private var currentViewerURL: URL? {
        if case let .viewer(url) = currentRoute {
            return url
        }
        return displayedItemURL
    }

    private func associatedViewerRoute(folderState: FolderRouteState? = nil) -> ContentRoute? {
        if let associatedViewerURL {
            return .viewer(associatedViewerURL)
        }
        let folderState = folderState ?? FolderRouteState(
            session: folderBrowserViewModel.session,
            isLoading: folderBrowserViewModel.isLoading
        )
        let matchingLoadedSession: FolderSession?
        if case let .folder(folderURL) = currentRoute,
           !folderState.isLoading,
           let session = folderState.session,
           session.folderURL.standardizedFileURL == folderURL.standardizedFileURL {
            matchingLoadedSession = session
        } else {
            matchingLoadedSession = nil
        }

        if let displayedItemURL {
            let displayedURL = displayedItemURL.standardizedFileURL
            if matchingLoadedSession == nil || matchingLoadedSession?.items.contains(where: {
                $0.url.standardizedFileURL == displayedURL
            }) == true {
                return .viewer(displayedURL)
            }
        }
        if let lastOpenedItemID = matchingLoadedSession?.lastOpenedItemID,
           let item = matchingLoadedSession?.items.first(where: { $0.id == lastOpenedItemID }) {
            return .viewer(item.url.standardizedFileURL)
        }
        if case let .viewer(url)? = backRoute ?? forwardRoute {
            return .viewer(url)
        }
        return nil
    }

    private func openFolderBrowserItem(_ item: ImageItem) {
        confirmUnsavedEditsIfNeeded(for: .opening) { [weak self] in
            guard let self else { return }
            self.folderBrowserViewModel.recordOpenedItem(item)
            self.associatedViewerURL = item.url.standardizedFileURL
            self.showRoute(.viewer(item.url.standardizedFileURL), recordHistory: true)
            self.hasAssignedOpenRequest = true
            self.openImageUsingExistingPipeline(item.url)
        }
    }

    private func applyFolderItemURLMutation(_ mutation: FolderItemURLMutation) {
        switch mutation {
        case let .removed(urls):
            let standardizedURLs = Set(urls.map(\.standardizedFileURL))
            let currentViewerWasRemoved: Bool
            if case let .viewer(url) = currentRoute {
                currentViewerWasRemoved = standardizedURLs.contains(url.standardizedFileURL)
            } else {
                currentViewerWasRemoved = false
            }
            backRoute = removingViewerRoute(backRoute, matchingAny: standardizedURLs)
            forwardRoute = removingViewerRoute(forwardRoute, matchingAny: standardizedURLs)
            if let associatedViewerURL,
               standardizedURLs.contains(associatedViewerURL.standardizedFileURL) {
                self.associatedViewerURL = nil
            }
            let replacementURL = viewModel.removeItemsFromNavigation(standardizedURLs)
            if currentViewerWasRemoved {
                currentRoute = replacementURL.map(ContentRoute.viewer)
            }
        case let .renamed(migrations):
            let standardizedMigrations = Dictionary(
                uniqueKeysWithValues: migrations.map {
                    ($0.key.standardizedFileURL, $0.value.standardizedFileURL)
                }
            )
            currentRoute = migratingViewerRoute(currentRoute, using: standardizedMigrations)
            backRoute = migratingViewerRoute(backRoute, using: standardizedMigrations)
            forwardRoute = migratingViewerRoute(forwardRoute, using: standardizedMigrations)
            if let associatedViewerURL,
               let destination = standardizedMigrations[associatedViewerURL.standardizedFileURL] {
                self.associatedViewerURL = destination
            }
            viewModel.applyItemURLMigrations(standardizedMigrations)
        }
    }

    private func presentRecoveryRequiredAlert(folderURL: URL, failures: [BatchRecoveryFailure]) {
        let presentation = Self.recoveryAlertPresentation(folderURL: folderURL, failures: failures)
        if let recoveryAlertPresenterForTesting {
            recoveryAlertPresenterForTesting(presentation)
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = presentation.title
        alert.informativeText = presentation.message
        alert.addButton(withTitle: AppStrings.text("common.ok"))

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 180))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = presentation.details
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )
        scrollView.documentView = textView
        alert.accessoryView = scrollView

        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func presentBatchOperationDetails(_ details: String) {
        let alert = NSAlert()
        alert.messageText = AppStrings.text("folderBrowser.operation.detailsTitle")
        alert.addButton(withTitle: AppStrings.text("common.ok"))
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 180))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = details
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        alert.accessoryView = scrollView
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private static func recoveryAlertPresentation(
        folderURL: URL,
        failures: [BatchRecoveryFailure]
    ) -> RecoveryAlertPresentation {
        let detailLines = failures.flatMap { failure -> [String] in
            let detail = String(
                format: AppStrings.text("folderBrowser.recovery.item"),
                failure.expectedURL.lastPathComponent,
                failure.actualURL.lastPathComponent,
                failure.reason
            )
            guard failure.actualURL.lastPathComponent.hasPrefix(".batch-rename-"),
                  failure.actualURL.pathExtension == "tmp" else {
                return [detail]
            }
            return [detail, AppStrings.text("folderBrowser.recovery.hiddenTemporaryHint")]
        }
        return RecoveryAlertPresentation(
            folderURL: folderURL,
            title: AppStrings.text("folderBrowser.recovery.alert.title"),
            message: String(
                format: AppStrings.text("folderBrowser.recovery.alert.folder"),
                folderURL.path
            ),
            details: detailLines.joined(separator: "\n")
        )
    }

    private func migratingViewerRoute(_ route: ContentRoute?, using migrations: [URL: URL]) -> ContentRoute? {
        guard case let .viewer(url) = route,
              let destination = migrations[url.standardizedFileURL] else {
            return route
        }
        return .viewer(destination)
    }

    private func removingViewerRoute(_ route: ContentRoute?, matchingAny removedURLs: Set<URL>) -> ContentRoute? {
        guard case let .viewer(url) = route,
              removedURLs.contains(url.standardizedFileURL) else {
            return route
        }
        return nil
    }

    private func showRoute(_ route: ContentRoute, recordHistory: Bool) {
        if recordHistory, currentRoute != route {
            backRoute = currentRoute
            forwardRoute = nil
        }
        currentRoute = route
        switch route {
        case .viewer:
            exitFolderBrowserMode()
        case .folder:
            enterFolderBrowserMode()
        }
    }

    private func goBack() {
        guard let target = backRoute, target != currentRoute else { return }
        let previousRoute = currentRoute
        backRoute = nil
        forwardRoute = previousRoute
        showRoute(target, recordHistory: false)
    }

    private func goForward() {
        guard let target = forwardRoute, target != currentRoute else { return }
        let previousRoute = currentRoute
        forwardRoute = nil
        backRoute = previousRoute
        showRoute(target, recordHistory: false)
    }

    private func moveSelectedFolderBrowserItemsToTrash() {
        let selectedItems = folderBrowserViewModel.selectedItems
        guard !selectedItems.isEmpty else {
            NSSound.beep()
            return
        }

        let confirmed = batchActionDialogProviderForTesting?.confirmTrash?(selectedItems.count)
            ?? confirmMoveSelectedFolderBrowserItemsToTrash(count: selectedItems.count)
        guard confirmed else { return }

        confirmUnsavedEditsForSelectedViewerIfNeeded(selectedItems, transition: .movingToTrash) { [weak self] in
            self?.folderBrowserViewModel.moveSelectedToTrash()
        }
    }

    private func moveSelectedFolderBrowserItemsToFolder() {
        let selectedItems = folderBrowserViewModel.selectedItems
        guard !selectedItems.isEmpty else {
            NSSound.beep()
            return
        }

        let destination = batchActionDialogProviderForTesting?.chooseDestinationFolder?()
            ?? chooseDestinationFolderForBatchMove()
        guard let destination else { return }

        guard let skipPlan = folderBrowserViewModel.planSelectedMove(
            to: destination,
            conflictPolicy: .skip
        ) else { return }

        let choice: MoveConflictChoice
        if skipPlan.conflictingNames.isEmpty {
            choice = .skipConflicts
        } else {
            choice = batchActionDialogProviderForTesting?.chooseMoveConflict?(skipPlan.conflictingNames)
                ?? chooseMoveConflict(names: skipPlan.conflictingNames)
        }
        guard choice != .cancel else { return }

        confirmUnsavedEditsForSelectedViewerIfNeeded(selectedItems, transition: .navigating) { [weak self] in
            guard let self else { return }
            switch choice {
            case .skipConflicts:
                self.folderBrowserViewModel.executeMovePlan(skipPlan)
            case .keepBoth:
                guard let keepBothPlan = self.folderBrowserViewModel.planSelectedMove(
                    to: destination,
                    conflictPolicy: .keepBoth
                ) else { return }
                self.folderBrowserViewModel.executeMovePlan(keepBothPlan)
            case .cancel:
                break
            }
        }
    }

    private func confirmUnsavedEditsForSelectedViewerIfNeeded(
        _ selectedItems: [ImageItem],
        transition: UnsavedChangesTransition,
        perform action: () -> Void
    ) {
        let selectedURLs = Set(selectedItems.map { $0.url.standardizedFileURL })
        guard let viewerURL = viewModel.navigationState?.currentItem?.url.standardizedFileURL,
              selectedURLs.contains(viewerURL) else {
            action()
            return
        }
        confirmUnsavedEditsIfNeeded(for: transition, perform: action)
    }

    private func renameSelectedFolderBrowserItems() {
        let selectedItems = folderBrowserViewModel.selectedItems
        guard !selectedItems.isEmpty else {
            NSSound.beep()
            return
        }

        let folderBrowserViewModel = self.folderBrowserViewModel
        let planRename: BatchRenameSheetController.PlanRename = { urls, baseName, startNumber, padding in
            folderBrowserViewModel.planBatchRename(
                urls: urls,
                baseName: baseName,
                startNumber: startNumber,
                padding: padding
            )
        }
        let confirm: (BatchRenameSheetController.RenameParameters, BatchRenamePlan) -> Void = { [weak self] _, plan in
            guard let self else { return }
            self.confirmUnsavedEditsForSelectedViewerIfNeeded(selectedItems, transition: .renaming) {
                self.folderBrowserViewModel.executeRenamePlan(plan)
            }
        }

        if let requestRenameParameters = batchActionDialogProviderForTesting?.requestRenameParameters {
            requestRenameParameters(selectedItems, planRename, confirm)
        } else {
            showBatchRenameSheet(items: selectedItems, planRename: planRename, onConfirm: confirm)
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = LocalEventMonitor(mask: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else {
                return event
            }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        keyMonitor.invalidate()
        self.keyMonitor = nil
    }

    /// 浮动的信息栏点到别处就收起来。
    ///
    /// 它是一块盖在图片上的临时面板，看完就该让开。停靠成侧栏的那种是常驻的，
    /// 不参与这条规则。事件只看不拦，点下去该做什么照做。
    private func installOutsideClickMonitor() {
        outsideClickMonitor?.invalidate()
        outsideClickMonitor = LocalEventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            self.dismissFloatingInspectorIfClickedOutside(event)
            return event
        }
    }

    private func dismissFloatingInspectorIfClickedOutside(_ event: NSEvent) {
        guard settings.showsInspector, !isInspectorDocked, !inspectorView.isHidden else { return }
        guard let hitView = rootView.hitTest(rootView.convert(event.locationInWindow, from: nil)) else { return }
        guard Self.shouldDismissFloatingInspector(
            hitViewIsInsideInspector: hitView.isDescendant(of: inspectorView),
            hitViewIsTheInspectorToggle: hitView.isDescendant(of: bottomInfoButton)
        ) else { return }
        settings.showsInspector = false
    }

    /// 点在面板自己身上不收；点在那颗开关上也不收，
    /// 否则这里先关掉、开关再打开，按下去就像没反应。
    static func shouldDismissFloatingInspector(
        hitViewIsInsideInspector: Bool,
        hitViewIsTheInspectorToggle: Bool
    ) -> Bool {
        !hitViewIsInsideInspector && !hitViewIsTheInspectorToggle
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        hideUsageHint()
        revealFullScreenChromeIfNeeded()
        switch Self.keyAction(
            for: event.keyCode,
            shouldEndEditing: shouldEndEditing(for: event),
            isCropping: cropOverlay.isCropping,
            modifierFlags: event.modifierFlags,
            isFolderBrowserMode: isFolderBrowserMode
        ) {
        case .showPrevious:
            navigateToPreviousImage()
            return true
        case .showNext:
            navigateToNextImage()
            return true
        case .closeWindow:
            window?.performClose(nil)
            return true
        case .moveToTrash:
            guard confirmMoveCurrentImageToTrash() else { return true }
            confirmUnsavedEditsIfNeeded(for: .movingToTrash) { [weak self] in
                self?.viewModel.moveCurrentToTrash()
            }
            return true
        case .toggleZoom:
            canvas.toggleFitOrActualSize()
            return true
        case .toggleFullscreen:
            window?.toggleFullScreen(nil)
            return true
        case .startCropping:
            startCropping(nil)
            return true
        case .applyCrop:
            applyCrop(nil)
            return true
        case .cancelCrop:
            cancelCrop(nil)
            return true
        case .endEditing:
            window?.endEditing(for: nil)
            return true
        case .passThrough:
            return false
        }
    }

    private func shouldEndEditing(for event: NSEvent) -> Bool {
        guard event.keyCode == 53,
              let window,
              let responder = window.firstResponder else {
            return false
        }

        return responder is NSText || responder is NSTextView
    }

    static func keyAction(
        for keyCode: UInt16,
        shouldEndEditing: Bool,
        isCropping: Bool = false,
        modifierFlags: NSEvent.ModifierFlags = [],
        isFolderBrowserMode: Bool = false
    ) -> KeyAction {
        if keyCode == 13, modifierFlags.contains(.command) {
            return .closeWindow
        }

        if isFolderBrowserMode {
            switch keyCode {
            case 53:
                return shouldEndEditing ? .endEditing : .passThrough
            default:
                return .passThrough
            }
        }

        if isCropping {
            switch keyCode {
            case 36:
                return .applyCrop
            case 53:
                return .cancelCrop
            default:
                break
            }
        }

        switch keyCode {
        case 123:
            return .showPrevious
        case 124:
            return .showNext
        case 51:
            return .moveToTrash
        case 49:
            return .toggleZoom
        case 40 where modifierFlags.contains(.command):
            return .startCropping
        case 36:
            return .toggleFullscreen
        case 53:
            return shouldEndEditing ? .endEditing : .passThrough
        default:
            return .passThrough
        }
    }

    static func shouldRefreshCurrentFileOnWindowActivation() -> Bool {
        true
    }

    static func isDirectoryURL(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    static func shouldResetCanvasTransform(from previousURL: URL?, to newURL: URL?) -> Bool {
        previousURL?.standardizedFileURL != newURL?.standardizedFileURL
    }

    static func resolveUnsavedChanges(choice: UnsavedChangesChoice, saveSucceeded: Bool) -> UnsavedChangesResolution {
        switch choice {
        case .save:
            return saveSucceeded ? .proceed : .stayOnCurrentImage
        case .discard:
            return .proceed
        case .cancel:
            return .stayOnCurrentImage
        }
    }

    static func menuCommand(for action: Selector?) -> MenuCommand? {
        switch action {
        case #selector(renameCurrentImage(_:)),
             #selector(revealCurrentImageInFinder(_:)),
             #selector(copyCurrentImagePath(_:)),
             #selector(copyCurrentImageFile(_:)),
             #selector(openCurrentImageWithApplication(_:)),
             #selector(moveCurrentImageToTrash(_:)):
            return .fileOperationRequiringCurrentItem
        case #selector(copyCurrentImage(_:)):
            return .copyImage
        case #selector(showPreviousImage(_:)), #selector(showNextImage(_:)):
            return .navigation
        case #selector(actualSize(_:)), #selector(zoomToFit(_:)), #selector(zoomToFitWidth(_:)):
            return .canvasSizing
        case #selector(startCropping(_:)):
            return .startCropping
        case #selector(rotateClockwise(_:)):
            return .editOperation(.rotateClockwise)
        case #selector(rotateCounterClockwise(_:)):
            return .editOperation(.rotateCounterClockwise)
        case #selector(mirrorHorizontal(_:)):
            return .editOperation(.mirrorHorizontal)
        case #selector(mirrorVertical(_:)):
            return .editOperation(.mirrorVertical)
        case #selector(saveEdits(_:)):
            return .saveEdits
        case #selector(saveEditsAs(_:)):
            return .saveEditsAs
        case #selector(discardEdits(_:)):
            return .discardEdits
        case #selector(undoEdit(_:)):
            return .undoEdit
        case #selector(redoEdit(_:)):
            return .redoEdit
        default:
            return nil
        }
    }

    static func isMenuCommandEnabled(
        _ command: MenuCommand,
        hasCurrentItem: Bool,
        hasCurrentImage: Bool,
        canEditCurrentImage: Bool,
        hasUnsavedEdits: Bool,
        isFolderBrowserMode: Bool = false
    ) -> Bool {
        if isFolderBrowserMode {
            return false
        }

        switch command {
        case .fileOperationRequiringCurrentItem:
            return hasCurrentItem
        case .copyImage:
            return hasCurrentImage
        case .navigation:
            return hasCurrentItem
        case .canvasSizing:
            return hasCurrentImage
        case .startCropping:
            return canEditCurrentImage
        case .editOperation:
            return canEditCurrentImage
        case .saveEdits, .saveEditsAs:
            return canEditCurrentImage && hasUnsavedEdits
        case .discardEdits:
            return hasCurrentImage && hasUnsavedEdits
        case .undoEdit:
            return hasCurrentImage && hasUnsavedEdits
        case .redoEdit:
            return hasCurrentImage
        }
    }

    private func updateDimensionStatus(metadata: ImageMetadata?) {
        bottomDimensionLabel.stringValue = Self.dimensionText(
            pixelWidth: metadata?.pixelWidth,
            pixelHeight: metadata?.pixelHeight
        )
    }

    private func updatePageStatus(navigationState: NavigationState?) {
        bottomPageLabel.stringValue = Self.pageText(navigationState: navigationState)
    }

    private func updateZoomStatus() {
        bottomZoomLabel.stringValue = Self.zoomText(
            displayMode: canvas.displayMode,
            pixelScale: canvas.pixelScale
        )
        bottomZoomLabel.setAccessibilityValue(bottomZoomLabel.stringValue)
    }

    private func updateEditControls() {
        cropControlsView.rootView = EditControlsView(
            aspectRatio: cropAspectRatio,
            onAspectRatioChange: { [weak self] in self?.changeCropAspectRatio($0) },
            onRotateLeft: { [weak self] in self?.performEdit(.rotateCounterClockwise) },
            onRotateRight: { [weak self] in self?.performEdit(.rotateClockwise) },
            onFlipHorizontal: { [weak self] in self?.performEdit(.mirrorHorizontal) },
            onFlipVertical: { [weak self] in self?.performEdit(.mirrorVertical) },
            onCancel: { [weak self] in self?.cancelCrop(nil) },
            onApply: { [weak self] in self?.applyCrop(nil) }
        )
        cropControlsView.isHidden = !cropOverlay.isCropping
        if cropOverlay.isCropping {
            hidePageControls(immediately: true)
        }
        // 标题栏那颗编辑按钮是开关，进出编辑都要跟着亮灭。
        updateTitleBarControlAvailability()
    }

    /// 编辑应用完立刻问一次去向，不再拖到切换图片时才提示。
    private func promptToPersistEditsIfNeeded() {
        guard viewModel.hasUnsavedEdits else { return }
        switch promptForEditDestination() {
        case .overwrite:
            if !viewModel.saveCurrentEdits() { NSSound.beep() }
        case .saveAsNew:
            saveEditsAs(nil)
        case .later:
            break
        }
    }

    enum EditDestinationChoice: Equatable {
        case overwrite
        case saveAsNew
        case later
    }

    private func promptForEditDestination() -> EditDestinationChoice {
        if let editDestinationChoiceForTesting {
            return editDestinationChoiceForTesting
        }
        let alert = NSAlert()
        alert.messageText = AppStrings.text("editDestination.title")
        alert.informativeText = AppStrings.text("editDestination.message")
        alert.addButton(withTitle: AppStrings.text("editDestination.button.overwrite"))
        alert.addButton(withTitle: AppStrings.text("editDestination.button.saveAs"))
        alert.addButton(withTitle: AppStrings.text("editDestination.button.later"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .overwrite
        case .alertSecondButtonReturn: return .saveAsNew
        default: return .later
        }
    }

    private func confirmMoveCurrentImageToTrash() -> Bool {
        guard let item = viewModel.navigationState?.currentItem else {
            NSSound.beep()
            return false
        }
        guard settings.confirmsDelete else { return true }

        let alert = NSAlert()
        alert.messageText = AppStrings.text("viewer.confirmTrash.title")
        alert.informativeText = String(
            format: AppStrings.text("viewer.confirmTrash.message"),
            item.url.lastPathComponent
        )
        alert.addButton(withTitle: AppStrings.text("viewer.confirmTrash.button"))
        alert.addButton(withTitle: AppStrings.text("viewer.confirmTrash.cancel"))

        return alert.runModal() == .alertFirstButtonReturn
    }

    private func confirmMoveSelectedFolderBrowserItemsToTrash(count: Int) -> Bool {
        guard settings.confirmsDelete else { return true }

        let alert = NSAlert()
        alert.messageText = String(format: AppStrings.text("folderBrowser.confirmTrash.title"), count)
        alert.informativeText = AppStrings.text("folderBrowser.confirmTrash.message")
        alert.addButton(withTitle: AppStrings.text("folderBrowser.confirmTrash.button"))
        alert.addButton(withTitle: AppStrings.text("folderBrowser.confirmTrash.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func chooseDestinationFolderForBatchMove() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = AppStrings.text("folderBrowser.movePanel.prompt")
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func chooseMoveConflict(names: [String]) -> MoveConflictChoice {
        let alert = NSAlert()
        alert.messageText = AppStrings.text("folderBrowser.moveConflict.title")
        alert.informativeText = AppStrings.text("folderBrowser.moveConflict.message")
        alert.addButton(withTitle: AppStrings.text("folderBrowser.moveConflict.skip"))
        alert.addButton(withTitle: AppStrings.text("folderBrowser.moveConflict.keepBoth"))
        alert.addButton(withTitle: AppStrings.text("folderBrowser.moveConflict.cancel"))

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 140))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.string = names.joined(separator: "\n")

        let scrollView = NSScrollView(frame: textView.frame)
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView
        alert.accessoryView = scrollView

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .skipConflicts
        case .alertSecondButtonReturn:
            return .keepBoth
        default:
            return .cancel
        }
    }

    private func showBatchRenameSheet(
        items: [ImageItem],
        planRename: @escaping BatchRenameSheetController.PlanRename,
        onConfirm: @escaping (BatchRenameSheetController.RenameParameters, BatchRenamePlan) -> Void
    ) {
        let controller = BatchRenameSheetController(items: items, planRename: planRename)
        controller.onConfirm = { [weak self] parameters, plan in
            onConfirm(parameters, plan)
            self?.activeBatchRenameSheet = nil
        }

        guard controller.window != nil, let window else {
            return
        }
        activeBatchRenameSheet = controller
        controller.beginSheet(on: window) { [weak self] _ in
            self?.activeBatchRenameSheet = nil
        }
    }

    private func applySettings() {
        if cropOverlay.isCropping && settings.usesContinuousReading {
            cancelCrop(nil)
        }
        canvas.backgroundColor = Self.canvasBackgroundColor()
        syncFilmstripContent(navigationState: viewModel.navigationState)
        updateFilmstripVisibility()
        updateInspectorPresentation(hasCurrentImage: viewModel.currentImage != nil)
        bottomInfoButton.state = settings.showsInspector ? .on : .off
        updateDimensionStatus(metadata: viewModel.currentMetadata)
        updatePageStatus(navigationState: viewModel.navigationState)
        updateZoomStatus()
        updateContinuousReadingPresentation()
        updateTitleBarControlAvailability()
    }

    private func syncFilmstripContent(navigationState: NavigationState?) {
        guard settings.showsFilmstrip else {
            filmstripView.apply(items: [], current: nil)
            return
        }
        filmstripView.apply(
            items: navigationState?.items ?? [],
            current: navigationState?.currentItem
        )
        // 条目数变了可滚动性也会变，重算一次滑杆是否可用。
        filmstripView.layoutSubtreeIfNeeded()
        filmstripSlider.doubleValue = Double(filmstripView.scrollProgress)
        updateFilmstripSliderAvailability()
    }

    private func updateContinuousReadingPresentation() {
        let shouldShow = settings.usesContinuousReading
            && viewModel.currentImage != nil
            && !isFolderBrowserMode
        continuousReadingView.isHidden = !shouldShow
        canvas.isHidden = shouldShow || isFolderBrowserMode
        if shouldShow {
            refreshContinuousReadingWindow()
        } else {
            continuousReadingTask?.cancel()
            continuousReadingTask = nil
        }
        bottomZoomLabel.isHidden = shouldShow || isFolderBrowserMode || viewModel.currentImage == nil
    }

    private func refreshContinuousReadingWindow() {
        continuousReadingTask?.cancel()
        let viewModel = viewModel
        let focusedItemID = continuousReadingFocusID ?? viewModel.navigationState?.currentItem?.id
        continuousReadingTask = Task { [weak self, viewModel] in
            let pages = await viewModel.continuousReadingPages(centeredAt: focusedItemID)
            guard !Task.isCancelled, let self, self.settings.usesContinuousReading else { return }
            self.continuousReadingView.apply(
                pages: pages,
                currentItemID: focusedItemID
            )
        }
    }

    private func updateInspector(metadata: ImageMetadata?) {
        inspectorView.rootView = InspectorView(
            metadata: metadata,
            isDocked: isInspectorDocked,
            onToggleDock: { [weak self] in self?.toggleInspectorDock() },
            onClose: { [weak self] in self?.settings.showsInspector = false }
        )
    }

    private func toggleInspectorDock() {
        isInspectorDocked.toggle()
        updateInspector(metadata: viewModel.currentMetadata)
        updateInspectorLayout()
    }

    /// 停靠的信息栏要占掉的横向空间：面板宽度加上它两侧的间距。
    private var reservedInspectorWidth: CGFloat {
        let shouldReserveColumn = isInspectorDocked
            && settings.showsInspector
            && viewModel.currentImage != nil
            && !isFolderBrowserMode
        guard shouldReserveColumn else { return 0 }
        return GlassMetrics.inspectorWidth + GlassMetrics.floatingInset * 2
    }

    /// 信息栏在不在、占不占地方，都取决于开关和当前有没有图。
    private func updateInspectorPresentation(hasCurrentImage: Bool) {
        inspectorView.isHidden = !Self.shouldDisplayInspector(
            isEnabled: settings.showsInspector,
            hasCurrentImage: hasCurrentImage
        )
        updateInspectorLayout()
    }

    private func updateInspectorLayout() {
        // 信息栏永远是一块浮起的圆角玻璃，四周留同样的间距。停靠只表示它常驻，
        // 并且图片往左让出它占的这一条，不再贴到窗口边上。
        inspectorTrailingConstraint?.constant = -GlassMetrics.floatingInset
        inspectorTopConstraint?.constant = GlassMetrics.floatingInset
        inspectorBottomConstraint?.constant = -GlassMetrics.floatingInset
        // 画布始终铺满整窗，模糊底才连成一片，玻璃底下也才有东西可以折射。
        // 图片靠 contentInsets 避开面板，和它避开上下边栏是同一套做法。
        updateCanvasContentInsets(chromeVisible: isChromeVisible)
        // 胶卷条同样要避开那一条，它浮在画布上，不受 contentInsets 影响。
        let reserved = reservedInspectorWidth
        filmstripCenterXConstraint?.constant = -reserved / 2
        filmstripTrailingConstraint?.constant = -(GlassMetrics.floatingInset + reserved)
        rootView.layoutSubtreeIfNeeded()
    }

    /// 胶卷条的显示只由「开关有没有打开」决定。
    ///
    /// 原来它跟着指针走：鼠标不动一会儿就自己收起来，缩放超过一档也收。
    /// 用户把它打开就是想一直看着它，这些自作主张的隐藏只会让人找不到它。
    /// 现在开着就一直在，关掉才收。
    /// `@Published` 在 willSet 时发布，订阅里读 viewModel 拿到的是旧值。
    /// 有图没图由调用方按发过来的值传进来，读属性只是没有订阅上下文时的兜底。
    private func updateFilmstripVisibility(hasLoadedImage: Bool? = nil, animated: Bool = true) {
        let shouldShow = Self.shouldDisplayFilmstripOverlay(
            isEnabled: settings.showsFilmstrip,
            hasLoadedImage: hasLoadedImage ?? (viewModel.currentImage != nil),
            isCropping: cropOverlay.isCropping,
            isFolderBrowserMode: isFolderBrowserMode
        )
        guard shouldShow else {
            hideFilmstripOverlay(immediately: !animated)
            return
        }

        filmstripVisibilityGeneration += 1
        filmstripOverlayView.isHidden = false
        guard filmstripOverlayView.alphaValue < 1 else { return }
        guard animated else {
            filmstripOverlayView.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            filmstripOverlayView.animator().alphaValue = 1
        }
    }

    private func hideFilmstripOverlay(immediately: Bool = false) {
        filmstripVisibilityGeneration += 1
        guard !filmstripOverlayView.isHidden else { return }

        if immediately {
            filmstripOverlayView.alphaValue = 0
            filmstripOverlayView.isHidden = true
            return
        }

        let generation = filmstripVisibilityGeneration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.overlayFadeOutDuration
            filmstripOverlayView.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.filmstripVisibilityGeneration == generation else { return }
                self.filmstripOverlayView.isHidden = true
            }
        }
    }

    private func configureFilmstripSlider() {
        filmstripSlider.translatesAutoresizingMaskIntoConstraints = false
        filmstripSlider.sliderType = .linear
        filmstripSlider.controlSize = .mini
        filmstripSlider.minValue = 0
        filmstripSlider.maxValue = 1
        filmstripSlider.doubleValue = 0
        filmstripSlider.isContinuous = true
        filmstripSlider.target = self
        filmstripSlider.action = #selector(filmstripSliderChanged(_:))
        filmstripSlider.setAccessibilityLabel(AppStrings.text("filmstrip.slider.accessibilityLabel"))
        filmstripSlider.toolTip = AppStrings.text("filmstrip.slider.accessibilityLabel")

        // 滚轮滑动胶卷条时滑杆跟着走，两边保持同步。
        filmstripView.onScrollProgressChanged = { [weak self] progress in
            guard let self, !self.isDraggingFilmstripSlider else { return }
            self.filmstripSlider.doubleValue = Double(progress)
            self.updateFilmstripSliderAvailability()
        }
    }

    @objc private func filmstripSliderChanged(_ sender: NSSlider) {
        isDraggingFilmstripSlider = true
        filmstripView.scrollProgress = CGFloat(sender.doubleValue)
        isDraggingFilmstripSlider = false
    }

    /// 一屏放得下时滑杆没有意义，直接禁用。
    private func updateFilmstripSliderAvailability() {
        filmstripSlider.isEnabled = filmstripView.isScrollable
    }

    /// 换图的过渡。
    ///
    /// 翻页时按方向推入，新画面从指针来的那一侧滑进来，方向感和左右按钮一致。
    /// 不是翻页导致的换图（打开、编辑后重绘）没有方向，退回淡入。
    private func playNavigationTransition(slide: CATransitionSubtype?) {
        canvas.wantsLayer = true
        let transition = CATransition()
        transition.duration = Self.navigationTransitionDuration
        transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
        if let slide {
            transition.type = .push
            transition.subtype = slide
        } else {
            transition.type = .fade
        }
        canvas.layer?.add(transition, forKey: "navigation")
    }

    static let navigationTransitionDuration: CFTimeInterval = 0.24

    private func revealPageControls() {
        guard Self.shouldDisplayPageControls(
            itemCount: viewModel.navigationState?.items.count ?? 0,
            isCropping: cropOverlay.isCropping
        ) else {
            hidePageControls(immediately: true)
            return
        }

        cancelPageControlsAutoHide()
        pageNavigationOverlayView.isHidden = false
        if pageNavigationOverlayView.alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                pageNavigationOverlayView.animator().alphaValue = 1
            }
        }
        schedulePageControlsAutoHide()
    }

    private func cancelPageControlsAutoHide() {
        pageControlsHideTimer?.invalidate()
        pageControlsHideTimer = nil
        pageControlsVisibilityGeneration += 1
    }

    private func schedulePageControlsAutoHide() {
        // 除了进出事件记下的状态，再查一次指针的实际位置。
        // 控件隐藏期间移进来不会有进入事件，只信状态会把停在按钮上的指针漏掉。
        guard Self.shouldAutoHidePageControls(
            pointerIsOverControls: isPointerOverPageControls
                || pageNavigationOverlayView.isPointerOverControls
        ) else { return }
        let generation = pageControlsVisibilityGeneration
        pageControlsHideTimer = Timer.scheduledTimer(
            withTimeInterval: Self.overlayAutoHideDelay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.pageControlsVisibilityGeneration == generation else { return }
                // 到点时指针还压在按钮上就不收，重新计时。
                guard !self.pageNavigationOverlayView.isPointerOverControls else {
                    self.schedulePageControlsAutoHide()
                    return
                }
                self.hidePageControls()
            }
        }
    }

    private func hidePageControls(immediately: Bool = false) {
        cancelPageControlsAutoHide()
        guard !pageNavigationOverlayView.isHidden else { return }

        if immediately {
            pageNavigationOverlayView.alphaValue = 0
            pageNavigationOverlayView.isHidden = true
            return
        }

        let generation = pageControlsVisibilityGeneration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.overlayFadeOutDuration
            pageNavigationOverlayView.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.pageControlsVisibilityGeneration == generation else { return }
                self.pageNavigationOverlayView.isHidden = true
            }
        }
    }

    private func configureContentBars() {
        for bar in [titleBarView, bottomBarView] {
            bar.translatesAutoresizingMaskIntoConstraints = false
            // 用更透的一档玻璃。上下边栏和图片留白区域压着的是同一层模糊底，
            // regular 太厚，边栏会读成另一种材质，和留白那一片对不上。
            bar.glassStyle = .clear
        }

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleBarView.contentView.addSubview(titleLabel)
        let browseCurrentFolderText = Self.titleBarBrowseFolderToolTip()
        configureTitleBarButton(
            titleBarGridButton,
            symbolName: "square.grid.2x2",
            accessibilityDescription: browseCurrentFolderText,
            action: #selector(browseCurrentImageFolder(_:))
        )
        titleBarGridButton.toolTip = browseCurrentFolderText
        titleBarControlsStack.orientation = .horizontal
        titleBarControlsStack.alignment = .centerY
        titleBarControlsStack.distribution = .fill
        titleBarControlsStack.spacing = 2
        titleBarControlsStack.translatesAutoresizingMaskIntoConstraints = false
        titleBarControlsStack.addArrangedSubview(titleBarGridButton)
        let filmstripText = AppStrings.text("menu.view.showFilmstrip")
        configureTitleBarButton(
            titleBarFilmstripButton,
            symbolName: "film",
            accessibilityDescription: filmstripText,
            action: #selector(toggleFilmstrip(_:))
        )
        titleBarFilmstripButton.setAccessibilityRole(.checkBox)
        titleBarControlsStack.addArrangedSubview(titleBarFilmstripButton)
        let editText = AppStrings.text("menu.image.edit")
        configureTitleBarButton(
            titleBarEditButton,
            symbolName: "crop.rotate",
            accessibilityDescription: editText,
            action: #selector(toggleImageEditing(_:))
        )
        titleBarEditButton.setAccessibilityRole(.checkBox)
        titleBarControlsStack.addArrangedSubview(titleBarEditButton)
        let moreText = AppStrings.text("titleBar.more")
        configureTitleBarButton(
            titleBarMoreButton,
            symbolName: "ellipsis.circle",
            accessibilityDescription: moreText,
            action: #selector(showMoreMenu(_:))
        )
        titleBarControlsStack.addArrangedSubview(titleBarMoreButton)
        titleBarView.contentView.addSubview(titleBarControlsStack)
        updateTitleBarControlAvailability()
        titleBarDoubleClickRecognizer.numberOfClicksRequired = 2
        titleBarDoubleClickRecognizer.delegate = self
        titleBarView.addGestureRecognizer(titleBarDoubleClickRecognizer)

        for label in [bottomDimensionLabel, bottomPageLabel, bottomZoomLabel] {
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.maximumNumberOfLines = 1
        }
        bottomDimensionLabel.lineBreakMode = .byTruncatingTail
        bottomDimensionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bottomPageLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        bottomZoomLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        bottomZoomLabel.toolTip = AppStrings.text("viewer.zoom.menu.tooltip")
        bottomZoomLabel.setAccessibilityRole(.button)
        bottomZoomLabel.setAccessibilityLabel(AppStrings.text("viewer.zoom.menu.accessibilityLabel"))
        bottomZoomLabel.addGestureRecognizer(bottomZoomClickRecognizer)
        let showInfoText = AppStrings.text("menu.view.showInfo")
        bottomInfoButton.image = NSImage(systemSymbolName: Self.bottomBarInfoSymbolName, accessibilityDescription: showInfoText)
        bottomInfoButton.bezelStyle = .toolbar
        bottomInfoButton.isBordered = false
        bottomInfoButton.toolTip = showInfoText
        bottomInfoButton.setAccessibilityLabel(showInfoText)
        bottomInfoButton.target = self
        bottomInfoButton.action = #selector(toggleInspector(_:))

        filmstripOverlayView.isHidden = true
        pageNavigationOverlayView.isHidden = true
        folderBrowserView.isHidden = true
    }

    private func configureTitleBarButton(
        _ button: HoverToolbarButton,
        symbolName: String,
        accessibilityDescription: String,
        action: Selector
    ) {
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        )?.withSymbolConfiguration(symbolConfiguration)
        button.toolTip = accessibilityDescription
        button.setAccessibilityLabel(accessibilityDescription)
        button.target = self
        button.action = action
    }

    private func updateTitleBarControlAvailability(
        folderState: FolderRouteState? = nil,
        canEditCurrentImage: Bool? = nil
    ) {
        let canEdit = canEditCurrentImage ?? viewModel.canEditCurrentImage
        titleBarGridButton.isEnabled = canToggleTitleBarGrid(folderState: folderState)
        let gridText: String
        if case .folder = currentRoute {
            gridText = AppStrings.text("titleBar.showImage")
        } else {
            gridText = AppStrings.text("titleBar.showFolder")
        }
        titleBarGridButton.toolTip = gridText
        titleBarGridButton.setAccessibilityLabel(gridText)
        titleBarGridButton.image?.accessibilityDescription = gridText
        // 胶卷开关跟着设置走，打开时按钮着强调色，和右键菜单的勾选一致。
        titleBarFilmstripButton.isEnabled = !isFolderBrowserMode
        titleBarFilmstripButton.isOnState = settings.showsFilmstrip
        titleBarFilmstripButton.setAccessibilityValue(settings.showsFilmstrip)
        // 编辑按钮同样是开关：进了编辑模式就亮着，再按一下退出。
        titleBarEditButton.isEnabled = Self.canEditFromTitleBar(
            canEditCurrentImage: canEdit,
            isFolderBrowserMode: isFolderBrowserMode,
            usesContinuousReading: settings.usesContinuousReading
        ) || isEditingImage
        titleBarEditButton.isOnState = isEditingImage
        titleBarEditButton.setAccessibilityValue(isEditingImage)
    }

    private func updateWindowTitle(viewerTitle: String) {
        let title: String
        let toolTip: String?
        if case .folder(let folderURL) = currentRoute {
            title = folderURL.lastPathComponent
            toolTip = folderURL.path
        } else {
            title = viewerTitle
            toolTip = nil
        }
        window?.title = title
        titleLabel.stringValue = title
        titleLabel.toolTip = toolTip
        titleLabel.setAccessibilityLabel(title)
        titleLabel.setAccessibilityHelp(toolTip)
    }

    /// 三点菜单和右键菜单共用同一份定义，条目、顺序和图标始终一致。
    @objc private func showMoreMenu(_ sender: NSButton) {
        guard let menu = makeImageContextMenu() else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    static func menuItem(in menu: NSMenu?, matching action: Selector) -> NSMenuItem? {
        guard let menu else { return nil }
        for item in menu.items {
            if item.action == action { return item }
            if let match = menuItem(in: item.submenu, matching: action) { return match }
        }
        return nil
    }

    private func canToggleTitleBarGrid(folderState: FolderRouteState?) -> Bool {
        switch currentRoute {
        case .viewer:
            true
        case .folder:
            associatedViewerRoute(folderState: folderState) != nil
        case nil:
            false
        }
    }

    private func startFolderRetry() {
        guard folderRetryTask == nil else { return }
        folderRetryGeneration &+= 1
        let generation = folderRetryGeneration
        let folderBrowserViewModel = folderBrowserViewModel
        folderRetryTask = Task { [weak self, folderBrowserViewModel] in
            guard !Task.isCancelled else { return }
            await folderBrowserViewModel.retryOpenFolder()
            guard let self, self.folderRetryGeneration == generation else { return }
            self.folderRetryTask = nil
        }
    }

    private func stopFolderRetryTask() {
        folderRetryGeneration &+= 1
        folderRetryTask?.cancel()
        folderRetryTask = nil
    }

    private func invalidateFolderRetry() {
        stopFolderRetryTask()
        folderBrowserViewModel.invalidateOpenFolderRequest()
    }

    private func cancelFolderRetry() {
        stopFolderRetryTask()
        folderBrowserViewModel.cancelOpenFolderRequest()
    }

    private static func folderBrowserPresentation(
        session: FolderSession?,
        isLoading: Bool,
        loadErrorMessage: String?
    ) -> FolderBrowserPresentation {
        if isLoading { return .loading }
        if let loadErrorMessage { return .loadFailed(loadErrorMessage) }
        guard let session else { return .loading }
        if session.items.isEmpty { return .emptyFolder }
        if session.visibleItems.isEmpty { return .filteredEmpty }
        return .content
    }

    /// 双击落在标题栏的空白处才缩放窗口。
    ///
    /// 标题栏是一块玻璃面板，内容挂在它内部的容器上，点在空白处命中的是那个
    /// 容器而不是面板本身，按面板本身比对会一直不成立。这里改成反向判断：
    /// 只要落在标题栏范围内，且不在标题文字或右侧那组按钮上，就算空白。
    private func shouldRecognizeTitleBarDoubleClick(hitView: NSView?) -> Bool {
        guard let hitView, hitView.isDescendant(of: titleBarView) else { return false }
        let interactiveViews: [NSView] = [titleLabel, titleBarControlsStack]
        return !interactiveViews.contains { hitView.isDescendant(of: $0) }
    }

    static func canvasBackgroundColor() -> NSColor {
        .windowBackgroundColor
    }

    private func updateEmptyStatePresentation() {
        updateEmptyStatePresentation(
            hasCurrentImage: viewModel.currentImage != nil,
            loadPhase: viewModel.loadPhase,
            hasError: viewModel.errorMessage != nil
        )
    }

    private func updateEmptyStatePresentation(
        hasCurrentImage: Bool,
        loadPhase: ImageLoadPhase,
        hasError: Bool
    ) {
        emptyStateView.isHidden = isFolderBrowserMode || !Self.shouldDisplayEmptyState(
            hasCurrentImage: hasCurrentImage,
            loadPhase: loadPhase,
            hasError: hasError
        )
        errorStateView.isHidden = isFolderBrowserMode || !Self.shouldDisplayErrorState(
            hasCurrentImage: hasCurrentImage,
            hasError: hasError
        )

        let shouldHideStatusContent = isFolderBrowserMode || Self.shouldHideImageStatusContent(
            hasCurrentImage: hasCurrentImage
        )
        for view in [bottomDimensionLabel, bottomPageLabel, bottomZoomLabel, bottomInfoButton] {
            view.isHidden = shouldHideStatusContent
        }
        inspectorView.isHidden = !Self.shouldDisplayInspector(
            isEnabled: settings.showsInspector,
            hasCurrentImage: hasCurrentImage
        ) || isFolderBrowserMode
        if hasCurrentImage && loadPhase == .full && !isFolderBrowserMode {
            showUsageHintIfNeeded()
        } else if !hasCurrentImage || isFolderBrowserMode {
            hideUsageHint()
        }
    }

    private func showUsageHintIfNeeded() {
        guard !settings.hasShownUsageHint, usageHintView.isHidden else { return }
        settings.hasShownUsageHint = true
        usageHintView.alphaValue = 1
        usageHintView.isHidden = false
        NSAccessibility.post(element: usageHintView, notification: .announcementRequested)
        usageHintTimer?.invalidate()
        usageHintTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.hideUsageHint() }
        }
    }

    private func hideUsageHint() {
        usageHintTimer?.invalidate()
        usageHintTimer = nil
        usageHintView.isHidden = true
    }

    private func revealFullScreenChromeIfNeeded() {
        guard isInFullScreen else { return }
        setFullScreenChromeVisible(true)
        fullScreenChromeHideTimer?.invalidate()
        fullScreenChromeHideTimer = Timer.scheduledTimer(
            withTimeInterval: Self.overlayAutoHideDelay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in self?.setFullScreenChromeVisible(false) }
        }
    }

    private func setFullScreenChromeVisible(_ visible: Bool) {
        isChromeVisible = visible
        titleBarHeightConstraint.constant = visible ? Self.titleBarHeight : 0
        bottomBarHeightConstraint.constant = visible ? Self.bottomBarHeight : 0
        titleBarView.isHidden = !visible
        bottomBarView.isHidden = !visible
        updateCanvasContentInsets(chromeVisible: visible)
        rootView.needsLayout = true
    }

    /// 图片要避开的四周空间。画布本身铺满整窗，让出来的只是图片的位置。
    private func updateCanvasContentInsets(chromeVisible: Bool) {
        let insets = NSEdgeInsets(
            top: chromeVisible ? Self.titleBarHeight : 0,
            left: 0,
            bottom: chromeVisible ? Self.bottomBarHeight : 0,
            right: reservedInspectorWidth
        )
        canvas.contentInsets = insets
    }

    private func announceLoadedImageIfNeeded(hasImage: Bool, loadPhase: ImageLoadPhase) {
        guard hasImage, loadPhase == .full,
              let url = viewModel.navigationState?.currentItem?.url.standardizedFileURL else {
            if !hasImage { lastAnnouncedLoadedURL = nil }
            return
        }
        guard lastAnnouncedLoadedURL != url else { return }
        lastAnnouncedLoadedURL = url
        let message = String(
            format: AppStrings.text("viewer.announcement.loaded"),
            url.lastPathComponent
        )
        if let accessibilityAnnouncementHandlerForTesting {
            accessibilityAnnouncementHandlerForTesting(message)
            return
        }
        NSAccessibility.post(
            element: canvas,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }

    private func enterFolderBrowserMode() {
        if cropOverlay.isCropping {
            cropOverlay.endCropping()
            updateEditControls()
        }
        isFolderBrowserMode = true
        canvas.isHidden = true
        continuousReadingView.isHidden = true
        continuousReadingTask?.cancel()
        folderBrowserView.isHidden = false
        emptyStateView.isHidden = true
        errorStateView.isHidden = true
        hideFilmstripOverlay(immediately: true)
        hidePageControls(immediately: true)
        cropOverlay.isHidden = true
        cropControlsView.isHidden = true
        updateEmptyStatePresentation()
        updateInspectorLayout()
    }

    private func exitFolderBrowserMode() {
        guard isFolderBrowserMode || !folderBrowserView.isHidden || canvas.isHidden else { return }
        isFolderBrowserMode = false
        folderBrowserView.isHidden = true
        updateContinuousReadingPresentation()
        updateEmptyStatePresentation()
        updateInspectorLayout()
    }

    static func shouldDisplayEmptyState(
        hasCurrentImage: Bool,
        loadPhase: ImageLoadPhase,
        hasError: Bool
    ) -> Bool {
        !hasCurrentImage && loadPhase == .empty && !hasError
    }

    static func shouldHideImageStatusContent(hasCurrentImage: Bool) -> Bool {
        !hasCurrentImage
    }

    static func shouldDisplayErrorState(hasCurrentImage: Bool, hasError: Bool) -> Bool {
        !hasCurrentImage && hasError
    }

    static func shouldDisplayInspector(isEnabled: Bool, hasCurrentImage: Bool) -> Bool {
        isEnabled && hasCurrentImage
    }

    var isEmptyStateVisibleForTesting: Bool { !emptyStateView.isHidden }
    var isErrorStateVisibleForTesting: Bool { !errorStateView.isHidden }
    var isShowingRecoverableErrorForTesting: Bool {
        viewModel.currentImage == nil && viewModel.errorMessage != nil
    }
    var errorRetryButtonForTesting: NSButton? { errorStateView.retryButtonForTesting }

    var isImageStatusContentHiddenForTesting: Bool {
        [bottomDimensionLabel, bottomPageLabel, bottomZoomLabel, bottomInfoButton]
            .allSatisfy(\.isHidden)
    }

    var isInspectorVisibleForTesting: Bool { !inspectorView.isHidden }
    var hasLoadedImageForTesting: Bool { viewModel.currentImage != nil }
    var canEditCurrentImageForTesting: Bool { viewModel.canEditCurrentImage }
    var currentImageURLForTesting: URL? { viewModel.navigationState?.currentItem?.url }
    var navigationItemCountForTesting: Int { viewModel.navigationState?.items.count ?? 0 }

    func showNextImageForTesting() { navigateToNextImage() }
    var hasUnsavedEditsForTesting: Bool { viewModel.hasUnsavedEdits }
    var isCroppingForTesting: Bool { cropOverlay.isCropping }
    var isFolderBrowserVisibleForTesting: Bool { !folderBrowserView.isHidden }
    var folderBrowserIsOperatingForTesting: Bool { folderBrowserViewModel.isOperating }
    var isCanvasVisibleForTesting: Bool { !canvas.isHidden }
    var canvasForTesting: ImageCanvasView { canvas }
    var titleBarGlassStyleForTesting: NSGlassEffectView.Style { titleBarView.glassStyle }
    var bottomBarGlassStyleForTesting: NSGlassEffectView.Style { bottomBarView.glassStyle }
    var isInspectorDockedForTesting: Bool { isInspectorDocked }
    var reservedInspectorWidthForTesting: CGFloat { reservedInspectorWidth }

    func toggleInspectorDockForTesting() { toggleInspectorDock() }
    var continuousReadingViewForTesting: ContinuousReadingView { continuousReadingView }
    var isFullScreenChromeVisibleForTesting: Bool {
        !titleBarView.isHidden && !bottomBarView.isHidden
    }
    func revealFullScreenChromeForTesting() { revealFullScreenChromeIfNeeded() }
    var isFilmstripVisibleForTesting: Bool { !filmstripOverlayView.isHidden }
    var filmstripOverlayFrameForTesting: NSRect { filmstripOverlayView.frame }
    var inspectorFrameForTesting: NSRect { inspectorView.frame }
    var bottomBarFrameForTesting: NSRect { bottomBarView.frame }
    var titleBarFilmstripButtonForTesting: HoverToolbarButton { titleBarFilmstripButton }
    var titleBarEditButtonForTesting: HoverToolbarButton { titleBarEditButton }
    var hasKeyMonitorForTesting: Bool { keyMonitor != nil }
    var isPageControlsVisibleForTesting: Bool { !pageNavigationOverlayView.isHidden }
    var folderBrowserItemCountForTesting: Int { folderBrowserView.testingItemCount }
    var folderBrowserOperationStatusTextForTesting: String? { folderBrowserView.testingOperationStatusText }
    var folderBrowserPresentationTitleForTesting: String? { folderBrowserView.testingPresentationTitle }
    var titleBarGridButtonForTesting: NSButton { titleBarGridButton }
    var titleBarControlsStackForTesting: NSStackView { titleBarControlsStack }
    var titleBarViewForTesting: NSView { titleBarView }
    var titleBarDoubleClickRecognizerForTesting: NSClickGestureRecognizer { titleBarDoubleClickRecognizer }

    func shouldRecognizeTitleBarDoubleClickForTesting(hitView: NSView) -> Bool {
        shouldRecognizeTitleBarDoubleClick(hitView: hitView)
    }

    func performTitleBarDoubleClickForTesting(hitView: NSView) {
        guard shouldRecognizeTitleBarDoubleClick(hitView: hitView) else { return }
        toggleWindowZoom(nil)
    }

    func requestOpenFromEmptyStateForTesting() {
        emptyStateView.performOpenForTesting()
    }

    func requestBrowseFolderFromEmptyStateForTesting() {
        emptyStateView.performBrowseFolderForTesting()
    }

    func requestOpenFromErrorStateForTesting() {
        errorStateView.performRetryForTesting()
    }

    func openFolderForTesting(_ folderURL: URL, items: [ImageItem]) {
        invalidateFolderRetry()
        hasAssignedOpenRequest = true
        currentRoute = .folder(folderURL.standardizedFileURL)
        associatedViewerURL = nil
        backRoute = nil
        forwardRoute = nil
        enterFolderBrowserMode()
        currentFolderBrowserItems = items
        folderBrowserView.apply(items: items, selectedIDs: [])
    }

    func openFolderForTesting(_ folderURL: URL, scannerItems: [ImageItem]) async {
        invalidateFolderRetry()
        hasAssignedOpenRequest = true
        currentRoute = .folder(folderURL.standardizedFileURL)
        associatedViewerURL = nil
        backRoute = nil
        forwardRoute = nil
        enterFolderBrowserMode()
        await folderBrowserViewModel.openFolder(folderURL)
    }

    func selectFolderBrowserItemsForTesting(_ selectedIDs: [ImageItem.ID]) {
        folderBrowserView.testingSelectItems(with: Set(selectedIDs))
    }

    func triggerFolderBrowserTrashForTesting() {
        folderBrowserView.testingTriggerTrash()
    }

    func triggerFolderBrowserMoveForTesting() {
        folderBrowserView.testingTriggerMove()
    }

    func triggerFolderBrowserRenameForTesting() {
        folderBrowserView.testingTriggerRename()
    }

    func triggerPrimaryFolderBrowserRecoveryForTesting() {
        folderBrowserView.testingTriggerPrimaryRecovery()
    }

    func triggerSecondaryFolderBrowserRecoveryForTesting() {
        folderBrowserView.testingTriggerSecondaryRecovery()
    }

    func requestFolderRetryForTesting() {
        startFolderRetry()
    }

    func openFirstFolderBrowserItemForTesting() {
        guard let firstItem = currentFolderBrowserItems.first else { return }
        folderBrowserView.onOpenItem?(firstItem)
    }

    func openFolderBrowserItemForTesting(at index: Int) {
        guard currentFolderBrowserItems.indices.contains(index) else { return }
        folderBrowserView.onOpenItem?(currentFolderBrowserItems[index])
    }

    var canGoBackForTesting: Bool { backRoute != nil && backRoute != currentRoute }
    var canGoForwardForTesting: Bool { forwardRoute != nil && forwardRoute != currentRoute }
    var lastOpenedFolderItemIDForTesting: ImageItem.ID? {
        folderBrowserViewModel.session?.lastOpenedItemID
    }
    var forwardViewerURLForTesting: URL? {
        guard case let .viewer(url) = forwardRoute else { return nil }
        return url
    }
    var associatedViewerURLForTesting: URL? { associatedViewerURL }
    var currentViewerRouteURLForTesting: URL? {
        guard case let .viewer(url) = currentRoute else { return nil }
        return url
    }
    var viewerNavigationURLForTesting: URL? {
        viewModel.navigationState?.currentItem?.url.standardizedFileURL
    }
    var displayedItemURLForTesting: URL? { displayedItemURL }
    var folderBrowserScrollOriginForTesting: NSPoint { folderBrowserView.testingScrollOrigin }

    func setFolderBrowserScrollOriginForTesting(_ origin: NSPoint) {
        folderBrowserView.testingSetScrollOrigin(origin)
    }

    var viewerNavigationURLsForTesting: [URL] {
        viewModel.navigationState?.items.map { $0.url.standardizedFileURL } ?? []
    }

    func setUnsavedChangesChoiceForTesting(_ choice: UnsavedChangesChoice?) {
        unsavedChangesChoiceForTesting = choice
    }

    func performTitleBarGridToggleForTesting() {
        browseCurrentImageFolder(nil)
    }

    func goBackForTesting() {
        goBack()
    }

    func goForwardForTesting() {
        goForward()
    }

    func performTitleBarBrowseCurrentFolderForTesting(items: [ImageItem]) {
        let folderURL = displayedItemURL?.deletingLastPathComponent()
            ?? items.first?.url.deletingLastPathComponent()
            ?? URL(fileURLWithPath: "/", isDirectory: true)
        openFolderForTesting(folderURL, items: items)
    }

    func returnToEmptyStateAfterCancelledOpen() {
        guard viewModel.currentImage == nil, viewModel.errorMessage != nil else { return }
        viewModel.resetToEmptyState()
        hasAssignedOpenRequest = false
        updateEmptyStatePresentation()
    }

    func updateRecentItems(_ urls: [URL]) {
        emptyStateView.applyRecentItems(urls)
    }

    /// 胶卷条开着就一直在，不看指针也不看缩放。
    /// 只有裁切时它会挡住选区，网格模式没有「当前这一张」，这两种情况才让路。
    static func shouldDisplayFilmstripOverlay(
        isEnabled: Bool,
        hasLoadedImage: Bool,
        isCropping: Bool = false,
        isFolderBrowserMode: Bool = false
    ) -> Bool {
        isEnabled && hasLoadedImage && !isCropping && !isFolderBrowserMode
    }

    static func shouldDisplayPageControls(itemCount: Int, isCropping: Bool) -> Bool {
        itemCount > 1 && !isCropping
    }

    static func pageControlAvailability(
        navigationState: NavigationState?,
        readingDirection: ReadingDirection = .leftToRight
    ) -> PageControlAvailability {
        guard let navigationState,
              let currentIndex = navigationState.currentIndex else {
            return PageControlAvailability(previous: false, next: false)
        }
        let leftToRight = PageControlAvailability(
            previous: currentIndex > 0,
            next: currentIndex < navigationState.items.count - 1
        )
        guard readingDirection == .rightToLeft else { return leftToRight }
        return PageControlAvailability(previous: leftToRight.next, next: leftToRight.previous)
    }

    static func shouldAutoHidePageControls(pointerIsOverControls: Bool) -> Bool {
        !pointerIsOverControls
    }

    static func dimensionText(pixelWidth: Int?, pixelHeight: Int?) -> String {
        guard let pixelWidth, let pixelHeight else { return "— × — px" }
        return "\(pixelWidth) × \(pixelHeight) px"
    }

    static func pageText(navigationState: NavigationState?) -> String {
        guard let navigationState,
              let currentIndex = navigationState.currentIndex else { return "0 / 0" }
        return "\(currentIndex + 1) / \(navigationState.items.count)"
    }

    static func zoomText(zoomScale: CGFloat) -> String {
        "\(Int((zoomScale * 100).rounded()))%"
    }

    static func zoomText(displayMode: ImageCanvasView.DisplayMode, pixelScale: CGFloat?) -> String {
        guard let pixelScale else {
            switch displayMode {
            case .fit: return AppStrings.text("viewer.zoom.fit")
            case .fitWidth: return AppStrings.text("viewer.zoom.fitWidth")
            case .manual: return "—%"
            }
        }
        let percentage = zoomText(zoomScale: pixelScale)
        if displayMode == .fit {
            return String(format: AppStrings.text("viewer.zoom.fitWithPercentage"), percentage)
        }
        if displayMode == .fitWidth {
            return String(format: AppStrings.text("viewer.zoom.fitWidthWithPercentage"), percentage)
        }
        return percentage
    }

    private func navigateToNextImage() {
        pendingNavigationSlide = .fromRight
        cancelCrop(nil)
        confirmUnsavedEditsIfNeeded(for: .navigating) { [weak self] in
            guard let self else { return }
            if self.settings.readingDirection == .leftToRight {
                self.viewModel.showNext()
            } else {
                self.viewModel.showPrevious()
            }
        }
    }

    private func navigateToPreviousImage() {
        pendingNavigationSlide = .fromLeft
        cancelCrop(nil)
        confirmUnsavedEditsIfNeeded(for: .navigating) { [weak self] in
            guard let self else { return }
            if self.settings.readingDirection == .leftToRight {
                self.viewModel.showPrevious()
            } else {
                self.viewModel.showNext()
            }
        }
    }

    private func selectImage(_ item: ImageItem) {
        cancelCrop(nil)
        confirmUnsavedEditsIfNeeded(for: .navigating) { [weak self] in
            self?.viewModel.show(item: item)
        }
    }

    private func performEdit(_ operation: EditOperation) {
        guard viewModel.canEditCurrentImage else {
            NSSound.beep()
            return
        }
        viewModel.applyEdit(operation)
    }

    private func confirmUnsavedEditsIfNeeded(
        for transition: UnsavedChangesTransition,
        perform action: () -> Void
    ) {
        guard viewModel.hasUnsavedEdits else {
            action()
            return
        }

        let choice = promptForUnsavedChanges(transition: transition)
        let saveSucceeded = choice == .save ? viewModel.saveCurrentEdits() : false
        let resolution = Self.resolveUnsavedChanges(choice: choice, saveSucceeded: saveSucceeded)

        guard resolution == .proceed else { return }
        if choice == .discard, !viewModel.discardCurrentEdits() {
            return
        }
        action()
    }

    private func promptForUnsavedChanges(transition: UnsavedChangesTransition) -> UnsavedChangesChoice {
        if let unsavedChangesChoiceForTesting {
            return unsavedChangesChoiceForTesting
        }
        let alert = NSAlert()
        alert.messageText = String(
            format: AppStrings.text("unsavedChanges.title"),
            transition.localizedDescription
        )
        alert.informativeText = AppStrings.text("unsavedChanges.message")
        alert.addButton(withTitle: AppStrings.text("unsavedChanges.button.save"))
        alert.addButton(withTitle: AppStrings.text("unsavedChanges.button.discard"))
        alert.addButton(withTitle: AppStrings.text("unsavedChanges.button.cancel"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }
}

extension MainWindowController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(undoEdit(_:)) {
            menuItem.title = viewModel.undoMenuTitle
            return !isFolderBrowserMode && viewModel.canUndo
        }
        if menuItem.action == #selector(redoEdit(_:)) {
            menuItem.title = viewModel.redoMenuTitle
            return !isFolderBrowserMode && viewModel.canRedo
        }
        if menuItem.action == #selector(toggleFilmstrip(_:)) {
            guard !isFolderBrowserMode else { return false }
            menuItem.state = settings.showsFilmstrip ? .on : .off
            return true
        }
        if menuItem.action == #selector(toggleInspector(_:)) {
            guard !isFolderBrowserMode else { return false }
            menuItem.state = settings.showsInspector ? .on : .off
            return true
        }
        if menuItem.action == #selector(toggleContinuousReading(_:)) {
            guard !isFolderBrowserMode,
                  !cropOverlay.isCropping,
                  viewModel.currentImage != nil else { return false }
            menuItem.state = settings.usesContinuousReading ? .on : .off
            return true
        }
        if menuItem.action == #selector(startCropping(_:)), settings.usesContinuousReading {
            return false
        }
        if menuItem.action == #selector(showPreviousImage(_:))
            || menuItem.action == #selector(showNextImage(_:)) {
            guard !isFolderBrowserMode else { return false }
            let availability = Self.pageControlAvailability(
                navigationState: viewModel.navigationState,
                readingDirection: settings.readingDirection
            )
            return menuItem.action == #selector(showPreviousImage(_:))
                ? availability.previous
                : availability.next
        }

        guard let command = Self.menuCommand(for: menuItem.action) else {
            return true
        }

        return Self.isMenuCommandEnabled(
            command,
            hasCurrentItem: viewModel.navigationState?.currentItem != nil,
            hasCurrentImage: viewModel.currentImage != nil,
            canEditCurrentImage: viewModel.canEditCurrentImage,
            hasUnsavedEdits: viewModel.hasUnsavedEdits,
            isFolderBrowserMode: isFolderBrowserMode
        )
    }
}

extension MainWindowController: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        onWindowDidBecomeKey?(self)
        guard Self.shouldRefreshCurrentFileOnWindowActivation() else { return }
        refreshCurrentFileForExternalChanges()
        startExternalFileCheckTimer()
    }

    func windowWillClose(_ notification: Notification) {
        cancelFolderRetry()
        continuousReadingTask?.cancel()
        continuousReadingTask = nil
        removeKeyMonitor()
        outsideClickMonitor?.invalidate()
        outsideClickMonitor = nil
        externalFileCheckTimer?.invalidate()
        externalFileCheckTimer = nil
        onWindowDidClose?(self)
    }

    func windowDidResignKey(_ notification: Notification) {
        externalFileCheckTimer?.invalidate()
        externalFileCheckTimer = nil
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        isInFullScreen = true
        fullScreenChromeHideTimer?.invalidate()
        fullScreenChromeHideTimer = nil
        setFullScreenChromeVisible(false)
        applySettings()
    }

    private func startExternalFileCheckTimer() {
        externalFileCheckTimer?.invalidate()
        externalFileCheckTimer = Timer.scheduledTimer(withTimeInterval: Self.externalFileCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshCurrentFileForExternalChanges()
            }
        }
    }

    private func refreshCurrentFileForExternalChanges() {
        let viewModel = viewModel
        Task { [weak viewModel] in
            await viewModel?.refreshCurrentFileIfNeeded()
        }
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        isInFullScreen = false
        fullScreenChromeHideTimer?.invalidate()
        fullScreenChromeHideTimer = nil
        setFullScreenChromeVisible(true)
        applySettings()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancelCrop(nil)
        guard viewModel.hasUnsavedEdits else { return true }

        let choice = promptForUnsavedChanges(transition: .closing)
        let saveSucceeded = choice == .save ? viewModel.saveCurrentEdits() : false
        let resolution = Self.resolveUnsavedChanges(choice: choice, saveSucceeded: saveSucceeded)

        if choice == .discard, resolution == .proceed {
            return viewModel.discardCurrentEdits()
        }

        return resolution == .proceed
    }
}

private enum UnsavedChangesTransition {
    case opening
    case navigating
    case renaming
    case movingToTrash
    case closing

    var localizedDescription: String {
        switch self {
        case .opening:
            return AppStrings.text("unsavedChanges.transition.opening")
        case .navigating:
            return AppStrings.text("unsavedChanges.transition.navigating")
        case .renaming:
            return AppStrings.text("unsavedChanges.transition.renaming")
        case .movingToTrash:
            return AppStrings.text("unsavedChanges.transition.movingToTrash")
        case .closing:
            return AppStrings.text("unsavedChanges.transition.closing")
        }
    }
}
