import AppKit

/// 下边栏内的胶片区域。
///
/// 外层下边栏已经提供玻璃材质，这里只负责容纳缩略图和滑杆。
@MainActor
final class FilmstripOverlayView: NSView {
    var contentView: NSView { self }

    override init(frame frameRect: NSRect = .zero) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

}
