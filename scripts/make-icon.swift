import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Resize the approved artwork rather than redrawing a different brand mark.
let sourceURL = URL(fileURLWithPath: "docs/brand/jiujing-logo.png")
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Unable to read docs/brand/jiujing-logo.png; run from the project root")
}
precondition(artwork.width == artwork.height, "The brand artwork must be square")
let space = CGColorSpace(name: CGColorSpace.sRGB)!
for (size, opaque, path) in [
    (1024, true, "JiuJing/Assets.xcassets/AppIcon.appiconset/AppIcon.png"),
    (256, false, "JiuJing/Assets.xcassets/BrandLogo.imageset/BrandLogo.png")
] {
    // Preserve the supplied rounded artwork in-app; App Store icons must be opaque.
    let alpha: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: size * 4, space: space, bitmapInfo: alpha.rawValue)!
    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    if opaque {
        // Match the supplied artwork's #0F3D3E background to avoid corner seams.
        context.setFillColor(CGColor(colorSpace: space, components: [15.0 / 255, 61.0 / 255, 62.0 / 255, 1])!)
        context.fill(bounds)
    }
    context.interpolationQuality = .high
    context.draw(artwork, in: bounds)
    // Catch blank output before writing the asset catalog.
    let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
    let redValues = stride(from: 0, to: size * size * 4, by: 4)
        .filter { opaque || bytes[$0 + 3] == 255 }.map { bytes[$0] }
    precondition(Int(redValues.max() ?? 0) - Int(redValues.min() ?? 0) > 32, "Logo pixels were not rendered")
    let image = context.makeImage()!
    let url = URL(fileURLWithPath: path)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination), "Unable to write \(path)")
    print("Generated \(path) (\(size) × \(size))")
}
