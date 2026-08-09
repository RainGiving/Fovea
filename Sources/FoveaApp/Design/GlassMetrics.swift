import AppKit

/// macOS 26 玻璃材质的统一度量。
///
/// 圆角、浮层间距和融合阈值都从这里取值，整个应用只有一套数字，
/// 改设计时改这里，不用去每个视图里翻魔数。
enum GlassMetrics {
    /// 贴着窗口边的 chrome，圆角交给窗口本身。
    static let chromeCornerRadius: CGFloat = 0

    /// 浮在图片上方的面板：胶卷条、信息面板、提示条、裁剪控件。
    static let panelCornerRadius: CGFloat = 16

    /// 玻璃面板内部的次级控件。
    static let controlCornerRadius: CGFloat = 10

    /// 浮层与窗口边缘之间留的距离。
    static let floatingInset: CGFloat = 16

    /// 玻璃视图开始相互融合的距离，传给 `NSGlassEffectContainerView`。
    static let mergeSpacing: CGFloat = 12

    /// 玻璃表面上悬停和按下的着色强度。
    ///
    /// 玻璃本身已经提供了材质，控件状态只需要很轻的一层染色，
    /// 数值高了会把玻璃压成实心色块。
    static let hoverTintAlpha: CGFloat = 0.14
    static let pressedTintAlpha: CGFloat = 0.24

    /// 信息面板的固定宽度。停靠成侧栏时画布让出的就是这个宽度。
    static let inspectorWidth: CGFloat = 220

    /// 胶囊圆角按高度取一半。
    static func capsuleCornerRadius(forHeight height: CGFloat) -> CGFloat {
        max(0, height / 2)
    }
}
