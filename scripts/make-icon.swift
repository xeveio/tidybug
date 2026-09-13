// Renders the TidyBug app icon (dark squircle + geometric ladybug mark) and
// writes a complete AppIcon.appiconset.
// Usage: swift scripts/make-icon.swift TidyBug/Assets.xcassets/AppIcon.appiconset
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.appiconset")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 1024, height: 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    color(0x0A0B0D).setFill()
    squircle.fill()
    ctx.restoreGState()

    ctx.saveGState()
    squircle.addClip()
    NSGradient(colors: [color(0x1B1E24), color(0x0A0B0D)])!.draw(in: body, angle: -90)
    // Dot grid
    color(0xFFFFFF, 0.06).setFill()
    var y: CGFloat = 130
    while y < 924 {
        var x: CGFloat = 130
        while x < 924 { NSBezierPath(ovalIn: CGRect(x: x, y: y, width: 5, height: 5)).fill(); x += 44 }
        y += 44
    }
    // Accent glow
    NSGradient(colors: [color(0xFF5F57, 0.28), color(0xFF5F57, 0)])!
        .draw(fromCenter: NSPoint(x: 512, y: 470), radius: 0, toCenter: NSPoint(x: 512, y: 470), radius: 420, options: [])
    // Inner border
    color(0xFFFFFF, 0.10).setStroke()
    let inner = NSBezierPath(roundedRect: body.insetBy(dx: 2, dy: 2), xRadius: 184, yRadius: 184)
    inner.lineWidth = 3
    inner.stroke()
    ctx.restoreGState()

    // Mark (AppKit coordinates: y up). Mirrors LogoMark geometry at s = 520.
    let s: CGFloat = 520
    let origin = CGPoint(x: 512 - s / 2, y: 512 - s / 2 - 10)
    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * s, y: origin.y + (1 - y) * s) }

    // Head
    color(0x2A2D33).setFill()
    let hr = 0.19 * s
    let head = NSBezierPath(ovalIn: CGRect(x: P(0.5, 0.22).x - hr, y: P(0.5, 0.22).y - hr, width: hr * 2, height: hr * 2))
    head.fill()
    color(0xFFFFFF, 0.14).setStroke(); head.lineWidth = 5; head.stroke()

    // Shell halves with holes
    let r = 0.4 * s
    let c = P(0.5, 0.58)
    for left in [true, false] {
        let gap = r * 0.06
        let cx = left ? c.x - gap : c.x + gap
        let path = NSBezierPath()
        path.move(to: CGPoint(x: cx, y: c.y + r))
        path.appendArc(withCenter: CGPoint(x: cx, y: c.y), radius: r, startAngle: 90, endAngle: 270, clockwise: !left)
        path.close()
        let dir: CGFloat = left ? -1 : 1
        for (dx, dy, dr) in [(0.42, -0.18, 0.17), (0.5, 0.36, 0.13)] as [(CGFloat, CGFloat, CGFloat)] {
            let hc = CGPoint(x: cx + dir * dx * r, y: c.y - dy * r)
            path.appendOval(in: CGRect(x: hc.x - dr * r, y: hc.y - dr * r, width: dr * r * 2, height: dr * r * 2))
        }
        path.windingRule = .evenOdd
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 40, color: color(0xFF5F57, 0.45).cgColor)
        color(0xFF5F57).setFill()
        path.fill()
        ctx.restoreGState()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let px = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(px).write(to: outDir.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: outDir.appendingPathComponent("Contents.json"))
try #"{"info":{"author":"xcode","version":1}}"#.data(using: .utf8)!
    .write(to: outDir.deletingLastPathComponent().appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(outDir.path)")
