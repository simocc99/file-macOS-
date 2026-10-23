import SwiftUI

@main
struct ClementineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Clementine", systemImage: "circle.hexagongrid.fill") {
            Button("Come si usa…") { Onboarding.show() }
            Button("Impostazioni…") { SettingsWindow.show() }
                .keyboardShortcut(",")
            Divider()
            Button("Esci") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        DragMonitor.shared.start()
        if !UserDefaults.standard.bool(forKey: "onboardingShown") {
            UserDefaults.standard.set(true, forKey: "onboardingShown")
            Onboarding.show()
        }
    }
}
