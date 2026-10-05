import AppKit

// Usage: swift scripts/render-og-image.swift <window screenshot.png> <out.jpg>
// The 1200x630 link preview for the website: the title screen of the installer art on the
// left, and a window of the app on the right.
let W = 1200.0, H = 630.0
func srgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(cgContext: NSGraphicsContext(bitmapImageRep: rep)!.cgContext, flipped: true)
ctx.cgContext.translateBy(x: 0, y: H); ctx.cgContext.scaleBy(x: 1, y: -1)
NSGraphicsContext.current = ctx

NSGradient(colors: [srgb(0x141A33), srgb(0x331C54), srgb(0x1E1238)])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 90)
// Grid floor in the lower half.
let horizon = 360.0, vanish = NSPoint(x: 330, y: 300)
NSGraphicsContext.saveGraphicsState()
NSBezierPath(rect: NSRect(x: 0, y: horizon, width: W, height: H - horizon)).addClip()
let grid = NSBezierPath()
for i in stride(from: -14.0, through: 14.0, by: 1) { grid.move(to: vanish); grid.line(to: NSPoint(x: 330 + i * 70, y: H)) }
var y = horizon, step = 6.0
while y < H { grid.move(to: NSPoint(x: 0, y: y)); grid.line(to: NSPoint(x: W, y: y)); y += step; step *= 1.35 }
grid.lineWidth = 1; srgb(0xB07CFF, 0.22).setStroke(); grid.stroke()
NSGraphicsContext.restoreGraphicsState()
NSGradient(colors: [srgb(0xE8A33A, 0.32), srgb(0xC7403A, 0.1), srgb(0xC7403A, 0)])!
    .draw(fromCenter: NSPoint(x: 300, y: 250), radius: 0, toCenter: NSPoint(x: 300, y: 250), radius: 300, options: [])

let title = NSFont.systemFont(ofSize: 96, weight: .black, width: .condensed)
func slanted(_ color: NSColor, dx: CGFloat, dy: CGFloat) {
    let s = NSAttributedString(string: "MacGames", attributes: [.font: title, .foregroundColor: color])
    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform()
    t.transformStruct = NSAffineTransformStruct(m11: 1, m12: 0, m21: -0.21, m22: 1, tX: 70 + dx, tY: 250 + dy)
    t.concat()
    s.draw(at: NSPoint(x: 0, y: -title.ascender))
    NSGraphicsContext.restoreGraphicsState()
}
slanted(srgb(0xC7403A), dx: 4, dy: 4)
let glow = NSShadow(); glow.shadowColor = srgb(0xE8A33A, 0.6); glow.shadowBlurRadius = 22
NSGraphicsContext.saveGraphicsState(); glow.set(); slanted(.white, dx: 0, dy: 0); NSGraphicsContext.restoreGraphicsState()
NSAttributedString(string: "Windows games on your Mac", attributes: [.font: NSFont.systemFont(ofSize: 30, weight: .semibold),
                                                                     .foregroundColor: NSColor.white.withAlphaComponent(0.85)])
    .draw(at: NSPoint(x: 74, y: 272))
NSAttributedString(string: "Steam, Battle.net and 20 games on Apple silicon", attributes: [.font: NSFont.systemFont(ofSize: 21, weight: .regular),
                                                                     .foregroundColor: NSColor.white.withAlphaComponent(0.6)])
    .draw(at: NSPoint(x: 74, y: 318))

// The app window, cropped by the right edge.
if let shot = NSImage(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])) {
    let h = 470.0, w = h * shot.size.width / shot.size.height
    shot.draw(in: NSRect(x: 600, y: 90, width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1,
              respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.86])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
