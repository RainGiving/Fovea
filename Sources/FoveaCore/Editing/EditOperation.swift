import CoreGraphics

public enum EditOperation: Equatable, Sendable {
    case rotateClockwise
    case rotateCounterClockwise
    case mirrorHorizontal
    case mirrorVertical
    case crop(CGRect)
}

public extension EditOperation {
    /// 图片上同一块内容，经过这次编辑之后落在哪里。
    ///
    /// 输入和输出都是归一化到 0...1 的矩形，原点在左上角，和 `crop` 取像素时
    /// 用的坐标系一致。裁切框按它跟着图片一起转，用户圈住的还是原来那块画面。
    /// 裁切之后整张图就是原来选中的那一块，所以返回整幅。
    func movingNormalizedRect(_ rect: CGRect) -> CGRect {
        switch self {
        case .rotateClockwise:
            return CGRect(
                x: 1 - rect.minY - rect.height,
                y: rect.minX,
                width: rect.height,
                height: rect.width
            )
        case .rotateCounterClockwise:
            return CGRect(
                x: rect.minY,
                y: 1 - rect.minX - rect.width,
                width: rect.height,
                height: rect.width
            )
        case .mirrorHorizontal:
            return CGRect(
                x: 1 - rect.minX - rect.width,
                y: rect.minY,
                width: rect.width,
                height: rect.height
            )
        case .mirrorVertical:
            return CGRect(
                x: rect.minX,
                y: 1 - rect.minY - rect.height,
                width: rect.width,
                height: rect.height
            )
        case .crop:
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
    }

    /// 撤销这次编辑时，内容反过来走的那一步。
    ///
    /// 裁切没有逆操作，撤销之后原来选中的范围在新画面里已经无从还原，返回 nil。
    var reversed: EditOperation? {
        switch self {
        case .rotateClockwise:
            return .rotateCounterClockwise
        case .rotateCounterClockwise:
            return .rotateClockwise
        case .mirrorHorizontal:
            return .mirrorHorizontal
        case .mirrorVertical:
            return .mirrorVertical
        case .crop:
            return nil
        }
    }
}
