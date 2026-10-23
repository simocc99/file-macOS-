import SwiftUI

/// Tiene vive le finestre aperte dall'app (che è senza Dock).
enum Windows {
    private static var open: [NSWindow] = []

    @MainActor
    static func show<V: View>(title: String, size: CGSize, @ViewBuilder content: () -> V) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content())
        window.center()
        open.append(window)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { note in
            open.removeAll { $0 === note.object as? NSWindow }
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

enum Onboarding {
    @MainActor
    static func show() {
        Windows.show(title: "Clementine", size: CGSize(width: 440, height: 320)) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Clementine").font(.largeTitle.bold())
                Text("Trascina un file e tieni premuto un tasto:")
                    .font(.headline)
                Label("**Shift** — menu rotondo per convertire (immagini, PDF, audio, video, documenti)", systemImage: "arrow.triangle.2.circlepath")
                Label("**Option** — menu rotondo con gli strumenti (comprimi, metadati, ritaglia, modifica, sfondo)", systemImage: "wand.and.stars")
                Text("Lascia il file su uno spicchio: il risultato viene salvato accanto all'originale, che non viene mai toccato. Tutto avviene sul tuo Mac, niente viene caricato online.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(24)
        }
    }
}
