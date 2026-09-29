import AppKit
let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        // Draw into an exact pixel bitmap; NSImage.lockFocus would render at the screen's backing scale.
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                                      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let side = CGFloat(pixels), inset = side * 0.08
        let rect = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
        let shape = NSBezierPath(roundedRect: rect, xRadius: side * 0.21, yRadius: side * 0.21)
        NSGradient(starting: NSColor(calibratedRed: 0.30, green: 0.53, blue: 1, alpha: 1), ending: NSColor(calibratedRed: 0.19, green: 0.27, blue: 0.78, alpha: 1))!.draw(in: shape, angle: -70)
        NSColor.white.setFill()
        let heights: [CGFloat] = [0.18, 0.34, 0.52, 0.28, 0.40]
        for (index, height) in heights.enumerated() {
            let width = side * 0.061, h = side * height
            NSBezierPath(roundedRect: NSRect(x: side * 0.257 + CGFloat(index) * side * 0.106, y: (side - h) / 2, width: width, height: h), xRadius: width / 2, yRadius: width / 2).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination).appendingPathComponent(filename))
    }
}
