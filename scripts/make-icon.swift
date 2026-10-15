// Renders Resources/AppIcon.icns: the menu-bar waveform glyph, white on a black rounded square.
// Usage: swift scripts/make-icon.swift <output.icns>
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns"
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(pixels) / 1024
    NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)

    // macOS icon grid: an 824pt rounded square centered on a 1024pt canvas.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGradient(colors: [NSColor(white: 0.20, alpha: 1), NSColor(white: 0.04, alpha: 1)])!
        .draw(in: path, angle: -90)
    NSColor(white: 1, alpha: 0.10).setStroke()
    path.lineWidth = 4
    path.stroke()

    let config = NSImage.SymbolConfiguration(pointSize: 420, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    let symbol = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!
    let s = symbol.size
    symbol.draw(in: NSRect(x: 512 - s.width / 2, y: 512 - s.height / 2, width: s.width, height: s.height))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = factor == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try render(pixels: points * factor).write(to: iconset.appendingPathComponent(name))
    }
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output]
try task.run()
task.waitUntilExit()
exit(task.terminationStatus)
