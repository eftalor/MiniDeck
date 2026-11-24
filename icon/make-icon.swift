// Builds icon/AppIcon.icns: a black playlist symbol on a white tile, in the style of the current Music icon.
// Run: swift icon/make-icon.swift   (from the project folder)
import AppKit

let out = "icon/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: out)
try! FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)


func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    // macOS icon grid: the tile is 824/1024 of the canvas, centered, with a soft shadow.
    let inset = s * 100 / 1024
    let tile = NSRect(x: inset, y: inset * 1.1, width: s - 2 * inset, height: s - 2 * inset)
    let radius = tile.width * 0.225
    let shape = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = s * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Apple's current Music icon style: a white tile shading to light grey at the bottom.
    NSGradient(starting: NSColor(white: 0.995, alpha: 1), ending: NSColor(white: 0.90, alpha: 1))!
        .draw(in: shape, angle: -90)
    NSColor(white: 0, alpha: 0.10).setStroke()
    let edge = NSBezierPath(roundedRect: tile.insetBy(dx: s * 0.002, dy: s * 0.002), xRadius: radius, yRadius: radius)
    edge.lineWidth = max(0.5, s * 0.003)
    edge.stroke()

    // Glossy black playlist symbol: draw it as a mask, fill with a dark-grey-to-black
    // gradient, and give it a soft drop shadow like the note in Music's icon.
    let cfg = NSImage.SymbolConfiguration(pointSize: tile.width * 0.5, weight: .semibold)
    if let sym = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let sz = sym.size
        let r = NSRect(x: tile.midX - sz.width / 2, y: tile.midY - sz.height / 2, width: sz.width, height: sz.height)
        let glyph = NSImage(size: sz, flipped: false) { b in
            NSGradient(starting: NSColor(white: 0.32, alpha: 1), ending: NSColor(white: 0.02, alpha: 1))!
                .draw(in: b, angle: -90)
            sym.draw(in: b, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
        NSGraphicsContext.saveGraphicsState()
        let gs = NSShadow()
        gs.shadowColor = NSColor.black.withAlphaComponent(0.28)
        gs.shadowBlurRadius = s * 0.012
        gs.shadowOffset = NSSize(width: 0, height: -s * 0.008)
        gs.set()
        glyph.draw(in: r)
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
                   ("128x128", 128), ("128x128@2x", 256), ("256x256", 256),
                   ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
print("wrote \(out)")
