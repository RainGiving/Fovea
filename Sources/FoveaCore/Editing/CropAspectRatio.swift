import CoreGraphics
import Foundation

/// 裁切时可选的宽高比。
///
/// `free` 不做约束，其余按 `width : height` 锁定。证件照按国标的毫米尺寸折算：
/// 一寸 25×35mm，二寸 35×49mm，小二寸（护照常用）35×45mm。
public enum CropAspectRatio: String, CaseIterable, Sendable, Hashable {
    case free
    case square
    case fourThree
    case threeTwo
    case sixteenNine
    case idOneInch
    case idTwoInch
    case idSmallTwoInch

    /// 宽除以高。`free` 没有约束，返回 nil。
    public var value: CGFloat? {
        switch self {
        case .free: return nil
        case .square: return 1
        case .fourThree: return 4.0 / 3.0
        case .threeTwo: return 3.0 / 2.0
        case .sixteenNine: return 16.0 / 9.0
        case .idOneInch: return 25.0 / 35.0
        case .idTwoInch: return 35.0 / 49.0
        case .idSmallTwoInch: return 35.0 / 45.0
        }
    }

    /// 菜单和按钮上的短标签。自由裁切按用户要求标 Free。
    public var displayName: String {
        switch self {
        case .free: return "Free"
        case .square: return "1:1"
        case .fourThree: return "4:3"
        case .threeTwo: return "3:2"
        case .sixteenNine: return "16:9"
        case .idOneInch: return "一寸"
        case .idTwoInch: return "二寸"
        case .idSmallTwoInch: return "小二寸"
        }
    }

    /// 证件照额外标出毫米尺寸，避免只看比例分不清一寸和二寸。
    public var detail: String? {
        switch self {
        case .idOneInch: return "25 × 35 mm"
        case .idTwoInch: return "35 × 49 mm"
        case .idSmallTwoInch: return "35 × 45 mm"
        default: return nil
        }
    }

    /// 把一个矩形调整成当前比例。
    ///
    /// 以矩形中心为基准缩到能放进原矩形的最大尺寸，避免调整比例时
    /// 选区突然跑出画面。
    public func constrained(_ rect: CGRect) -> CGRect {
        guard let value, value > 0, rect.width > 0, rect.height > 0 else { return rect }
        let currentRatio = rect.width / rect.height
        var width = rect.width
        var height = rect.height
        if currentRatio > value {
            width = rect.height * value
        } else {
            height = rect.width / value
        }
        return CGRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
    }
}
