import AppKit
import ImageViewCore

enum CropHandle {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
    case move
}

final class CropOverlayView: NSView {
    private let minimumCropSide: CGFloat = 24
    private let handleSize: CGFloat = 8
    private let handleHitInset: CGFloat = 6
    private var imageRect = CGRect.zero
    private var activeHandle: CropHandle?
    private var lastDragLocation: CGPoint?

    var cropRect: CGRect = .zero {
        didSet { needsDisplay = true }
    }

    /// 锁定的宽高比。改成非 Free 时立刻把当前选区收进这个比例。
    var aspectRatio: CropAspectRatio = .free {
        didSet {
            guard aspectRatio != oldValue, isCropping else { return }
            cropRect = fitted(aspectRatio.constrained(cropRect))
        }
    }

    private(set) var isCropping = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func beginCropping(in imageRect: CGRect) {
        guard imageRect.width >= minimumCropSide,
              imageRect.height >= minimumCropSide else {
            endCropping()
            return
        }

        self.imageRect = imageRect
        let initial = imageRect.insetBy(dx: imageRect.width * 0.1, dy: imageRect.height * 0.1)
        cropRect = fitted(aspectRatio.constrained(initial))
        isCropping = true
        isHidden = false
    }

    /// 把选区推回画面之内。按比例收缩后中心可能落在边缘外，需要挪回来。
    private func fitted(_ rect: CGRect) -> CGRect {
        guard imageRect.width > 0, imageRect.height > 0 else { return rect }
        var result = rect
        result.size.width = min(result.width, imageRect.width)
        result.size.height = min(result.height, imageRect.height)
        result.origin.x = min(max(result.minX, imageRect.minX), imageRect.maxX - result.width)
        result.origin.y = min(max(result.minY, imageRect.minY), imageRect.maxY - result.height)
        return result
    }

    /// 锁定比例时，用户拖动的那条边决定主导方向，另一条边跟着算出来。
    ///
    /// 拖上下边就以高度为准算宽度，其余情况以宽度为准算高度。
    /// 换算完再整体推回画面内，避免贴边时选区被拉扁。
    private func applyingAspectRatio(_ rect: CGRect, edge: CropHandle) -> CGRect {
        guard let ratio = aspectRatio.value, ratio > 0 else { return rect }
        var result = rect
        switch edge {
        case .top, .bottom:
            result.size.width = rect.height * ratio
        default:
            result.size.height = rect.width / ratio
        }

        // 保持用户正在拖的那个角或边不动，另一侧伸缩。
        switch edge {
        case .topLeft, .left, .bottomLeft:
            result.origin.x = rect.maxX - result.width
        default:
            result.origin.x = rect.minX
        }
        switch edge {
        case .topLeft, .top, .topRight:
            result.origin.y = rect.maxY - result.height
        default:
            result.origin.y = rect.minY
        }
        return fitted(result)
    }

    func endCropping() {
        isCropping = false
        activeHandle = nil
        lastDragLocation = nil
        isHidden = true
    }

    func moveCrop(by delta: CGPoint) {
        guard isCropping else { return }

        let x = min(max(cropRect.minX + delta.x, imageRect.minX), imageRect.maxX - cropRect.width)
        let y = min(max(cropRect.minY + delta.y, imageRect.minY), imageRect.maxY - cropRect.height)
        cropRect.origin = CGPoint(x: x, y: y)
    }

    func resizeCrop(edge: CropHandle, by delta: CGPoint) {
        guard isCropping else { return }

        var next = cropRect
        switch edge {
        case .topLeft:
            next.origin.x = clampedLeading(cropRect.minX + delta.x, trailing: cropRect.maxX, lowerBound: imageRect.minX)
            next.origin.y = clampedLeading(cropRect.minY + delta.y, trailing: cropRect.maxY, lowerBound: imageRect.minY)
            next.size.width = cropRect.maxX - next.minX
            next.size.height = cropRect.maxY - next.minY
        case .top:
            next.origin.y = clampedLeading(cropRect.minY + delta.y, trailing: cropRect.maxY, lowerBound: imageRect.minY)
            next.size.height = cropRect.maxY - next.minY
        case .topRight:
            next.origin.y = clampedLeading(cropRect.minY + delta.y, trailing: cropRect.maxY, lowerBound: imageRect.minY)
            next.size.height = cropRect.maxY - next.minY
            next.size.width = clampedTrailing(cropRect.maxX + delta.x, leading: cropRect.minX, upperBound: imageRect.maxX) - cropRect.minX
        case .right:
            next.size.width = clampedTrailing(cropRect.maxX + delta.x, leading: cropRect.minX, upperBound: imageRect.maxX) - cropRect.minX
        case .bottomRight:
            next.size.width = clampedTrailing(cropRect.maxX + delta.x, leading: cropRect.minX, upperBound: imageRect.maxX) - cropRect.minX
            next.size.height = clampedTrailing(cropRect.maxY + delta.y, leading: cropRect.minY, upperBound: imageRect.maxY) - cropRect.minY
        case .bottom:
            next.size.height = clampedTrailing(cropRect.maxY + delta.y, leading: cropRect.minY, upperBound: imageRect.maxY) - cropRect.minY
        case .bottomLeft:
            next.origin.x = clampedLeading(cropRect.minX + delta.x, trailing: cropRect.maxX, lowerBound: imageRect.minX)
            next.size.width = cropRect.maxX - next.minX
            next.size.height = clampedTrailing(cropRect.maxY + delta.y, leading: cropRect.minY, upperBound: imageRect.maxY) - cropRect.minY
        case .left:
            next.origin.x = clampedLeading(cropRect.minX + delta.x, trailing: cropRect.maxX, lowerBound: imageRect.minX)
            next.size.width = cropRect.maxX - next.minX
        case .move:
            moveCrop(by: delta)
            return
        }
        cropRect = applyingAspectRatio(next, edge: edge)
    }

    override func mouseDown(with event: NSEvent) {
        guard isCropping else { return }
        let location = convert(event.locationInWindow, from: nil)
        activeHandle = handle(at: location)
        lastDragLocation = activeHandle == nil ? nil : location
    }

    override func mouseDragged(with event: NSEvent) {
        guard let activeHandle,
              let lastDragLocation else { return }
        let location = convert(event.locationInWindow, from: nil)
        resizeCrop(edge: activeHandle, by: CGPoint(x: location.x - lastDragLocation.x, y: location.y - lastDragLocation.y))
        self.lastDragLocation = location
    }

    override func mouseUp(with event: NSEvent) {
        activeHandle = nil
        lastDragLocation = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isCropping else { return }

        let mask = NSBezierPath(rect: bounds)
        mask.appendRect(cropRect)
        mask.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.55).setFill()
        mask.fill()

        NSColor.controlAccentColor.setStroke()
        NSBezierPath(rect: cropRect).stroke()
        NSColor.controlAccentColor.setFill()
        for handleRect in handleRects.values {
            NSBezierPath(rect: handleRect).fill()
        }
    }

    private var handleRects: [CropHandle: CGRect] {
        let halfHandle = handleSize / 2
        let centerX = cropRect.midX
        let centerY = cropRect.midY
        return [
            .topLeft: CGRect(x: cropRect.minX - halfHandle, y: cropRect.minY - halfHandle, width: handleSize, height: handleSize),
            .top: CGRect(x: centerX - halfHandle, y: cropRect.minY - halfHandle, width: handleSize, height: handleSize),
            .topRight: CGRect(x: cropRect.maxX - halfHandle, y: cropRect.minY - halfHandle, width: handleSize, height: handleSize),
            .right: CGRect(x: cropRect.maxX - halfHandle, y: centerY - halfHandle, width: handleSize, height: handleSize),
            .bottomRight: CGRect(x: cropRect.maxX - halfHandle, y: cropRect.maxY - halfHandle, width: handleSize, height: handleSize),
            .bottom: CGRect(x: centerX - halfHandle, y: cropRect.maxY - halfHandle, width: handleSize, height: handleSize),
            .bottomLeft: CGRect(x: cropRect.minX - halfHandle, y: cropRect.maxY - halfHandle, width: handleSize, height: handleSize),
            .left: CGRect(x: cropRect.minX - halfHandle, y: centerY - halfHandle, width: handleSize, height: handleSize)
        ]
    }

    private func handle(at location: CGPoint) -> CropHandle? {
        let rects = handleRects
        for handle in [CropHandle.topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left] {
            guard let rect = rects[handle] else { continue }
            if rect.insetBy(dx: -handleHitInset, dy: -handleHitInset).contains(location) {
                return handle
            }
        }
        return cropRect.contains(location) ? .move : nil
    }

    private func clampedLeading(_ value: CGFloat, trailing: CGFloat, lowerBound: CGFloat) -> CGFloat {
        min(max(value, lowerBound), trailing - minimumCropSide)
    }

    private func clampedTrailing(_ value: CGFloat, leading: CGFloat, upperBound: CGFloat) -> CGFloat {
        max(min(value, upperBound), leading + minimumCropSide)
    }
}
