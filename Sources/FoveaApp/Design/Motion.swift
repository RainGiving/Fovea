import AppKit

/// 全应用共用的一套动效。
///
/// 时长、曲线和位移都从这里取值，各处的进出节奏才对得上，改观感时也只改这一处。
/// 两种情况下所有入口直接落值：系统开了「减弱动态效果」，以及视图还没真正上屏。
/// 后一条覆盖了建好窗口却从不显示的用法，界面状态在那里必须当场生效。
@MainActor
enum Motion {
    /// 轻反馈：着色、按下、图标切换。
    static let quick: TimeInterval = 0.16

    /// 常规过渡：浮层进出、两种视图互换。
    static let standard: TimeInterval = 0.24

    /// 要走一段距离的大件：信息栏、chrome 收放、网格与单图互换。
    static let expressive: TimeInterval = 0.32

    /// 退场取入场的这个比例。东西离开时不该让人等。
    static let exitRatio: Double = 0.72

    /// 入场：起步快，尾巴长，停得住。
    static let entrance = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)

    /// 退场：先松一下再加速离开。
    static let exit = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.9, 0.4)

    /// 位置和尺寸变化：两端都收得住，中段走得快。
    static let move = CAMediaTimingFunction(controlPoints: 0.33, 0.85, 0.15, 1)

    /// 连续翻页：保留快速响应，同时让起步和落点都有缓冲。
    static let navigation = CAMediaTimingFunction(controlPoints: 0.2, 0.68, 0.24, 1)

    /// 末端带一点回弹，用在按钮点亮这种点状反馈上。
    static let springy = CAMediaTimingFunction(controlPoints: 0.22, 1.32, 0.36, 1)

    /// 浮层进出时先偏出去的距离。
    static let panelOffset: CGFloat = 18

    static var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// 只有真的显示在屏幕上的视图才播动画。
    ///
    /// 没上屏时播动画既看不见，又会把状态切换推迟到动画收尾，
    /// 于是刚建好窗口的那一批状态会晚一拍才落地。
    static func canAnimate(_ view: NSView?) -> Bool {
        guard !prefersReducedMotion else { return false }
        guard let window = view?.window else { return false }
        return window.isVisible
    }

    /// 统一的动画入口。
    ///
    /// 不满足播放条件时当场落值，`completion` 同步调用，调用方不必分两条路写。
    /// `animatesLayout` 打开的是 Auto Layout 的隐式动画，改完约束记得在
    /// `changes` 末尾触发一次布局。
    static func run(
        in view: NSView?,
        duration: TimeInterval = standard,
        timing: CAMediaTimingFunction = entrance,
        animatesLayout: Bool = false,
        changes: () -> Void,
        completion: @escaping @MainActor () -> Void = {}
    ) {
        guard canAnimate(view) else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = animatesLayout
                changes()
            }
            completion()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timing
            context.allowsImplicitAnimation = animatesLayout
            changes()
        } completionHandler: {
            MainActor.assumeIsolated { completion() }
        }
    }

    /// 配合淡入淡出的一段位移。
    ///
    /// 浮层多半靠一条约束定位，进出时把这条约束在两个常数之间推一下，
    /// 就有了「从哪来、往哪去」的方向感。
    struct Slide {
        let constraint: NSLayoutConstraint
        let visibleConstant: CGFloat
        let hiddenConstant: CGFloat
        let layoutRoot: NSView
        /// 收起之后把常数放回显示时的那个。
        ///
        /// 位移只是过场时该保持默认，藏起来的浮层量出来的位置仍然是它该在的地方。
        /// 收起的常数本身就代表新的布局时（比如把边栏高度收到零）传 false。
        let restoresWhenHidden: Bool

        init(
            _ constraint: NSLayoutConstraint,
            visible: CGFloat,
            hidden: CGFloat,
            in layoutRoot: NSView,
            restoresWhenHidden: Bool = true
        ) {
            self.constraint = constraint
            self.visibleConstant = visible
            self.hiddenConstant = hidden
            self.layoutRoot = layoutRoot
            self.restoresWhenHidden = restoresWhenHidden
        }
    }

    /// 让一块浮层出现或收起。
    ///
    /// 收起时先播完淡出再置 `isHidden`，收尾里用模型上的 alpha 判断这次淡出
    /// 是否已经过期：中途又被要求显示的话，alpha 在动画开始那一刻就已经写回 1，
    /// 于是这次收尾自动作废，不用另外记代次。
    static func setVisible(
        _ view: NSView,
        _ visible: Bool,
        slide: Slide? = nil,
        duration: TimeInterval = standard,
        animated: Bool = true,
        completion: @escaping @MainActor () -> Void = {}
    ) {
        guard animated else {
            view.alphaValue = visible ? 1 : 0
            view.isHidden = !visible
            if let slide {
                slide.constraint.constant = visible || slide.restoresWhenHidden
                    ? slide.visibleConstant
                    : slide.hiddenConstant
            }
            completion()
            return
        }

        if visible {
            guard view.isHidden || view.alphaValue < 1 else {
                completion()
                return
            }
            if view.isHidden {
                view.alphaValue = 0
                slide?.constraint.constant = slide?.hiddenConstant ?? 0
                slide?.layoutRoot.layoutSubtreeIfNeeded()
                view.isHidden = false
            }
            run(
                in: view,
                duration: duration,
                timing: entrance,
                animatesLayout: slide != nil,
                changes: {
                    view.animator().alphaValue = 1
                    if let slide {
                        slide.constraint.constant = slide.visibleConstant
                        slide.layoutRoot.layoutSubtreeIfNeeded()
                    }
                },
                completion: completion
            )
            return
        }

        guard !view.isHidden else {
            completion()
            return
        }
        run(
            in: view,
            duration: duration * exitRatio,
            timing: exit,
            animatesLayout: slide != nil,
            changes: {
                view.animator().alphaValue = 0
                if let slide {
                    slide.constraint.constant = slide.hiddenConstant
                    slide.layoutRoot.layoutSubtreeIfNeeded()
                }
            },
            completion: {
                // 这中间又被显示出来了，收尾作废。
                guard view.alphaValue == 0 else { return }
                view.isHidden = true
                // 藏起来之后把约束放回原位，别人量这块浮层的位置时读到的
                // 仍然是它该在的地方。
                if let slide, slide.restoresWhenHidden {
                    slide.constraint.constant = slide.visibleConstant
                    slide.layoutRoot.layoutSubtreeIfNeeded()
                }
                completion()
            }
        )
    }

    /// 绕视图中心缩放的变换。
    ///
    /// AppKit 会把图层的 anchorPoint 一直按回 (0, 0)，改它撑不过下一次布局，
    /// 所以中心缩放靠平移到中心、缩放、再平移回来实现。
    static func centeredScale(_ scale: CGFloat, in bounds: CGRect) -> CATransform3D {
        var transform = CATransform3DIdentity
        transform = CATransform3DTranslate(transform, bounds.midX, bounds.midY, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        return CATransform3DTranslate(transform, -bounds.midX, -bounds.midY, 0)
    }

    /// 把视图缩到某个倍率并停在那里。按下、松开这类有状态的反馈用它。
    static func setScale(
        _ view: NSView,
        _ scale: CGFloat,
        duration: TimeInterval = quick,
        timing: CAMediaTimingFunction = entrance
    ) {
        guard let layer = view.layer else { return }
        let target = scale == 1 ? CATransform3DIdentity : centeredScale(scale, in: layer.bounds)
        guard canAnimate(view) else {
            // 播不了动画时不留下一个缩着的视图：静态地缩一下既没有意义，
            // 也可能因为看不见的那一半流程没跑完而卡在那个倍率上。
            layer.transform = CATransform3DIdentity
            return
        }
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? layer.transform)
        animation.toValue = NSValue(caTransform3D: target)
        animation.duration = duration
        animation.timingFunction = timing
        layer.transform = target
        layer.add(animation, forKey: "motion.scale")
    }

    /// 让视图鼓一下再回去。开关点亮、状态确认这类没有位移的动作用它。
    static func pop(_ view: NSView, scale: CGFloat = 1.16, duration: TimeInterval = 0.3) {
        guard canAnimate(view), let layer = view.layer else { return }
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = [
            NSValue(caTransform3D: CATransform3DIdentity),
            NSValue(caTransform3D: centeredScale(scale, in: layer.bounds)),
            NSValue(caTransform3D: CATransform3DIdentity)
        ]
        animation.keyTimes = [0, 0.4, 1]
        animation.timingFunctions = [entrance, springy]
        animation.duration = duration
        layer.add(animation, forKey: "motion.pop")
    }

    /// 手写插值用的缓出曲线，和 `entrance` 是同一种手感。
    ///
    /// 自己按帧算的动画（裁切框）拿不到 Core Animation 的曲线，只能算这一份。
    static func easeOut(_ progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        return 1 - pow(1 - clamped, 3)
    }

    /// 两个矩形之间按进度插值。
    static func interpolate(_ from: CGRect, _ to: CGRect, progress: Double) -> CGRect {
        let ratio = CGFloat(min(max(progress, 0), 1))
        return CGRect(
            x: from.minX + (to.minX - from.minX) * ratio,
            y: from.minY + (to.minY - from.minY) * ratio,
            width: from.width + (to.width - from.width) * ratio,
            height: from.height + (to.height - from.height) * ratio
        )
    }
}
