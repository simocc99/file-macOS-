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
        Windows.show(title: "Benvenuto in Clementine", size: CGSize(width: 480, height: 420)) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading) {
                        Text("Clementine").font(.largeTitle.bold())
                        Text("Converti e modifica file trascinandoli.").foregroundStyle(.secondary)
                    }
                }
                step(1, "Trascina un file", "Prendi un file dal Finder o dalla scrivania.")
                step(2, "Tieni premuto un tasto", "**Shift** per convertire, **Option** per gli strumenti: comprimi, metadati, ritaglia, modifica, sfondo.")
                step(3, "Lascia il file su uno spicchio", "Il risultato è salvato accanto all'originale, che non viene mai toccato.")
                Spacer()
                Label("Tutto avviene sul tuo Mac: niente viene caricato online.", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
        }
    }

    private static func step(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.orange))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(.init(detail)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
