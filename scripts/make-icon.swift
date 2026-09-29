import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Draw into an explicit opaque bitmap so this also works without an AppKit window.
let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: size * 4, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 0.10, green: 0.31, blue: 0.25, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.setStrokeColor(CGColor(red: 0.87, green: 0.95, blue: 0.82, alpha: 1))
context.setLineWidth(48)
context.setLineCap(.round)
context.setLineJoin(.round)
for (x, y, dx, dy) in [(250.0, 250.0, 1.0, 1.0), (774, 250, -1, 1), (250, 774, 1, -1), (774, 774, -1, -1)] {
    context.move(to: CGPoint(x: x + dx * 120, y: y))
    context.addLine(to: CGPoint(x: x, y: y))
    context.addLine(to: CGPoint(x: x, y: y + dy * 120))
    context.strokePath()
}
context.setLineWidth(42)
context.strokeEllipse(in: CGRect(x: 367, y: 367, width: 290, height: 290))
context.setFillColor(CGColor(gray: 1, alpha: 1))
context.fillEllipse(in: CGRect(x: 463, y: 463, width: 98, height: 98))
let image = context.makeImage()!
let url = URL(fileURLWithPath: "JiuJing/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
precondition(CGImageDestinationFinalize(destination), "Unable to write App icon")
// Catch the blank/black output regression before it reaches the asset catalog.
let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
let center = (512 * size + 512) * 4
precondition(bytes[1] > bytes[0] && bytes[center] > 240, "Icon pixels were not rendered")
