import SwiftUI

enum Editors {
    @MainActor
    static func edit(_ url: URL) {
        guard FileKind.of(url) == .text, let text = try? Converters.loadAttributed(url).string else {
            NSWorkspace.shared.open(url)
            return
        }
        Windows.show(title: url.lastPathComponent, size: CGSize(width: 720, height: 520)) {
            TextEditorView(url: url, initialText: text)
        }
    }

    @MainActor
    static func addBackground(_ url: URL) {
        guard let image = try? Converters.loadImage(url, maxPixel: 3000) else { return }
        Windows.show(title: "Aggiungi sfondo", size: CGSize(width: 560, height: 640)) {
            BackgroundView(url: url, image: image)
        }
    }
}

struct TextEditorView: View {
    let url: URL
    @State var text: String
    @State private var status = ""

    init(url: URL, initialText: String) {
        self.url = url
        _text = State(initialValue: initialText)
    }

    /// I file di testo semplice si salvano sul posto; i documenti (docx, rtf, html…) in una copia accanto.
    private var isPlain: Bool {
        !["rtf", "rtfd", "doc", "docx", "odt", "html", "htm"].contains(url.pathExtension.lowercased())
    }

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
            Divider()
            HStack {
                Text(status).foregroundStyle(.secondary)
                Spacer()
                Text("\(text.count) caratteri").foregroundStyle(.secondary)
                Button(isPlain ? "Salva" : "Salva una copia") { save() }
                    .keyboardShortcut("s")
            }
            .padding(10)
        }
    }

    private func save() {
        do {
            if isPlain {
                try text.write(to: url, atomically: true, encoding: .utf8)
                status = "Salvato"
            } else {
                let out = Converters.output(for: url, ext: url.pathExtension, suffix: "edited")
                let attributed = NSAttributedString(string: text)
                let type: NSAttributedString.DocumentType = {
                    switch url.pathExtension.lowercased() {
                    case "docx": return .officeOpenXML
                    case "html", "htm": return .html
                    default: return .rtf
                    }
                }()
                let data = try attributed.data(
                    from: NSRange(location: 0, length: attributed.length),
                    documentAttributes: [.documentType: type]
                )
                try data.write(to: out)
                status = "Salvato come \(out.lastPathComponent)"
            }
        } catch {
            status = error.localizedDescription
        }
    }
}

struct BackgroundView: View {
    let url: URL
    let image: CGImage

    private static let palettes: [[Color]] = [
        [.orange, .pink], [.yellow, .orange], [.green, .mint], [.cyan, .blue],
        [.purple, .indigo], [.pink, .purple], [Color(white: 0.2), .black], [.white, Color(white: 0.85)],
    ]

    @State private var palette = 0
    @State private var padding = 80.0
    @State private var corner = 24.0
    @State private var shadow = 30.0
    @State private var status = ""

    private var size: CGSize {
        CGSize(width: Double(image.width) + padding * 2, height: Double(image.height) + padding * 2)
    }

    private var composite: some View {
        ZStack {
            LinearGradient(colors: Self.palettes[palette], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(decorative: image, scale: 1)
                .clipShape(RoundedRectangle(cornerRadius: corner))
                .shadow(color: .black.opacity(0.4), radius: shadow, y: shadow / 3)
        }
        .frame(width: size.width, height: size.height)
    }

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let scale = min(geo.size.width / size.width, geo.size.height / size.height)
                composite
                    .scaleEffect(scale)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            HStack {
                ForEach(0..<Self.palettes.count, id: \.self) { i in
                    Circle()
                        .fill(LinearGradient(colors: Self.palettes[i], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(Color.primary, lineWidth: i == palette ? 2 : 0))
                        .onTapGesture { palette = i }
                }
            }
            Slider(value: $padding, in: 0...300) { Text("Margine") }
            Slider(value: $corner, in: 0...80) { Text("Angoli") }
            Slider(value: $shadow, in: 0...80) { Text("Ombra") }
            HStack {
                Text(status).foregroundStyle(.secondary)
                Spacer()
                Button("Salva con sfondo") { save() }.keyboardShortcut("s")
            }
        }
        .padding(16)
    }

    @MainActor
    private func save() {
        let renderer = ImageRenderer(content: composite)
        renderer.scale = 1
        guard let cg = renderer.cgImage else { status = "Rendering non riuscito"; return }
        let out = Converters.output(for: url, ext: "png", suffix: "Background")
        do {
            try Converters.write(cg, as: .png, to: out)
            status = "Salvato come \(out.lastPathComponent)"
        } catch {
            status = error.localizedDescription
        }
    }
}
