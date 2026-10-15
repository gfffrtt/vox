// Renders Resources/DMGBackground.tiff: the installer window background (640×400pt, 1x + 2x).
// The icon positions here must match the ones make-dmg.sh gives Finder (Vox at 160, Applications at 480).
// Usage: swift scripts/make-dmg-background.swift <output.tiff>
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/DMGBackground.tiff"
let size = NSSize(width: 640, height: 400)
let iconY: CGFloat = 190  // icon centers, measured from the top like Finder does

/// Converts a top-left based y (Finder's coordinates) to AppKit's bottom-left based y.
func y(_ top: CGFloat) -> CGFloat { size.height - top }

func drawCentered(_ text: String, font: NSFont, color: NSColor, top: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let s = (text as NSString).size(withAttributes: attributes)
    (text as NSString).draw(at: NSPoint(x: (size.width - s.width) / 2, y: y(top) - s.height), withAttributes: attributes)
}

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = size  // drawing happens in points; the rep maps them to pixels
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Light background so Finder's dark icon labels stay readable, with the black app icon popping.
    NSGradient(colors: [NSColor(white: 0.985, alpha: 1), NSColor(white: 0.925, alpha: 1)])!
        .draw(in: NSRect(origin: .zero, size: size), angle: -90)

    drawCentered("Drag Vox into Applications", font: .systemFont(ofSize: 17, weight: .semibold),
                 color: NSColor(white: 0.15, alpha: 1), top: 44)
    drawCentered("Push-to-talk dictation for your Mac", font: .systemFont(ofSize: 12),
                 color: NSColor(white: 0.45, alpha: 1), top: 70)

    // Arrow between the two icons.
    let arrow = NSBezierPath()
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 262, y: y(iconY)))
    arrow.line(to: NSPoint(x: 376, y: y(iconY)))
    arrow.move(to: NSPoint(x: 362, y: y(iconY) + 13))
    arrow.line(to: NSPoint(x: 378, y: y(iconY)))
    arrow.line(to: NSPoint(x: 362, y: y(iconY) - 13))
    NSColor(white: 0.62, alpha: 1).setStroke()
    arrow.stroke()

    // Divider and first-launch hint (the app isn't notarized, so Gatekeeper blocks the first open).
    NSColor(white: 0, alpha: 0.08).setFill()
    NSRect(x: 60, y: y(318), width: size.width - 120, height: 1).fill()
    drawCentered("First launch blocked? Open System Settings → Privacy & Security → Open Anyway.",
                 font: .systemFont(ofSize: 11), color: NSColor(white: 0.5, alpha: 1), top: 336)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
let one = tmp.appendingPathComponent("dmg-bg.png"), two = tmp.appendingPathComponent("dmg-bg@2x.png")
try render(scale: 1).representation(using: .png, properties: [:])!.write(to: one)
try render(scale: 2).representation(using: .png, properties: [:])!.write(to: two)

// A multi-resolution TIFF lets Finder pick the sharp version on Retina displays.
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
task.arguments = ["-cathidpicheck", one.path, two.path, "-out", output]
try task.run()
task.waitUntilExit()
exit(task.terminationStatus)
