import AppKit
import ImageViewCore

/// 窗口当下在展示什么。互斥，同一时刻只有一个成立。
///
/// 这件事以前分散在路由、文件夹标志、连续浏览开关和「有没有图」几处，各自在
/// 不同时机被改，界面该是什么样要靠调用顺序凑出来。现在它由一组输入算出来。
enum ContentMode: Equatable {
    /// 还没有图，等着用户打开。
    case empty
    /// 正在解，画面上还没有东西可看。
    case loading
    /// 打开失败。
    case error
    /// 单图查看。
    case single
    /// 连续浏览。
    case continuous
    /// 文件夹网格。
    case grid

    /// 画面上有一张图。单图和连续浏览都算。
    var showsImage: Bool { self == .single || self == .continuous }

    /// 画布这一层在不在前面。网格和连续浏览会把它换下去。
    var showsCanvas: Bool { self != .grid && self != .continuous }

    struct Input: Equatable {
        var isBrowsingFolder: Bool
        var hasImage: Bool
        var loadPhase: ImageLoadPhase
        var hasError: Bool
        var usesContinuousReading: Bool

        init(
            isBrowsingFolder: Bool = false,
            hasImage: Bool = false,
            loadPhase: ImageLoadPhase = .empty,
            hasError: Bool = false,
            usesContinuousReading: Bool = false
        ) {
            self.isBrowsingFolder = isBrowsingFolder
            self.hasImage = hasImage
            self.loadPhase = loadPhase
            self.hasError = hasError
            self.usesContinuousReading = usesContinuousReading
        }
    }

    /// 模式只由这五个输入决定，没有别的来源。
    ///
    /// 网格压过一切：进了网格就没有「当前这一张」可谈。有图之后才轮到单图和
    /// 连续浏览之分。都没有时，出错显示错误，解码中什么也不显示，其余是空状态。
    static func resolve(_ input: Input) -> ContentMode {
        if input.isBrowsingFolder { return .grid }
        if input.hasImage { return input.usesContinuousReading ? .continuous : .single }
        if input.hasError { return .error }
        return input.loadPhase == .empty ? .empty : .loading
    }
}

/// 一次刷新要落到界面上的全部状态。
///
/// 由 `resolve` 从模式和几个开关一次算出来，控制器只负责把它贴到视图上。
/// 「谁在什么时候刷新了什么」因此不再取决于调用顺序：状态先改完，再整体算一次。
struct WindowPresentation: Equatable {
    var mode: ContentMode
    /// 编辑模式。只有单图查看能进，别的模式一律按 false 算。
    var isEditing: Bool
    /// 上下两条玻璃边栏。全屏里会收起来。
    var showsChrome: Bool
    var showsCanvas: Bool
    var showsContinuousReading: Bool
    var showsFolderBrowser: Bool
    var showsEmptyState: Bool
    var showsErrorState: Bool
    var showsInspector: Bool
    /// 停靠的信息栏要图片让出一条。浮动时不占地方。
    var reservesInspectorColumn: Bool
    var showsFilmstrip: Bool
    /// 底栏里那几个只有看图时才有意义的状态。
    var showsImageStatus: Bool
    var showsZoomStatus: Bool
    /// 翻页按钮允不允许露面。真正的显隐还要看指针有没有动。
    var allowsPageControls: Bool
    var canEditImage: Bool
    var canToggleFilmstrip: Bool
    var canToggleContinuousReading: Bool
    var canToggleGrid: Bool
    /// 需要「当前这一张」的那些菜单命令。
    var allowsImageCommands: Bool
    var title: String
    var titleToolTip: String?

    struct Input: Equatable {
        var mode: ContentMode
        var isEditing: Bool
        var chromeVisible: Bool
        var inspectorEnabled: Bool
        var inspectorDocked: Bool
        var filmstripEnabled: Bool
        var canEditCurrentImage: Bool
        var canToggleGrid: Bool
        var itemCount: Int
        var viewerTitle: String
        var folderURL: URL?

        init(
            mode: ContentMode = .empty,
            isEditing: Bool = false,
            chromeVisible: Bool = true,
            inspectorEnabled: Bool = false,
            inspectorDocked: Bool = false,
            filmstripEnabled: Bool = false,
            canEditCurrentImage: Bool = false,
            canToggleGrid: Bool = false,
            itemCount: Int = 0,
            viewerTitle: String = "",
            folderURL: URL? = nil
        ) {
            self.mode = mode
            self.isEditing = isEditing
            self.chromeVisible = chromeVisible
            self.inspectorEnabled = inspectorEnabled
            self.inspectorDocked = inspectorDocked
            self.filmstripEnabled = filmstripEnabled
            self.canEditCurrentImage = canEditCurrentImage
            self.canToggleGrid = canToggleGrid
            self.itemCount = itemCount
            self.viewerTitle = viewerTitle
            self.folderURL = folderURL
        }
    }

    static func resolve(_ input: Input) -> WindowPresentation {
        let mode = input.mode
        let hasImage = mode.showsImage
        // 编辑只属于单图查看。别的模式下即使残留着编辑状态也一律按退出算，
        // 裁切框不会浮到网格或连续浏览上面去。
        let isEditing = input.isEditing && mode == .single
        let showsInspector = inspectorVisible(isEnabled: input.inspectorEnabled, hasImage: hasImage)
        let title: String
        let titleToolTip: String?
        // 网格里没有「当前这一张」，标题给目录名。它是这个模式下唯一说得通的标题，
        // 也不会因为刚才看过哪张图而变。
        if mode == .grid, let folderURL = input.folderURL {
            title = folderURL.lastPathComponent
            titleToolTip = folderURL.path
        } else {
            title = input.viewerTitle
            titleToolTip = nil
        }

        return WindowPresentation(
            mode: mode,
            isEditing: isEditing,
            showsChrome: input.chromeVisible,
            showsCanvas: mode.showsCanvas,
            showsContinuousReading: mode == .continuous,
            showsFolderBrowser: mode == .grid,
            showsEmptyState: mode == .empty,
            showsErrorState: mode == .error,
            showsInspector: showsInspector,
            reservesInspectorColumn: showsInspector && input.inspectorDocked,
            showsFilmstrip: filmstripVisible(
                isEnabled: input.filmstripEnabled,
                hasImage: hasImage,
                isEditing: isEditing,
                mode: mode
            ),
            showsImageStatus: hasImage,
            showsZoomStatus: mode == .single,
            allowsPageControls: pageControlsAllowed(mode: mode, itemCount: input.itemCount, isEditing: isEditing),
            canEditImage: imageEditingAllowed(canEditCurrentImage: input.canEditCurrentImage, mode: mode),
            canToggleFilmstrip: mode != .grid,
            canToggleContinuousReading: mode != .grid && !isEditing,
            canToggleGrid: input.canToggleGrid,
            allowsImageCommands: mode != .grid,
            title: title,
            titleToolTip: titleToolTip
        )
    }

    /// 空窗口的初始状态。控制器建好视图之后马上会算一次真的。
    static let initial = resolve(Input())

    // MARK: - 单条规则
    //
    // 每条规则只写一次，`resolve` 负责把它们串起来。控制器和测试都从这里取。

    static func emptyStateVisible(hasImage: Bool, loadPhase: ImageLoadPhase, hasError: Bool) -> Bool {
        !hasImage && loadPhase == .empty && !hasError
    }

    static func errorStateVisible(hasImage: Bool, hasError: Bool) -> Bool {
        !hasImage && hasError
    }

    static func inspectorVisible(isEnabled: Bool, hasImage: Bool) -> Bool {
        isEnabled && hasImage
    }

    /// 裁切时胶卷条会挡住选区；网格模式没有「当前这一张」；连续浏览本身就是把
    /// 整个序列铺开滚，再加一条胶卷等于同一件事说两遍。这三种情况让路。
    static func filmstripVisible(isEnabled: Bool, hasImage: Bool, isEditing: Bool, mode: ContentMode) -> Bool {
        isEnabled && hasImage && !isEditing && mode == .single
    }

    static func pageControlsAllowed(mode: ContentMode, itemCount: Int, isEditing: Bool) -> Bool {
        mode.showsImage && itemCount > 1 && !isEditing
    }

    /// 有图、能改、并且正处在单图查看里。网格和连续浏览都进不了编辑。
    static func imageEditingAllowed(canEditCurrentImage: Bool, mode: ContentMode) -> Bool {
        canEditCurrentImage && mode == .single
    }
}
