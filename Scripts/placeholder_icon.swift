// Generates a placeholder app icon: rounded pink square with a white folder.
// Used only when Assets/AppIcon.png is not provided. Writes dist/placeholder.png.

import CoreGraphics
import Foundation
import ImageIO

let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()

guard let ctx = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Could not create drawing context")
}

func fillRounded(_ rect: CGRect, radius: CGFloat, color: CGColor) {
    ctx.setFillColor(color)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()
}

// Pink background, #FF6B9D.
let pink = CGColor(red: 1.0, green: 0x6B / 255.0, blue: 0x9D / 255.0, alpha: 1.0)
let white = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)

fillRounded(CGRect(x: 0, y: 0, width: 1024, height: 1024), radius: 180, color: pink)
// Folder tab (drawn first, body covers its lower edge).
fillRounded(CGRect(x: 352, y: 610, width: 320, height: 140), radius: 28, color: white)
// Folder body.
fillRounded(CGRect(x: 150, y: 380, width: 724, height: 330), radius: 44, color: white)

guard let image = ctx.makeImage() else {
    fatalError("Could not render image")
}

let fm = FileManager.default
let outDir = URL(fileURLWithPath: "dist")
try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)
let outURL = outDir.appendingPathComponent("placeholder.png")

guard let destination = CGImageDestinationCreateWithURL(outURL as CFURL, "public.png" as CFString, 1, nil) else {
    fatalError("Could not create image destination")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("Could not write PNG")
}

print("Wrote \(outURL.path)")
