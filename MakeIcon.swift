import AppKit
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(px) / 1024); transform.concat()
        NSColor(calibratedRed: 0.08, green: 0.18, blue: 0.22, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 36,y: 36,width: 952,height: 952), xRadius: 214,yRadius: 214).fill()
        let shades = [NSColor(calibratedRed: 59.0 / 255.0, green: 158.0 / 255.0, blue: 200.0 / 255.0, alpha: 1), NSColor(calibratedRed: 0.77, green: 0.88, blue: 0.95, alpha: 1), NSColor(calibratedRed: 0.97, green: 0.84, blue: 0.57, alpha: 1)]
        for i in 0..<3 {
            shades[i].setFill(); let x = CGFloat(210 + i*202)
            NSBezierPath(roundedRect: NSRect(x: x,y: 240,width: 158,height: 550), xRadius: 28,yRadius: 28).fill()
            NSColor(calibratedWhite: 0.10,alpha: 0.25).setFill()
            NSBezierPath(roundedRect: NSRect(x: x+24,y: 660,width: 110,height: 12), xRadius: 6,yRadius: 6).fill()
            NSBezierPath(roundedRect: NSRect(x: x+24,y: 625,width: 110,height: 12), xRadius: 6,yRadius: 6).fill()
            NSBezierPath(ovalIn: NSRect(x: x+58,y: 285,width: 42,height: 42)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
