import AppKit

private final class ToastPanel: NSPanel {
    var onClick: (() -> Void)?
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// Piccola notifica a pillola in basso sullo schermo: stato dell'operazione e,
/// al clic, "mostra nel Finder".
@MainActor
final class Toast {
    static let shared = Toast()

    private var panel: ToastPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ text: String, symbol: String, tint: NSColor = .systemOrange, reveal: URL? = nil, duration: Double? = 3) {
        hideTask?.cancel()
        panel?.orderOut(nil)

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        icon.contentTintColor = tint

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.lineBreakMode = .byTruncatingMiddle
        label.preferredMaxLayoutWidth = 340

        let stack = NSStackView(views: [icon, label])
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 20
        blur.layer?.masksToBounds = true
        blur.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: blur.topAnchor, constant: 11),
            stack.bottomAnchor.constraint(equalTo: blur.bottomAnchor, constant: -11),
        ])
        blur.layoutSubtreeIfNeeded()
        let size = blur.fittingSize

        let p = ToastPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.contentView = blur
        if let reveal {
            p.onClick = { [weak self] in
                NSWorkspace.shared.activateFileViewerSelecting([reveal])
                self?.hide()
            }
        }

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.minY + 56))
        }
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; p.animator().alphaValue = 1 }
        panel = p

        if let duration {
            hideTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.hide()
            }
        }
    }

    func hide() {
        guard let p = panel else { return }
        panel = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; p.animator().alphaValue = 0 }) {
            p.orderOut(nil)
        }
    }
}
