import AppKit
import AVFoundation
import PDFKit
import UniformTypeIdentifiers

enum ConvertError: LocalizedError {
    case unreadable, unsupported, failed(String)
    var errorDescription: String? {
        switch self {
        case .unreadable: return "Impossibile leggere il file."
        case .unsupported: return "Formato non supportato su questo Mac."
        case .failed(let m): return m
        }
    }
}

enum Converters {
    // MARK: Nomi dei file di output (sempre accanto all'originale, mai sovrascritti)

    static func output(for url: URL, ext: String, suffix: String? = nil) -> URL {
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent + (suffix.map { " " + $0 } ?? "")
        var candidate = dir.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    // MARK: Immagini

    static func loadImage(_ url: URL, maxPixel: Int = 100_000) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixel,
              ] as CFDictionary) else { throw ConvertError.unreadable }
        return img
    }

    private static func flattened(_ image: CGImage) -> CGImage {
        guard image.alphaInfo != .none, image.alphaInfo != .noneSkipFirst, image.alphaInfo != .noneSkipLast,
              let ctx = CGContext(
                  data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        return ctx.makeImage() ?? image
    }

    static func write(_ image: CGImage, as type: UTType, to out: URL, quality: Double = 0.9) throws {
        guard let dst = CGImageDestinationCreateWithURL(out as CFURL, type.identifier as CFString, 1, nil)
        else { throw ConvertError.unsupported }
        let opaque = [UTType.jpeg, .bmp].contains(type)
        CGImageDestinationAddImage(dst, opaque ? flattened(image) : image,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dst) else { throw ConvertError.failed("Scrittura del file non riuscita.") }
    }

    static func convertImage(_ url: URL, to type: UTType) throws -> URL {
        let out = output(for: url, ext: type.preferredFilenameExtension ?? "img")
        if type == .gif, let src = CGImageSourceCreateWithURL(url as CFURL, nil) {
            let count = CGImageSourceGetCount(src)
            guard let dst = CGImageDestinationCreateWithURL(out as CFURL, type.identifier as CFString, count, nil)
            else { throw ConvertError.unsupported }
            for i in 0..<count { CGImageDestinationAddImageFromSource(dst, src, i, nil) }
            guard CGImageDestinationFinalize(dst) else { throw ConvertError.failed("Scrittura del file non riuscita.") }
            return out
        }
        try write(try loadImage(url), as: type, to: out)
        return out
    }

    static func imageToPDF(_ url: URL) throws -> URL {
        let image = try loadImage(url)
        let out = output(for: url, ext: "pdf")
        var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let ctx = CGContext(out as CFURL, mediaBox: &box, nil) else { throw ConvertError.unsupported }
        ctx.beginPDFPage(nil)
        ctx.draw(image, in: box)
        ctx.endPDFPage()
        ctx.closePDF()
        return out
    }

    static func cropSquare(_ url: URL) throws -> URL {
        let image = try loadImage(url)
        let side = min(image.width, image.height)
        let rect = CGRect(x: (image.width - side) / 2, y: (image.height - side) / 2, width: side, height: side)
        guard let cropped = image.cropping(to: rect) else { throw ConvertError.failed("Ritaglio non riuscito.") }
        let type = Self.imageType(of: url)
        let out = output(for: url, ext: type.preferredFilenameExtension ?? "png", suffix: "Cropped")
        try write(cropped, as: type, to: out)
        return out
    }

    /// Tipo di scrittura sicuro per un'immagine: mantiene JPEG/HEIC/PNG/TIFF, altrimenti PNG.
    static func imageType(of url: URL) -> UTType {
        let type = UTType(filenameExtension: url.pathExtension.lowercased()) ?? .png
        return [UTType.jpeg, .heic, .png, .tiff].contains(where: { type.conforms(to: $0) }) ? type : .png
    }

    static func stripMetadata(_ url: URL) throws -> URL {
        if FileKind.of(url) == .pdf {
            guard let doc = PDFDocument(url: url) else { throw ConvertError.unreadable }
            doc.documentAttributes = [:]
            let out = output(for: url, ext: "pdf", suffix: "clean")
            guard doc.write(to: out) else { throw ConvertError.failed("Scrittura del PDF non riuscita.") }
            return out
        }
        // Ridisegnare l'immagine da zero elimina EXIF, GPS e il resto dei metadati.
        let type = imageType(of: url)
        let out = output(for: url, ext: type.preferredFilenameExtension ?? "png", suffix: "clean")
        try write(try loadImage(url), as: type, to: out, quality: 0.95)
        return out
    }

    // MARK: PDF

    static func pdfToImages(_ url: URL, type: UTType) throws -> [URL] {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { throw ConvertError.unreadable }
        let ext = type.preferredFilenameExtension ?? "png"
        let fileType: NSBitmapImageRep.FileType = type == .jpeg ? .jpeg : .png
        var results: [URL] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let image = page.thumbnail(of: CGSize(width: bounds.width * 2, height: bounds.height * 2), for: .mediaBox)
            guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let data = rep.representation(using: fileType, properties: [.compressionFactor: 0.9])
            else { throw ConvertError.failed("Pagina \(i + 1) non convertibile.") }
            let out = output(for: url, ext: ext, suffix: doc.pageCount > 1 ? "\(i + 1)" : nil)
            try data.write(to: out)
            results.append(out)
        }
        return results
    }

    static func pdfToText(_ url: URL) throws -> URL {
        guard let doc = PDFDocument(url: url), let text = doc.string, !text.isEmpty
        else { throw ConvertError.failed("Il PDF non contiene testo selezionabile.") }
        let out = output(for: url, ext: "txt")
        try text.write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    // MARK: Documenti di testo

    enum TextTarget { case txt, rtf, html, docx }

    private static let plainExtensions: Set<String> = ["rtf", "rtfd", "doc", "docx", "odt", "html", "htm"]

    @MainActor
    static func loadAttributed(_ url: URL) throws -> NSAttributedString {
        if plainExtensions.contains(url.pathExtension.lowercased()) {
            return try NSAttributedString(url: url, options: [:], documentAttributes: nil)
        }
        return NSAttributedString(string: try String(contentsOf: url, encoding: .utf8))
    }

    @MainActor
    static func convertText(_ url: URL, to target: TextTarget) throws -> URL {
        let text = try loadAttributed(url)
        let range = NSRange(location: 0, length: text.length)
        let ext: String
        let data: Data
        switch target {
        case .txt:
            ext = "txt"; data = Data(text.string.utf8)
        case .rtf:
            ext = "rtf"; data = try text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        case .html:
            ext = "html"; data = try text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.html])
        case .docx:
            ext = "docx"; data = try text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
        }
        let out = output(for: url, ext: ext)
        try data.write(to: out)
        return out
    }

    // MARK: Audio e video

    static func convertAudio(_ url: URL, ext: String, bitRate: Int = 192_000) async throws -> URL {
        let input = try AVAudioFile(forReading: url)
        let format = input.processingFormat
        let channels = Int(min(format.channelCount, 2))
        var settings: [String: Any] = [AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: channels]
        switch ext {
        case "m4a":
            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            settings[AVEncoderBitRateKey] = bitRate * channels / 2
        case "wav", "caf", "aiff":
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = ext == "aiff"
        default:
            throw ConvertError.unsupported
        }
        let out = output(for: url, ext: ext, suffix: ext == url.pathExtension.lowercased() ? "compressed" : nil)
        let output = try AVAudioFile(forWriting: out, settings: settings)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_768)
        else { throw ConvertError.failed("Memoria insufficiente.") }
        while input.framePosition < input.length {
            try input.read(into: buffer)
            try output.write(from: buffer)
        }
        return out
    }

    static func exportAV(_ url: URL, preset: String, type: AVFileType, ext: String, suffix: String? = nil) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset)
        else { throw ConvertError.unsupported }
        let out = output(for: url, ext: ext, suffix: suffix)
        session.outputURL = out
        session.outputFileType = type
        await session.export()
        guard session.status == .completed else {
            throw session.error ?? ConvertError.failed("Esportazione non riuscita.")
        }
        return out
    }

    // MARK: Comprimi

    static func compress(_ url: URL) async throws -> URL {
        switch FileKind.of(url) {
        case .image:
            let type = imageType(of: url) == .png ? UTType.png : .jpeg
            let out = output(for: url, ext: type.preferredFilenameExtension ?? "jpg", suffix: "compressed")
            try write(try loadImage(url, maxPixel: 2048), as: type, to: out, quality: 0.6)
            return out
        case .pdf:
            guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { throw ConvertError.unreadable }
            let out = output(for: url, ext: "pdf", suffix: "compressed")
            guard let ctx = CGContext(out as CFURL, mediaBox: nil, nil) else { throw ConvertError.unsupported }
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                let image = page.thumbnail(of: CGSize(width: bounds.width * 1.5, height: bounds.height * 1.5), for: .mediaBox)
                guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                      let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.5]),
                      let provider = CGDataProvider(data: jpeg as CFData),
                      let cg = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
                else { throw ConvertError.failed("Pagina \(i + 1) non comprimibile.") }
                var box = CGRect(origin: .zero, size: bounds.size)
                ctx.beginPDFPage([kCGPDFContextMediaBox as String: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary)
                ctx.draw(cg, in: box)
                ctx.endPDFPage()
            }
            ctx.closePDF()
            return out
        case .audio:
            return try await convertAudio(url, ext: "m4a", bitRate: 96_000)
        case .video:
            return try await exportAV(url, preset: AVAssetExportPresetMediumQuality, type: .mp4, ext: "mp4", suffix: "compressed")
        default:
            throw ConvertError.unsupported
        }
    }
}
