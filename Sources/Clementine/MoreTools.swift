import AppKit
import AVFoundation
import PDFKit
import UniformTypeIdentifiers

/// Strumenti aggiuntivi: trasformazioni di immagini, rotazione PDF, GIF da video, video senza audio.
extension Converters {
    // MARK: Immagini

    private static func edit(_ url: URL, suffix: String, _ transform: (CGImage) -> CGImage?) throws -> URL {
        let image = try loadImage(url)
        guard let result = transform(image) else { throw ConvertError.failed("Operazione non riuscita.") }
        let type = imageType(of: url)
        let out = output(for: url, ext: type.preferredFilenameExtension ?? "png", suffix: suffix)
        try write(result, as: type, to: out)
        return out
    }

    private static func canvas(width: Int, height: Int, gray: Bool = false, _ body: (CGContext) -> Void) -> CGImage? {
        let space = gray ? CGColorSpaceCreateDeviceGray() : CGColorSpace(name: CGColorSpace.sRGB)!
        let info = gray ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: info) else { return nil }
        ctx.interpolationQuality = .high
        body(ctx)
        return ctx.makeImage()
    }

    static func rotateImage(_ url: URL, clockwise: Bool) throws -> URL {
        try edit(url, suffix: "Rotated") { img in
            let w = img.width, h = img.height
            return canvas(width: h, height: w) { ctx in
                ctx.concatenate(clockwise
                    ? CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: CGFloat(w))
                    : CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: CGFloat(h), ty: 0))
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }
    }

    static func flipImage(_ url: URL) throws -> URL {
        try edit(url, suffix: "Flipped") { img in
            canvas(width: img.width, height: img.height) { ctx in
                ctx.translateBy(x: CGFloat(img.width), y: 0)
                ctx.scaleBy(x: -1, y: 1)
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
            }
        }
    }

    static func resizeImage(_ url: URL, scale: Double) throws -> URL {
        try edit(url, suffix: "\(Int(scale * 100))%") { img in
            let w = max(Int(Double(img.width) * scale), 1), h = max(Int(Double(img.height) * scale), 1)
            return canvas(width: w, height: h) { $0.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h)) }
        }
    }

    static func grayscaleImage(_ url: URL) throws -> URL {
        try edit(url, suffix: "BW") { img in
            canvas(width: img.width, height: img.height, gray: true) {
                $0.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
            }
        }
    }

    static func cropRatio(_ url: URL, width rw: Int, height rh: Int) throws -> URL {
        try edit(url, suffix: "\(rw)x\(rh)") { img in
            let ratio = Double(rw) / Double(rh)
            var w = Double(img.width), h = w / ratio
            if h > Double(img.height) { h = Double(img.height); w = h * ratio }
            let rect = CGRect(x: (Double(img.width) - w) / 2, y: (Double(img.height) - h) / 2,
                              width: w.rounded(), height: h.rounded())
            return img.cropping(to: rect)
        }
    }

    // MARK: PDF

    static func rotatePDF(_ url: URL) throws -> URL {
        guard let doc = PDFDocument(url: url) else { throw ConvertError.unreadable }
        for i in 0..<doc.pageCount { doc.page(at: i)?.rotation += 90 }
        let out = output(for: url, ext: "pdf", suffix: "Rotated")
        guard doc.write(to: out) else { throw ConvertError.failed("Scrittura del file non riuscita.") }
        return out
    }

    // MARK: Video

    static func videoToGIF(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let fps = 10.0
        let count = max(Int(min(duration, 10) * fps), 1)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)

        let out = output(for: url, ext: "gif")
        guard let dst = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, count, nil)
        else { throw ConvertError.unsupported }
        let loop: [String: Any] = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]]
        CGImageDestinationSetProperties(dst, loop as CFDictionary)
        let frame: [String: Any] = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: 1 / fps]]
        for i in 0..<count {
            let time = CMTime(seconds: Double(i) / fps, preferredTimescale: 600)
            let (image, _) = try await generator.image(at: time)
            CGImageDestinationAddImage(dst, image, frame as CFDictionary)
        }
        guard CGImageDestinationFinalize(dst) else { throw ConvertError.failed("Scrittura del file non riuscita.") }
        return out
    }

    static func muteVideo(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw ConvertError.unreadable }
        let composition = AVMutableComposition()
        guard let target = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ConvertError.unsupported }
        let duration = try await asset.load(.duration)
        try target.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
        target.preferredTransform = try await track.load(.preferredTransform)

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else { throw ConvertError.unsupported }
        let isMP4 = ["mp4", "m4v"].contains(url.pathExtension.lowercased())
        let out = output(for: url, ext: isMP4 ? "mp4" : "mov", suffix: "Muted")
        session.outputURL = out
        session.outputFileType = isMP4 ? .mp4 : .mov
        await session.export()
        guard session.status == .completed else {
            throw session.error ?? ConvertError.failed("Esportazione non riuscita.")
        }
        return out
    }
}
