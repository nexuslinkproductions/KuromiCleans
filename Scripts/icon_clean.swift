import Foundation
import CoreGraphics
import ImageIO

// icon_clean.swift: strip the background from an app icon and scale the
// character up in the frame.
//
// Usage: swift Scripts/icon_clean.swift <input.png> <output.png> [scale]
//
// Background removal is a flood fill from the image borders: only pixels
// reachable from the edge that are close to the corner color become
// transparent, so the character's own dark pixels stay intact. If the input
// already has a transparent background, removal is skipped.

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: swift icon_clean.swift <input.png> <output.png> [scale]\n".utf8))
    exit(2)
}
let inputPath = args[1]
let outputPath = args[2]
let scale = args.count > 3 ? (Double(args[3]) ?? 1.075) : 1.075

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: inputPath) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    FileHandle.standardError.write(Data("cannot load \(inputPath)\n".utf8))
    exit(1)
}

let w = img.width
let h = img.height
let bpr = w * 4
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
let px = ctx.data!.assumingMemoryBound(to: UInt8.self)

func pixel(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
    let i = y * bpr + x * 4
    return (px[i], px[i + 1], px[i + 2], px[i + 3])
}

// ---- diagnostics ----
print("size: \(w)x\(h)")
let corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
for (cx, cy) in corners {
    let p = pixel(cx, cy)
    print("corner (\(cx),\(cy)): rgba(\(p.r),\(p.g),\(p.b),\(p.a))")
}

var minX = w, minY = h, maxX = -1, maxY = -1
var opaque = 0
for y in 0..<h {
    for x in 0..<w where pixel(x, y).a > 16 {
        opaque += 1
        if x < minX { minX = x }
        if x > maxX { maxX = x }
        if y < minY { minY = y }
        if y > maxY { maxY = y }
    }
}
print("opaque px: \(opaque)")
if maxX >= 0 {
    let fillW = Double(maxX - minX + 1) / Double(w) * 100
    let fillH = Double(maxY - minY + 1) / Double(h) * 100
    print("content bbox: x \(minX)...\(maxX), y \(minY)...\(maxY)  (fills \(String(format: "%.1f", fillW))% x \(String(format: "%.1f", fillH))% of canvas)")
}

// ---- background removal (border flood fill) ----
let cornerOpaque = corners.filter { pixel($0.0, $0.1).a > 32 }.count
if cornerOpaque >= 2 {
    var rSum = 0, gSum = 0, bSum = 0
    for (cx, cy) in corners {
        let p = pixel(cx, cy)
        rSum += Int(p.r); gSum += Int(p.g); bSum += Int(p.b)
    }
    let bgR = UInt8(rSum / 4), bgG = UInt8(gSum / 4), bgB = UInt8(bSum / 4)
    let tol = 48

    func similar(_ x: Int, _ y: Int) -> Bool {
        let p = pixel(x, y)
        guard p.a > 32 else { return false }
        return abs(Int(p.r) - Int(bgR)) <= tol && abs(Int(p.g) - Int(bgG)) <= tol && abs(Int(p.b) - Int(bgB)) <= tol
    }

    var visited = [Bool](repeating: false, count: w * h)
    var queue: [(Int, Int)] = []
    for x in 0..<w {
        if similar(x, 0) { queue.append((x, 0)); visited[x] = true }
        if similar(x, h - 1) { queue.append((x, h - 1)); visited[(h - 1) * w + x] = true }
    }
    for y in 0..<h {
        if similar(0, y) { queue.append((0, y)); visited[y * w] = true }
        if similar(w - 1, y) { queue.append((w - 1, y)); visited[y * w + w - 1] = true }
    }

    var removed = 0
    while !queue.isEmpty {
        let (x, y) = queue.removeLast()
        px[y * bpr + x * 4 + 3] = 0
        removed += 1
        for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
            let nx = x + dx, ny = y + dy
            guard nx >= 0, ny >= 0, nx < w, ny < h, !visited[ny * w + nx], similar(nx, ny) else { continue }
            visited[ny * w + nx] = true
            queue.append((nx, ny))
        }
    }
    print("background removed: \(removed) px (flood fill from borders, tolerance \(tol), bg rgb(\(bgR),\(bgG),\(bgB)))")
} else {
    print("background already transparent; no removal needed")
}

// ---- rebuild CGImage from processed pixels ----
let provider = CGDataProvider(data: Data(bytes: px, count: bpr * h) as CFData)!
let processed = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bpr,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!

// ---- scale character up, centered ----
let outW = 1024, outH = 1024
let ctxOut = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: outW * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let side = Double(outW) * scale
let rect = CGRect(x: (Double(outW) - side) / 2, y: (Double(outH) - side) / 2, width: side, height: side)
ctxOut.interpolationQuality = .high
ctxOut.draw(processed, in: rect)

let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outputPath) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctxOut.makeImage()!, nil)
guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write(Data("failed to write \(outputPath)\n".utf8))
    exit(1)
}
print("wrote \(outputPath) (\(outW)x\(outH), scale \(scale))")
