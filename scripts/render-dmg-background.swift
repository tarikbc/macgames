import AppKit

// Usage: swift scripts/render-dmg-background.swift out-dir
// Writes dmg-background.png (660x520) and dmg-background@2x.png for the installer window.
// Everything sits in the top 440 points; the field continues below, because the height
// of Finder's window chrome differs between macOS versions.
//
// The art follows the app and the website: the italic title lit by the icon's amber glow,
// soft color glows over a grid floor, and a rounded glass panel the icons stand on, with
// the app's capsule download bar between them. Finder draws the file names under the
// icons itself, in black on this background, so the panel's luminance keeps black and
// white text at 4.5:1 or more where the names sit.

let W = 660.0, H = 520.0
let appCenter = NSPoint(x: 190, y: 236), folderCenter = NSPoint(x: 470, y: 236)

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
let navy = srgb(0x141A33), violet = srgb(0x331C54), deep = srgb(0x1E1238)
let amber = srgb(0xE8A33A), amberHi = srgb(0xF2B453), ember = srgb(0xC7403A), glow = srgb(0x6E4CE6)
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

func radial(_ colors: [NSColor], at center: NSPoint, radius: CGFloat) {
    NSGradient(colors: colors)!.draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
}

func draw() {
    NSGradient(colors: [navy, violet, deep])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 90)

    // Soft color glows, as behind the website's glass.
    radial([amber.withAlphaComponent(0.26), amber.withAlphaComponent(0)], at: NSPoint(x: 150, y: -20), radius: 330)
    radial([glow.withAlphaComponent(0.32), glow.withAlphaComponent(0)], at: NSPoint(x: 640, y: 220), radius: 320)
    radial([ember.withAlphaComponent(0.24), ember.withAlphaComponent(0)], at: NSPoint(x: 40, y: 470), radius: 300)

    // Grid floor that fades toward the horizon.
    let horizon = 150.0, vanish = NSPoint(x: W / 2, y: horizon - 70)
    let cg = NSGraphicsContext.current!.cgContext
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: NSRect(x: 0, y: horizon, width: W, height: H - horizon)).addClip()
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    let grid = NSBezierPath()
    for i in stride(from: -16.0, through: 16.0, by: 1) { grid.move(to: vanish); grid.line(to: NSPoint(x: W / 2 + i * 64, y: H)) }
    var y = horizon, step = 7.0
    while y < H { grid.move(to: NSPoint(x: 0, y: y)); grid.line(to: NSPoint(x: W, y: y)); y += step; step *= 1.3 }
    grid.lineWidth = 1
    srgb(0xB07CFF, 0.2).setStroke(); grid.stroke()
    NSGraphicsContext.current!.compositingOperation = .destinationIn
    NSGradient(colors: [NSColor.black.withAlphaComponent(0), .black])!.draw(in: NSRect(x: 0, y: horizon, width: W, height: 200), angle: 90)
    cg.endTransparencyLayer()
    NSGraphicsContext.restoreGraphicsState()

    // Title, lit from behind by the icon's glow, with its ember edge.
    radial([amber.withAlphaComponent(0.3), ember.withAlphaComponent(0.1), ember.withAlphaComponent(0)], at: NSPoint(x: W / 2, y: 58), radius: 210)
    let title = NSFont.systemFont(ofSize: 54, weight: .black, width: .condensed)
    func slanted(_ color: NSColor, dx: CGFloat, top: CGFloat) {
        let attributed = NSAttributedString(string: "MacGames", attributes: [.font: title, .foregroundColor: color, .kern: 0.5])
        let size = attributed.size(), baseline = top + title.ascender
        NSGraphicsContext.saveGraphicsState()
        let shear = NSAffineTransform()
        shear.transformStruct = NSAffineTransformStruct(m11: 1, m12: 0, m21: -0.21, m22: 1, tX: W / 2 + dx, tY: baseline)
        shear.concat()
        attributed.draw(at: NSPoint(x: -size.width / 2, y: -title.ascender))
        NSGraphicsContext.restoreGraphicsState()
    }
    slanted(ember, dx: 3, top: 21)
    withShadow(amber.withAlphaComponent(0.6), blur: 18) { slanted(.white, dx: 0, top: 18) }
    text("Windows games on your Mac", .systemFont(ofSize: 14, weight: .semibold), NSColor.white.withAlphaComponent(0.72),
         centerX: W / 2, top: 88, kern: 0.2)

    // The glass panel the icons stand on: rounded like the app's cards, with a hairline and a top light.
    let rect = NSRect(x: 40, y: 126, width: W - 80, height: 222)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 26, yRadius: 26)
    withShadow(NSColor.black.withAlphaComponent(0.45), blur: 34, offset: NSSize(width: 0, height: -14)) {
        panelCool.setFill(); shape.fill()
    }
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [panelWarm, panelCool])!.draw(in: rect, angle: 0)
    // The panel frosts the glows behind it: warm on the left, violet on the right.
    radial([amber.withAlphaComponent(0.16), amber.withAlphaComponent(0)], at: NSPoint(x: rect.minX + 40, y: rect.minY + 20), radius: 220)
    radial([glow.withAlphaComponent(0.14), glow.withAlphaComponent(0)], at: NSPoint(x: rect.maxX - 30, y: rect.minY + 40), radius: 220)
    // A warm light behind the app icon that fades before the name row.
    radial([amber.withAlphaComponent(0.42), ember.withAlphaComponent(0.14), ember.withAlphaComponent(0)], at: appCenter, radius: 76)
    // Top light, as on glass.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 70), angle: 90)
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.26).setStroke()
    let edge = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 25.5, yRadius: 25.5)
    edge.lineWidth = 1; edge.stroke()

    // The drag cue: the app's capsule download bar, filling toward Applications.
    let track = NSRect(x: 286, y: appCenter.y - 4, width: 76, height: 8)
    NSColor.white.withAlphaComponent(0.22).setFill()
    NSBezierPath(roundedRect: track, xRadius: 4, yRadius: 4).fill()
    let fill = NSRect(x: track.minX, y: track.minY, width: track.width * 0.72, height: track.height)
    withShadow(amber.withAlphaComponent(0.8), blur: 10) {
        NSGradient(colors: [amberHi, amber])!.draw(in: NSBezierPath(roundedRect: fill, xRadius: 4, yRadius: 4), angle: 0)
    }
    let chevron = NSBezierPath()
    chevron.move(to: NSPoint(x: track.maxX + 10, y: appCenter.y - 8))
    chevron.line(to: NSPoint(x: track.maxX + 18, y: appCenter.y))
    chevron.line(to: NSPoint(x: track.maxX + 10, y: appCenter.y + 8))
    chevron.lineWidth = 3; chevron.lineCapStyle = .round; chevron.lineJoinStyle = .round
    withShadow(amber.withAlphaComponent(0.7), blur: 6) { NSColor.white.setStroke(); chevron.stroke() }

    // Instruction on a glass capsule, led by a play glyph, with room to the window's bottom edge.
    let hint = NSAttributedString(string: "Drag MacGames into Applications, then open it from there.",
                                  attributes: [.font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
                                               .foregroundColor: NSColor.white.withAlphaComponent(0.88)])
    let pillWidth = hint.size().width + 50, pill = NSRect(x: W / 2 - pillWidth / 2, y: 370, width: pillWidth, height: 30)
    let capsule = NSBezierPath(roundedRect: pill, xRadius: 15, yRadius: 15)
    NSColor.white.withAlphaComponent(0.1).setFill(); capsule.fill()
    NSColor.white.withAlphaComponent(0.18).setStroke(); capsule.lineWidth = 1; capsule.stroke()
    let play = NSBezierPath()
    play.move(to: NSPoint(x: pill.minX + 16, y: pill.midY - 5)); play.line(to: NSPoint(x: pill.minX + 25, y: pill.midY))
    play.line(to: NSPoint(x: pill.minX + 16, y: pill.midY + 5)); play.close()
    amber.setFill(); play.fill()
    hint.draw(at: NSPoint(x: pill.minX + 34, y: pill.midY - hint.size().height / 2))
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try! render(scale: 1).write(to: out.appendingPathComponent("dmg-background.png"))
try! render(scale: 2).write(to: out.appendingPathComponent("dmg-background@2x.png"))
