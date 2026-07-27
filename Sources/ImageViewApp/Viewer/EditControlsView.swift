import AppKit
import ImageViewCore
import SwiftUI

/// 编辑模式的浮动控制条。
///
/// 裁切比例、旋转翻转、取消应用都收在这里。查看状态下不出现，
/// 只有进入「编辑图片」之后才浮上来。
struct EditControlsView: View {
    var aspectRatio: CropAspectRatio = .free
    var onAspectRatioChange: (CropAspectRatio) -> Void = { _ in }
    var onRotateLeft: () -> Void = {}
    var onRotateRight: () -> Void = {}
    var onFlipHorizontal: () -> Void = {}
    var onFlipVertical: () -> Void = {}
    let onCancel: () -> Void
    let onApply: () -> Void

    @State private var aspectRatioAnchor = MenuAnchorBox()

    var body: some View {
        // 每个控件各自是一块玻璃，靠容器把贴近的几块融成一条。
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                aspectRatioButton

                Divider().frame(height: 18)

                iconButton("rotate.left", AppStrings.text("menu.image.rotateCounterclockwise"), onRotateLeft)
                iconButton("rotate.right", AppStrings.text("menu.image.rotateClockwise"), onRotateRight)
                iconButton("arrow.left.arrow.right", AppStrings.text("menu.image.flipHorizontal"), onFlipHorizontal)
                iconButton("arrow.up.arrow.down", AppStrings.text("menu.image.flipVertical"), onFlipVertical)

                Divider().frame(height: 18)

                Button(AppStrings.text("crop.button.cancel"), action: onCancel)
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                Button(AppStrings.text("crop.button.apply"), action: onApply)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.regular)
        }
    }

    /// 比例选择做成普通按钮加 AppKit 菜单，不用 SwiftUI 的 `Menu`。
    ///
    /// `Menu` 走的是弹出按钮那套绘制，标签配色由它自己决定，玻璃条上会出现
    /// 深底黑字，跟旁边同样是玻璃按钮的旋转图标对不上。改成和旋转按钮完全
    /// 相同的 `Button` 加 `.glass`，配色就只有一个来源。菜单本身交给 `NSMenu`，
    /// 勾选状态也回到系统的对钩，不用在标签里塞一个 checkmark 图片充数。
    private var aspectRatioButton: some View {
        Button {
            presentAspectRatioMenu()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "aspectratio")
                Text(aspectRatio.displayName)
                Image(systemName: "chevron.down")
                    .imageScale(.small)
            }
        }
        .buttonStyle(.glass)
        .fixedSize()
        .help(AppStrings.text("crop.aspectRatio"))
        .accessibilityLabel(AppStrings.text("crop.aspectRatio"))
        .background(MenuAnchorView(box: aspectRatioAnchor))
    }

    private func presentAspectRatioMenu() {
        guard let anchor = aspectRatioAnchor.view else { return }
        let menu = Self.makeAspectRatioMenu(selected: aspectRatio, onSelect: onAspectRatioChange)
        // 菜单贴着按钮下沿弹出。视图未翻转，y 轴向上，所以取 0。
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: anchor)
    }

    static func makeAspectRatioMenu(
        selected: CropAspectRatio,
        onSelect: @escaping (CropAspectRatio) -> Void
    ) -> NSMenu {
        AspectRatioMenu(selected: selected, onSelect: onSelect)
    }

    private func iconButton(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(.glass)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// 比例菜单。`NSMenuItem.target` 是弱引用，菜单自己强持有那个目标对象。
final class AspectRatioMenu: NSMenu {
    private let handler: AspectRatioMenuTarget

    init(selected: CropAspectRatio, onSelect: @escaping (CropAspectRatio) -> Void) {
        handler = AspectRatioMenuTarget(onSelect: onSelect)
        super.init(title: "")
        for ratio in CropAspectRatio.allCases {
            // 证件照带上毫米尺寸，只看比例分不出一寸和二寸。
            let title = ratio.detail.map { "\(ratio.displayName)  \($0)" } ?? ratio.displayName
            let item = NSMenuItem(
                title: title,
                action: #selector(AspectRatioMenuTarget.selectRatio(_:)),
                keyEquivalent: ""
            )
            item.state = ratio == selected ? .on : .off
            item.representedObject = ratio.rawValue
            item.target = handler
            addItem(item)
        }
    }

    /// 菜单只在代码里构造，不从 nib 反序列化。
    @available(*, unavailable)
    required init(coder: NSCoder) {
        handler = AspectRatioMenuTarget { _ in }
        super.init(coder: coder)
    }
}

private final class AspectRatioMenuTarget: NSObject {
    private let onSelect: (CropAspectRatio) -> Void

    init(onSelect: @escaping (CropAspectRatio) -> Void) {
        self.onSelect = onSelect
    }

    @objc func selectRatio(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let ratio = CropAspectRatio(rawValue: rawValue) else { return }
        onSelect(ratio)
    }
}

/// 把 SwiftUI 按钮的位置借出来当菜单的锚点。
private final class MenuAnchorBox {
    weak var view: NSView?
}

private struct MenuAnchorView: NSViewRepresentable {
    let box: MenuAnchorBox

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        box.view = nsView
    }
}
