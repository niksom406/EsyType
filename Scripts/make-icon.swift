// Draws the provisional EsyType app icon and writes Resources/AppIcon.icns.
// Usage: swift Scripts/make-icon.swift   (run from the project root)
// Provisional artwork: replace once EsyAI supplies master logo files.
import AppKit

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels) / 1024 // drawn on Apple's 1024 icon grid: 824 pt body, 100 pt margin

    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: NSColor(white: 0.12, alpha: 1), ending: NSColor(white: 0.02, alpha: 1))!.draw(in: squircle, angle: -90)
    NSColor(white: 1, alpha: 0.10).setStroke()
    squircle.lineWidth = 3 * s
    squircle.stroke()

    // Waveform bars, blue (top) to amber (bottom) across the whole wave height.
    let heights: [CGFloat] = [0.22, 0.42, 0.66, 0.88, 1.0, 0.8, 0.58, 0.38]
    let barWidth = 40 * s, gap = 30 * s, maxHeight = 460 * s, midY = 512 * s
    let gradient = NSGradient(colors: [NSColor(srgbRed: 0x28 / 255, green: 0x79 / 255, blue: 0xAB / 255, alpha: 1),
                                       NSColor(srgbRed: 0x9A / 255, green: 0x98 / 255, blue: 0x8F / 255, alpha: 1),
                                       NSColor(srgbRed: 0xDB / 255, green: 0xAE / 255, blue: 0x7E / 255, alpha: 1)])!
    let bars = NSBezierPath()
    var x = 221 * s // centres bars + cursor (582 pt wide) on the grid
    for h in heights {
        let height = h * maxHeight
        bars.append(NSBezierPath(roundedRect: NSRect(x: x, y: midY - height / 2, width: barWidth, height: height),
                                 xRadius: barWidth / 2, yRadius: barWidth / 2))
        x += barWidth + gap
    }
    NSGraphicsContext.saveGraphicsState()
    bars.addClip()
    gradient.draw(in: NSRect(x: 0, y: midY - maxHeight / 2, width: CGFloat(pixels), height: maxHeight), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // The text cursor: voice becomes typing.
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: midY - 210 * s, width: 22 * s, height: 420 * s),
                 xRadius: 11 * s, yRadius: 11 * s).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        let png = drawIcon(pixels: size * scale).representation(using: .png, properties: [:])!
        try! png.write(to: iconset.appendingPathComponent(name))
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
precondition(iconutil.terminationStatus == 0, "iconutil failed")
print("Wrote Resources/AppIcon.icns")
