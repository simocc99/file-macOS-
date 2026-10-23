import AppKit

/// Il menu rotondo: disegna gli spicchi e riceve il file lasciato cadere.
final class WheelView: NSView {
    var onFinished: (() -> Void)?

    private var actions: [WheelAction] = []
    private var files: [URL] = []
    private var hovered: Int?
    private var busy = false

    private let outer: CGFloat = 175
    private let inner: CGFloat = 62
    private let gap: CGFloat = 2.5 // gradi tra uno spicchio e l'altro

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(actions: [WheelAction], files: [URL]) {
        self.actions = actions
        self.files = files
        hovered = nil
        busy = false
        needsDisplay = true
    }

    private var step: CGFloat { 360 / CGFloat(max(actions.count, 1)) }
    private var center: NSPoint { NSPoint(x: bounds.midX, y: bounds.midY) }

    // MARK: Disegno

    override func draw(_ dirtyRect: NSRect) {
        guard !actions.isEmpty else { return }

        let disc = NSBezierPath(ovalIn: bounds.insetBy(dx: bounds.width / 2 - outer - 8, dy: bounds.height / 2 - outer - 8))
        NSColor(white: 0.1, alpha: 0.35).setFill()
        disc.fill()

        for (i, action) in actions.enumerated() {
            let mid = 90 - CGFloat(i) * step
            let path = wedge(mid: mid)
            if i == hovered {
                NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.1, alpha: 0.95).setFill()
            } else {
                NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.7, alpha: 0.82).setFill()
            }
            path.fill()
            NSColor(white: 1, alpha: 0.5).setStroke()
            path.lineWidth = 1
            path.stroke()

            let labelRadius = (outer + inner) / 2
            let rad = mid * .pi / 180
            let p = NSPoint(x: center.x + cos(rad) * labelRadius, y: center.y + sin(rad) * labelRadius)
            drawLabel(action, at: p, active: i == hovered)
        }
        drawCenter()
    }

    private func wedge(mid: CGFloat) -> NSBezierPath {
        let start = mid + step / 2 - gap
        let end = mid - step / 2 + gap
        func point(_ r: CGFloat, _ deg: CGFloat) -> NSPoint {
            NSPoint(x: center.x + cos(deg * .pi / 180) * r, y: center.y + sin(deg * .pi / 180) * r)
        }
        let path = NSBezierPath()
        path.move(to: point(inner, start))
        path.line(to: point(outer, start))
        path.appendArc(withCenter: center, radius: outer, startAngle: start, endAngle: end, clockwise: true)
        path.line(to: point(inner, end))
        path.appendArc(withCenter: center, radius: inner, startAngle: end, endAngle: start, clockwise: false)
        path.close()
        return path
    }

    private func drawLabel(_ action: WheelAction, at p: NSPoint, active: Bool) {
        let color: NSColor = active ? .white : NSColor(calibratedWhite: 0.25, alpha: 1)
        if let symbol = NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
                .applying(.init(paletteColors: [color]))
            let img = symbol.withSymbolConfiguration(config) ?? symbol
            let size = img.size
            img.draw(in: NSRect(x: p.x - size.width / 2, y: p.y - size.height / 2 + 8, width: size.width, height: size.height))
        }
        let text = NSAttributedString(string: action.title.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: color,
        ])
        let ts = text.size()
        text.draw(at: NSPoint(x: p.x - ts.width / 2, y: p.y - ts.height / 2 - 12))
    }

    private func drawCenter() {
        let r = inner - 8
        let circle = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        NSColor(white: 0.12, alpha: 0.55).setFill()
        circle.fill()

        var line1 = busy ? "…" : (hovered.map { actions[$0].title } ?? "Rilascia")
        var line2 = files.count > 1 ? "\(files.count) file" : sizeString(files.first)
        if line1.count > 12 { line1 = String(line1.prefix(11)) + "…" }
        if line2.isEmpty { line2 = " " }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        for (text, size, dy, alpha) in [(line1, CGFloat(12), CGFloat(4), CGFloat(1)), (line2, CGFloat(10), CGFloat(-12), CGFloat(0.7))] {
            let s = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: .semibold),
                .foregroundColor: NSColor(white: 1, alpha: alpha),
                .paragraphStyle: paragraph,
            ])
            let ts = s.size()
            s.draw(at: NSPoint(x: center.x - ts.width / 2, y: center.y + dy - ts.height / 2))
        }
    }

    private func sizeString(_ url: URL?) -> String {
        guard let url,
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    // MARK: Hit test

    private func index(at windowPoint: NSPoint) -> Int? {
        let p = convert(windowPoint, from: nil)
        let dx = p.x - center.x, dy = p.y - center.y
        let dist = hypot(dx, dy)
        guard dist >= inner - 4, dist <= outer + 10, !actions.isEmpty else { return nil }
        let angle = atan2(dy, dx) * 180 / .pi
        var i = Int(((90 - angle) / step).rounded())
        i = ((i % actions.count) + actions.count) % actions.count
        return i
    }

    // MARK: Trascinamento

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        update(sender)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        update(sender)
        return hovered == nil ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        hovered = nil
        needsDisplay = true
    }

    private func update(_ sender: NSDraggingInfo) {
        let i = index(at: sender.draggingLocation)
        if i != hovered {
            hovered = i
            needsDisplay = true
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let i = index(at: sender.draggingLocation) else { return false }
        let urls = (sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]) ?? files
        let action = actions[i]
        busy = true
        needsDisplay = true
        Task {
            await Runner.run(action, on: urls)
            await MainActor.run { self.onFinished?() }
        }
        return true
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        if !busy { onFinished?() }
    }
}
