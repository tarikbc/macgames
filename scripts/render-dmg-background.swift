import AppKit

// Usage: swift scripts/render-dmg-background.swift out-dir
// Writes dmg-background.png (660x520) and dmg-background@2x.png for the installer window.
// Everything sits in the top 440 points; the field continues below, because the height
// of Finder's window chrome differs between macOS versions.
//
// The art reads like a game's title screen, in the app icon's colors: a navy-to-violet
// field over a grid floor, an italic heavy title lit by the icon's amber glow, and a HUD
// panel with cut corners. Finder draws the file names under the icons itself, in black
// on this background, so the panel's luminance keeps black and white text at 4.5:1 or more.

let W = 660.0, H = 520.0
let appCenter = NSPoint(x: 190, y: 236), folderCenter = NSPoint(x: 470, y: 236)

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
let navy = srgb(0x141A33), violet = srgb(0x331C54), deep = srgb(0x1E1238)
let amber = srgb(0xE8A33A), ember = srgb(0xC7403A)
// Both panel tones have a relative luminance near 0.18: white and black text each reach about 4.6:1.
let panelWarm = srgb(0x8A67AD), panelCool = srgb(0x7C6BAF)

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    // Top-left origin, like Finder's icon positions; `flipped` keeps text upright.
    let context = NSGraphicsContext(cgContext: NSGraphicsContext(bitmapImageRep: rep)!.cgContext, flipped: true)
    context.cgContext.translateBy(x: 0, y: H)
    context.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = context
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func withShadow(_ color: NSColor, blur: CGFloat, offset: NSSize = .zero, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color; shadow.shadowBlurRadius = blur; shadow.shadowOffset = offset
    shadow.set()
    body()
    NSGraphicsContext.restoreGraphicsState()
}

func text(_ string: String, _ font: NSFont, _ color: NSColor, centerX: CGFloat, top: CGFloat, kern: CGFloat = 0) {
    let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .kern: kern])
    attributed.draw(at: NSPoint(x: centerX - attributed.size().width / 2, y: top))
}

/// A rectangle with its four corners cut at 45 degrees.
func panel(_ r: NSRect, cut c: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: r.minX + c, y: r.minY))
    p.line(to: NSPoint(x: r.maxX - c, y: r.minY)); p.line(to: NSPoint(x: r.maxX, y: r.minY + c))
    p.line(to: NSPoint(x: r.maxX, y: r.maxY - c)); p.line(to: NSPoint(x: r.maxX - c, y: r.maxY))
    p.line(to: NSPoint(x: r.minX + c, y: r.maxY)); p.line(to: NSPoint(x: r.minX, y: r.maxY - c))
    p.line(to: NSPoint(x: r.minX, y: r.minY + c)); p.close()
    return p
}

func draw() {
    NSGradient(colors: [navy, violet, deep])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 90)

    // Grid floor: lines run to a vanishing point behind the title and fade toward it.
    let horizon = 150.0, vanish = NSPoint(x: W / 2, y: horizon - 70)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: NSRect(x: 0, y: horizon, width: W, height: H - horizon)).addClip()
    let grid = NSBezierPath()
    for i in stride(from: -16.0, through: 16.0, by: 1) {
        grid.move(to: vanish); grid.line(to: NSPoint(x: W / 2 + i * 64, y: H))
    }
    var y = horizon, step = 7.0
    while y < H { grid.move(to: NSPoint(x: 0, y: y)); grid.line(to: NSPoint(x: W, y: y)); y += step; step *= 1.3 }
    grid.lineWidth = 1
    let cg = NSGraphicsContext.current!.cgContext
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    srgb(0xB07CFF, 0.24).setStroke(); grid.stroke()
    // Mask the lines so they fade out toward the horizon.
    NSGraphicsContext.current!.compositingOperation = .destinationIn
    NSGradient(colors: [NSColor.black.withAlphaComponent(0), .black])!
        .draw(in: NSRect(x: 0, y: horizon, width: W, height: 200), angle: 90)
    cg.endTransparencyLayer()
    NSGraphicsContext.restoreGraphicsState()

    // Title, lit from behind by the icon's glow, with an ember offset like an arcade marquee.
    NSGradient(colors: [amber.withAlphaComponent(0.34), ember.withAlphaComponent(0.12), ember.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: W / 2, y: 58), radius: 0, toCenter: NSPoint(x: W / 2, y: 58), radius: 220, options: [])
    // The condensed face has no italic, so the title is sheared 12 degrees around its baseline.
    let title = NSFont.systemFont(ofSize: 54, weight: .black, width: .condensed)
    func slanted(_ color: NSColor, dx: CGFloat, top: CGFloat) {
        let attributed = NSAttributedString(string: "MacGames", attributes: [.font: title, .foregroundColor: color, .kern: 0.5])
        let size = attributed.size(), baseline = top + title.ascender
        NSGraphicsContext.saveGraphicsState()
        let shear = NSAffineTransform()
        shear.translateX(by: W / 2 + dx, yBy: baseline)
        shear.transformStruct = NSAffineTransformStruct(m11: 1, m12: 0, m21: -0.21, m22: 1, tX: W / 2 + dx, tY: baseline)
        shear.concat()
        attributed.draw(at: NSPoint(x: -size.width / 2, y: -title.ascender))
        NSGraphicsContext.restoreGraphicsState()
    }
    slanted(ember, dx: 3, top: 21)
    withShadow(amber.withAlphaComponent(0.6), blur: 18) { slanted(.white, dx: 0, top: 18) }
    text("Windows games on your Mac", .systemFont(ofSize: 14, weight: .semibold), NSColor.white.withAlphaComponent(0.7),
         centerX: W / 2, top: 88, kern: 0.3)

    // HUD panel the icons stand on.
    let rect = NSRect(x: 40, y: 126, width: W - 80, height: 222), cut = 22.0
    let shape = panel(rect, cut: cut)
    withShadow(NSColor.black.withAlphaComponent(0.5), blur: 30, offset: NSSize(width: 0, height: -12)) {
        panelCool.setFill(); shape.fill()
    }
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [panelWarm, panelCool])!.draw(in: rect, angle: 0)
    // A spotlight behind the app icon that fades before the name row.
    NSGradient(colors: [amber.withAlphaComponent(0.45), ember.withAlphaComponent(0.16), ember.withAlphaComponent(0)])!
        .draw(fromCenter: appCenter, radius: 0, toCenter: appCenter, radius: 76, options: [])
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.12), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 56), angle: 90)
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.24).setStroke()
    shape.lineWidth = 1; shape.stroke()

    // Amber brackets on the cut corners, like a targeting frame.
    let brackets = NSBezierPath(), arm = 24.0, inset = 7.0
    for (cx, sx) in [(rect.minX, 1.0), (rect.maxX, -1.0)] {
        for (cy, sy) in [(rect.minY, 1.0), (rect.maxY, -1.0)] {
            brackets.move(to: NSPoint(x: cx + sx * inset, y: cy + sy * (cut + arm)))
            brackets.line(to: NSPoint(x: cx + sx * inset, y: cy + sy * (cut + 3)))
            brackets.line(to: NSPoint(x: cx + sx * (cut + 3), y: cy + sy * inset))
            brackets.line(to: NSPoint(x: cx + sx * (cut + arm), y: cy + sy * inset))
        }
    }
    brackets.lineWidth = 3; brackets.lineCapStyle = .square; brackets.lineJoinStyle = .miter
    withShadow(amber.withAlphaComponent(0.7), blur: 7) { amber.setStroke(); brackets.stroke() }

    // The drag cue: an install bar that fills toward Applications.
    let segments = 6, segW = 12.0, gap = 5.0
    let barX = (appCenter.x + folderCenter.x) / 2 - (Double(segments) * (segW + gap) + 12) / 2
    for i in 0..<segments {
        let t = Double(i) / Double(segments - 1)
        let segment = NSBezierPath(rect: NSRect(x: barX + Double(i) * (segW + gap), y: appCenter.y - 5, width: segW, height: 10))
        let color = amber.blended(withFraction: t, of: ember) ?? amber
        withShadow(color.withAlphaComponent(0.25 + 0.6 * t), blur: 8) { color.setFill(); segment.fill() }
    }
    let tipX = barX + Double(segments) * (segW + gap)
    let tip = NSBezierPath()
    tip.move(to: NSPoint(x: tipX, y: appCenter.y - 11)); tip.line(to: NSPoint(x: tipX + 12, y: appCenter.y))
    tip.line(to: NSPoint(x: tipX, y: appCenter.y + 11)); tip.close()
    withShadow(ember.withAlphaComponent(0.9), blur: 8) { NSColor.white.setFill(); tip.fill() }

    // Instruction, led by a play glyph as the prompt. Below it, 44 points of field to the window edge.
    let hint = NSAttributedString(string: "Drag MacGames into Applications, then open it from there.",
                                  attributes: [.font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
                                               .foregroundColor: NSColor.white.withAlphaComponent(0.8)])
    let start = W / 2 - (hint.size().width + 18) / 2, top = 378.0
    let play = NSBezierPath()
    play.move(to: NSPoint(x: start, y: top + 3.5)); play.line(to: NSPoint(x: start + 9, y: top + 8.5))
    play.line(to: NSPoint(x: start, y: top + 13.5)); play.close()
    withShadow(amber.withAlphaComponent(0.8), blur: 5) { amber.setFill(); play.fill() }
    hint.draw(at: NSPoint(x: start + 18, y: top))
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try! render(scale: 1).write(to: out.appendingPathComponent("dmg-background.png"))
try! render(scale: 2).write(to: out.appendingPathComponent("dmg-background@2x.png"))
