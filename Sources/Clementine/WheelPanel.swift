import AppKit

final class WheelPanel: NSPanel {
    static let side: CGFloat = 380
    private let wheel = WheelView(frame: NSRect(x: 0, y: 0, width: side, height: side))

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.side, height: Self.side),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        contentView = wheel
        wheel.onFinished = { [weak self] in self?.dismiss() }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func present(actions: [WheelAction], files: [URL], at point: NSPoint) {
        wheel.configure(actions: actions, files: files)
        var origin = NSPoint(x: point.x - Self.side / 2, y: point.y - Self.side / 2)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            let f = screen.visibleFrame
            origin.x = min(max(origin.x, f.minX), f.maxX - Self.side)
            origin.y = min(max(origin.y, f.minY), f.maxY - Self.side)
        }
        setFrameOrigin(origin)
        orderFrontRegardless()
    }

    func dismiss() {
        orderOut(nil)
    }
}
