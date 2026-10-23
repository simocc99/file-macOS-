import AppKit

// Disegna l'icona di Clementine (squircle arancione con la ruota a spicchi)
// in tutte le dimensioni richieste da iconutil. Uso: swift make-icon.swift <cartella.iconset>

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)

    let bg = NSBezierPath(roundedRect: NSRect(x: s * 0.05, y: s * 0.05, width: s * 0.9, height: s * 0.9),
                          xRadius: s * 0.2, yRadius: s * 0.2)
    NSGradient(starting: NSColor(calibratedRed: 1.0, green: 0.7, blue: 0.2, alpha: 1),
               ending: NSColor(calibratedRed: 0.96, green: 0.38, blue: 0.04, alpha: 1))!.draw(in: bg, angle: -90)

    let c = NSPoint(x: s / 2, y: s / 2)
    let outer = s * 0.34, inner = s * 0.13, count = 7, step = 360.0 / Double(count), gap = 3.0
    func pt(_ r: CGFloat, _ deg: Double) -> NSPoint {
        NSPoint(x: c.x + r * CGFloat(cos(deg * .pi / 180)), y: c.y + r * CGFloat(sin(deg * .pi / 180)))
    }
    for i in 0..<count {
        let mid = 90 - Double(i) * step
        let a = mid + step / 2 - gap, b = mid - step / 2 + gap
        let path = NSBezierPath()
        path.move(to: pt(inner, a))
        path.line(to: pt(outer, a))
        path.appendArc(withCenter: c, radius: outer, startAngle: CGFloat(a), endAngle: CGFloat(b), clockwise: true)
        path.line(to: pt(inner, b))
        path.appendArc(withCenter: c, radius: inner, startAngle: CGFloat(b), endAngle: CGFloat(a), clockwise: false)
        path.close()
        NSColor(white: 1, alpha: i == 0 ? 1 : 0.8).setFill()
        path.fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base).png"))
    try render(base * 2).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base)@2x.png"))
}
