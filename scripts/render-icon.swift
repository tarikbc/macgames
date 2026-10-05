import AppKit

// Usage: swift scripts/render-icon.swift out.png
// Renders the MacGames app icon at 1024 px: a macOS squircle with a deep gradient,
// a warm glow in the two game accents, and a white controller glyph.
let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    let inset = 100.0, rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowBlurRadius = 28; shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35); shadow.set()
    NSColor.black.setFill(); shape.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    shape.addClip()
    NSGradient(colors: [NSColor(srgbRed: 0.08, green: 0.10, blue: 0.20, alpha: 1),
                        NSColor(srgbRed: 0.20, green: 0.11, blue: 0.33, alpha: 1)])!.draw(in: rect, angle: -60)
    // Warm glow: AoE IV red into CS2 amber.
    let glow = NSGradient(colors: [NSColor(srgbRed: 0.91, green: 0.64, blue: 0.23, alpha: 0.85),
                                   NSColor(srgbRed: 0.78, green: 0.25, blue: 0.23, alpha: 0.45),
                                   NSColor(srgbRed: 0.78, green: 0.25, blue: 0.23, alpha: 0)])!
    glow.draw(fromCenter: NSPoint(x: size / 2, y: size * 0.36), radius: 0,
              toCenter: NSPoint(x: size / 2, y: size * 0.36), radius: 430, options: [])
    // Soft top highlight.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: 430, weight: .semibold)
    if let glyph = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let tinted = NSImage(size: glyph.size, flipped: false) { r in
            glyph.draw(in: r); NSColor.white.set(); r.fill(using: .sourceAtop); return true
        }
        let w = glyph.size.width, h = glyph.size.height
        NSGraphicsContext.current?.saveGraphicsState()
        let s = NSShadow(); s.shadowBlurRadius = 30; s.shadowOffset = NSSize(width: 0, height: -10)
        s.shadowColor = NSColor.black.withAlphaComponent(0.45); s.set()
        tinted.draw(in: NSRect(x: (size - w) / 2, y: (size - h) / 2 - 10, width: w, height: h))
        NSGraphicsContext.current?.restoreGraphicsState()
    }
    // Hairline edge.
    NSColor.white.withAlphaComponent(0.12).setStroke(); shape.lineWidth = 3; shape.stroke()
    return true
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
