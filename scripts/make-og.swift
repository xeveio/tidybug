// Social preview card (1200×630) for tidybug.xeve.io.
// Usage: swift scripts/make-og.swift <overview.png> <icon.png> <out.png>
import AppKit

let args = CommandLine.arguments
guard args.count >= 4, let shot = NSImage(contentsOfFile: args[1]), let icon = NSImage(contentsOfFile: args[2]) else {
    print("usage: make-og.swift overview.png icon.png out.png"); exit(1)
}
let W = 1200, H = 630
func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: a)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W * 2, pixelsHigh: H * 2, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let full = NSRect(x: 0, y: 0, width: W, height: H)

hex(0x0A0B0D).setFill(); full.fill()
// Dot grid
hex(0xFFFFFF, 0.06).setFill()
for y in stride(from: CGFloat(11), to: CGFloat(H), by: 22) {
    for x in stride(from: CGFloat(11), to: CGFloat(W), by: 22) {
        NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 1.4, height: 1.4)).fill()
    }
}
// Accent glow
NSGradient(colors: [hex(0xFF5F57, 0.22), hex(0xFF5F57, 0)])!
    .draw(fromCenter: NSPoint(x: 900, y: 180), radius: 0, toCenter: NSPoint(x: 900, y: 180), radius: 520, options: [])

// Screenshot, bleeding off the right edge
let shotRect = NSRect(x: 600, y: 70, width: 820, height: 820 * shot.size.height / shot.size.width)
NSGraphicsContext.saveGraphicsState()
let clip = NSBezierPath(roundedRect: shotRect, xRadius: 16, yRadius: 16)
let shadow = NSShadow(); shadow.shadowColor = .black.withAlphaComponent(0.7); shadow.shadowBlurRadius = 40; shadow.shadowOffset = NSSize(width: 0, height: -16)
shadow.set()
hex(0x111317).setFill(); clip.fill()
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState()
clip.addClip()
shot.draw(in: shotRect, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
hex(0xFFFFFF, 0.12).setStroke(); clip.lineWidth = 1.5; clip.stroke()

// Copy
icon.draw(in: NSRect(x: 58, y: 430, width: 108, height: 108))
func text(_ s: String, _ font: NSFont, _ color: NSColor, at p: NSPoint) {
    NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .kern: -0.6]).draw(at: p)
}
text("TidyBug", .systemFont(ofSize: 34, weight: .bold), hex(0xEDEEF0), at: NSPoint(x: 70, y: 368))
let headline = NSMutableAttributedString(string: "Reclaim your disk.\n", attributes: [.font: NSFont.systemFont(ofSize: 54, weight: .heavy), .foregroundColor: hex(0xEDEEF0), .kern: -1.6])
headline.append(NSAttributedString(string: "Precisely.", attributes: [.font: NSFont.systemFont(ofSize: 54, weight: .heavy), .foregroundColor: hex(0xFF5F57), .kern: -1.6]))
let para = NSMutableParagraphStyle(); para.lineHeightMultiple = 0.92
headline.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: headline.length))
headline.draw(in: NSRect(x: 66, y: 190, width: 560, height: 160))
text("Disk cleaner for developers · macOS", .monospacedSystemFont(ofSize: 19, weight: .regular), hex(0x8C919A), at: NSPoint(x: 70, y: 146))
text("tidybug.xeve.io", .monospacedSystemFont(ofSize: 17, weight: .medium), hex(0x5D626C), at: NSPoint(x: 70, y: 58))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
print("  ✓ og.png")
