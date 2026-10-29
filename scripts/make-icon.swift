// Renders the myPaste app icon (1024×1024 PNG). Usage: swift make-icon.swift out.png
// scripts/make-icon.sh turns it into Resources/AppIcon.icns.
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// macOS icon grid: 824 pt body centred in 1024 with ~185 pt corner radius.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.black.setFill()
squircle.fill()
ctx.restoreGState()

squircle.addClip()
NSGradient(colors: [
    NSColor(srgbRed: 0.33, green: 0.30, blue: 0.95, alpha: 1),
    NSColor(srgbRed: 0.56, green: 0.29, blue: 0.93, alpha: 1),
    NSColor(srgbRed: 0.93, green: 0.36, blue: 0.62, alpha: 1),
])!.draw(in: body, angle: -60)
// Soft top highlight.
NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)

func card(_ rect: NSRect, rotate degrees: CGFloat, alpha: CGFloat, lines: Bool) {
    ctx.saveGState()
    ctx.translateBy(x: rect.midX, y: rect.midY)
    ctx.rotate(by: degrees * .pi / 180)
    let r = NSRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height)
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    NSColor.white.withAlphaComponent(alpha).setFill()
    NSBezierPath(roundedRect: r, xRadius: 46, yRadius: 46).fill()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    if lines {
        // Coloured header strip, like a myPaste card.
        let header = NSBezierPath(roundedRect: NSRect(x: r.minX, y: r.maxY - 96, width: r.width, height: 96), xRadius: 46, yRadius: 46)
        header.append(NSBezierPath(rect: NSRect(x: r.minX, y: r.maxY - 96, width: r.width, height: 48)))
        NSColor(srgbRed: 0.40, green: 0.33, blue: 0.95, alpha: 1).setFill()
        header.fill()
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: NSRect(x: r.maxX - 92, y: r.maxY - 74, width: 52, height: 52), xRadius: 14, yRadius: 14).fill()
        let widths: [CGFloat] = [0.78, 0.62, 0.70, 0.44]
        for (i, w) in widths.enumerated() {
            NSColor(srgbRed: 0.25, green: 0.24, blue: 0.40, alpha: 0.22 + (i == 0 ? 0.1 : 0)).setFill()
            NSBezierPath(roundedRect: NSRect(x: r.minX + 46, y: r.maxY - 160 - CGFloat(i) * 62, width: (r.width - 92) * w, height: 26),
                         xRadius: 13, yRadius: 13).fill()
        }
    }
    ctx.restoreGState()
}

card(NSRect(x: 300, y: 270, width: 430, height: 500), rotate: 11, alpha: 0.45, lines: false)
card(NSRect(x: 280, y: 250, width: 430, height: 500), rotate: -4, alpha: 0.7, lines: false)
card(NSRect(x: 297, y: 232, width: 430, height: 500), rotate: 0, alpha: 1, lines: true)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
