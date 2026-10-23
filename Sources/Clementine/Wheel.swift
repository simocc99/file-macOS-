import AppKit
import UniformTypeIdentifiers

enum WheelMode { case convert, tools }

struct WheelAction {
    let id: String
    let title: String
    let symbol: String
    let run: @Sendable (URL) async throws -> Void
}

enum FileKind {
    case image, pdf, audio, video, text, other

    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "rtf", "rtfd", "doc", "docx", "odt", "html", "htm",
        "json", "csv", "xml", "yml", "yaml", "log", "swift", "py", "js", "ts",
    ]

    static func of(_ url: URL) -> FileKind {
        let ext = url.pathExtension.lowercased()
        if textExtensions.contains(ext) { return .text }
        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .text) { return .text }
        return .other
    }
}

enum Wheel {
    static func actions(mode: WheelMode, for url: URL) -> [WheelAction] {
        let kind = FileKind.of(url)
        let ext = url.pathExtension.lowercased()
        switch mode {
        case .convert: return convertActions(kind).filter { $0.id != ext && !(ext == "jpeg" && $0.id == "jpg") }
        case .tools: return toolActions(kind)
        }
    }

    private static func convertActions(_ kind: FileKind) -> [WheelAction] {
        func image(_ id: String, _ title: String, _ type: UTType) -> WheelAction {
            WheelAction(id: id, title: title, symbol: "photo") { _ = try Converters.convertImage($0, to: type) }
        }
        func audio(_ id: String, _ title: String) -> WheelAction {
            WheelAction(id: id, title: title, symbol: "waveform") { _ = try await Converters.convertAudio($0, ext: id) }
        }
        func video(_ id: String, _ title: String, _ type: AVFileTypeBox, preset: String) -> WheelAction {
            WheelAction(id: id, title: title, symbol: "film") {
                _ = try await Converters.exportAV($0, preset: preset, type: type.value, ext: id)
            }
        }
        func text(_ id: String, _ title: String, _ target: Converters.TextTarget) -> WheelAction {
            WheelAction(id: id, title: title, symbol: "doc.text") {
                _ = try await Converters.convertText($0, to: target)
            }
        }
        func pdfPages(_ id: String, _ title: String, _ type: UTType) -> WheelAction {
            WheelAction(id: id, title: title, symbol: "photo.on.rectangle") { _ = try Converters.pdfToImages($0, type: type) }
        }

        switch kind {
        case .image:
            return [
                image("png", "PNG", .png), image("jpg", "JPG", .jpeg), image("heic", "HEIC", .heic),
                image("tiff", "TIFF", .tiff), image("gif", "GIF", .gif), image("bmp", "BMP", .bmp),
                WheelAction(id: "pdf", title: "PDF", symbol: "doc.richtext") { _ = try Converters.imageToPDF($0) },
            ]
        case .pdf:
            return [
                pdfPages("png", "PNG", .png), pdfPages("jpg", "JPG", .jpeg),
                WheelAction(id: "txt", title: "TXT", symbol: "doc.text") { _ = try Converters.pdfToText($0) },
            ]
        case .audio:
            return [audio("m4a", "M4A"), audio("wav", "WAV"), audio("aiff", "AIFF"), audio("caf", "CAF")]
        case .video:
            return [
                video("mp4", "MP4", .init(.mp4), preset: AVAssetExportPresetHighestQuality),
                video("mov", "MOV", .init(.mov), preset: AVAssetExportPresetHighestQuality),
                video("m4a", "Audio", .init(.m4a), preset: AVAssetExportPresetAppleM4A),
            ]
        case .text:
            return [
                text("txt", "TXT", .txt), text("rtf", "RTF", .rtf),
                text("html", "HTML", .html), text("docx", "DOCX", .docx),
            ]
        case .other:
            return []
        }
    }

    private static func toolActions(_ kind: FileKind) -> [WheelAction] {
        let compress = WheelAction(id: "compress", title: "Comprimi", symbol: "arrow.down.right.and.arrow.up.left") {
            _ = try await Converters.compress($0)
        }
        let metadata = WheelAction(id: "metadata", title: "Metadati", symbol: "tag") {
            _ = try Converters.stripMetadata($0)
        }
        let crop = WheelAction(id: "crop", title: "Ritaglia", symbol: "crop") {
            _ = try Converters.cropSquare($0)
        }
        let edit = WheelAction(id: "edit", title: "Modifica", symbol: "slider.horizontal.3") { url in
            await MainActor.run { Editors.edit(url) }
        }
        let addBG = WheelAction(id: "addbg", title: "Sfondo", symbol: "photo.artframe") { url in
            await MainActor.run { Editors.addBackground(url) }
        }
        switch kind {
        case .image: return [compress, metadata, crop, edit, addBG]
        case .pdf: return [compress, metadata, edit]
        case .audio, .video: return [compress, edit]
        case .text: return [edit]
        case .other: return []
        }
    }
}

import AVFoundation

/// AVFileType non è Sendable: lo incapsuliamo per usarlo nelle closure.
struct AVFileTypeBox: @unchecked Sendable {
    let value: AVFileType
    init(_ value: AVFileType) { self.value = value }
}

enum Runner {
    static func run(_ action: WheelAction, on urls: [URL]) async {
        let opensWindow = ["edit", "addbg"].contains(action.id)
        var done: [URL] = []
        for url in urls {
            if !opensWindow {
                await MainActor.run {
                    Toast.shared.show("\(action.title)… \(url.lastPathComponent)", symbol: "hourglass", duration: nil)
                }
            }
            do {
                try await action.run(url)
                done.append(url)
            } catch {
                if Prefs.bool("soundEnabled") { NSSound(named: "Basso")?.play() }
                await MainActor.run {
                    Toast.shared.hide()
                    let alert = NSAlert()
                    alert.messageText = "Operazione non riuscita"
                    alert.informativeText = "\(url.lastPathComponent): \(error.localizedDescription)"
                    alert.runModal()
                }
            }
        }
        guard !opensWindow else { return }
        if let first = done.first {
            if Prefs.bool("soundEnabled") { NSSound(named: "Glass")?.play() }
            let name = done.count > 1 ? "\(done.count) file" : first.lastPathComponent
            await MainActor.run {
                Toast.shared.show("Fatto · \(name) — clic per mostrare", symbol: "checkmark.circle.fill",
                                  tint: .systemGreen, reveal: first.deletingLastPathComponent())
            }
        } else {
            await MainActor.run { Toast.shared.hide() }
        }
    }
}
