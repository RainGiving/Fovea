import AppKit

@MainActor
final class GestureCoordinator: NSObject {
    private weak var canvas: ImageCanvasView?

    init(canvas: ImageCanvasView) {
        self.canvas = canvas
        super.init()
        install()
    }

    private func install() {
        let magnification = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnification(_:)))
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
        click.numberOfClicksRequired = 2
        canvas?.addGestureRecognizer(magnification)
        canvas?.addGestureRecognizer(click)
    }

    func applyMagnification(_ magnification: CGFloat, at point: CGPoint) {
        canvas?.zoom(by: 1.0 + magnification, around: point)
    }

    /// 双击是一步到位的切换，并把点击处留在原地。
    func applyDoubleClick(at point: CGPoint) {
        guard let canvas else { return }
        canvas.withAnimatedGeometry { canvas.toggleFitOrActualSize(around: point) }
    }

    @objc private func handleMagnification(_ gesture: NSMagnificationGestureRecognizer) {
        guard let canvas else { return }
        let point = gesture.location(in: canvas)
        applyMagnification(gesture.magnification, at: point)
        gesture.magnification = 0
    }

    @objc private func handleDoubleClick(_ gesture: NSClickGestureRecognizer) {
        guard let canvas else { return }
        applyDoubleClick(at: gesture.location(in: canvas))
    }

}
