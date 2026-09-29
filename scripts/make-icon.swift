import AppKit

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
NSColor(srgbRed: 0.10, green: 0.31, blue: 0.25, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
NSColor(srgbRed: 0.87, green: 0.95, blue: 0.82, alpha: 1).setStroke()
for (x, y, dx, dy) in [(250.0, 250.0, 1.0, 1.0), (774, 250, -1, 1), (250, 774, 1, -1), (774, 774, -1, -1)] {
    let p = NSBezierPath()
    p.lineWidth = 48; p.lineCapStyle = .round; p.lineJoinStyle = .round
    p.move(to: NSPoint(x: x + dx * 120, y: y))
    p.line(to: NSPoint(x: x, y: y))
    p.line(to: NSPoint(x: x, y: y + dy * 120))
    p.stroke()
}
let lens = NSBezierPath(ovalIn: NSRect(x: 367, y: 367, width: 290, height: 290))
lens.lineWidth = 42; lens.stroke()
NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: 463, y: 463, width: 98, height: 98)).fill()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
let opaque = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: opaque)
bitmap.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
try opaque.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "JiuJing/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
