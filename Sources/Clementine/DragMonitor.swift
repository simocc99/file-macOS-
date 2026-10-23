import AppKit
import os

let clemLog = Logger(subsystem: "com.simocc99.clementine", category: "drag")

/// Osserva i trascinamenti di file in tutto il sistema e, con Shift/Option premuto,
/// mostra il menu rotondo sotto il cursore.
@MainActor
final class DragMonitor {
    static let shared = DragMonitor()

    private var monitors: [Any] = []
    private var dragChangeCountAtMouseDown = 0
    private let panel = WheelPanel()

    func start() {
        guard monitors.isEmpty else { return }
        let add = { (mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) in
            if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
                self.monitors.append(m)
            }
        }
        add(.leftMouseDown) { [weak self] _ in
            Task { @MainActor in
                self?.dragChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
            }
        }
        add(.leftMouseDragged) { [weak self] event in
            let flags = event.modifierFlags
            Task { @MainActor in self?.dragged(flags: flags) }
        }
        add(.leftMouseUp) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                self?.panel.dismiss()
            }
        }
    }

    private func dragged(flags: NSEvent.ModifierFlags) {
        guard !panel.isVisible else { return }
        clemLog.debug("dragged flags=\(flags.rawValue)")
        let mode: WheelMode
        if flags.contains(.shift), Prefs.bool("shiftEnabled") { mode = .convert }
        else if flags.contains(.option), Prefs.bool("optionEnabled") { mode = .tools }
        else { return }

        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragChangeCountAtMouseDown else {
            clemLog.debug("pasteboard changeCount invariato (\(pasteboard.changeCount))")
            return
        }
        let urls = (pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]) ?? []
        guard let first = urls.first else {
            clemLog.debug("nessun file URL nella pasteboard drag")
            return
        }

        let actions = Wheel.actions(mode: mode, for: first)
        guard !actions.isEmpty else { return }
        clemLog.debug("mostro menu: \(actions.count) azioni per \(first.lastPathComponent)")
        panel.present(actions: actions, files: urls, at: NSEvent.mouseLocation)
    }
}
