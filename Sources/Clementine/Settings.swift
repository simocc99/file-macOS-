import SwiftUI
import ServiceManagement

enum Prefs {
    /// Le opzioni sono tutte attive finché l'utente non le spegne.
    static func bool(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}

struct SettingsView: View {
    @AppStorage("shiftEnabled") private var shiftEnabled = true
    @AppStorage("optionEnabled") private var optionEnabled = true
    @AppStorage("soundEnabled") private var soundEnabled = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Menu rotondo") {
                Toggle("Shift + trascina: converti", isOn: $shiftEnabled)
                Toggle("Option + trascina: strumenti", isOn: $optionEnabled)
            }
            Section("Generale") {
                Toggle("Suono a operazione conclusa", isOn: $soundEnabled)
                Toggle("Apri Clementine all'avvio del Mac", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
    }
}

enum SettingsWindow {
    @MainActor
    static func show() {
        Windows.show(title: "Impostazioni di Clementine", size: CGSize(width: 420, height: 300)) {
            SettingsView()
        }
    }
}
