import AppKit

// render-logo <in.png> <height px> <out.png> [<height px> <out.png> ...]
//
// For logo_homepage.png: a gold mark on a dark, textured background. The background level is
// read from the image border; each pixel is treated as gold laid over that background, so
// alpha comes from how far its brightest channel rises above it and the colour is
// un-mixed accordingly. The result is cropped to the visible logo and scaled to each
// requested height (width follows the aspect ratio).
let a = CommandLine.arguments
guard a.count >= 4, a.count % 2 == 0,
      let data = FileManager.default.contents(atPath: a[1]),
      let src = NSBitmapImageRep(data: data), let cg = src.cgImage else {
    FileHandle.standardError.write(Data("render-logo: bad arguments\n".utf8)); exit(2)
}
let w = cg.width, h = cg.height

var px = [UInt8](repeating: 0, count: w * h * 4)
guard let ctx = CGContext(
    data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(3) }
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

func brightest(_ i: Int) -> Double { Double(max(px[i * 4], px[i * 4 + 1], px[i * 4 + 2])) }

// Background level: a high percentile of the border, so texture and vignette count as background.
var border: [Double] = []
for x in 0..<w { border.append(brightest(x)); border.append(brightest((h - 1) * w + x)) }
for y in 0..<h { border.append(brightest(y * w)); border.append(brightest(y * w + w - 1)) }
border.sort()
let background = border[Int(Double(border.count - 1) * 0.98)] + 6

// Straight (unpremultiplied) RGBA with the background removed.
var out = [UInt8](repeating: 0, count: w * h * 4)
var minX = w, minY = h, maxX = -1, maxY = -1
for i in 0..<(w * h) {
    let alpha = min(max((brightest(i) - background) / (255 - background), 0), 1)
    guard alpha > 0 else { continue }
    for c in 0..<3 {
        let value = Double(px[i * 4 + c])
        let unmixed = (value - background * (1 - alpha)) / alpha
        out[i * 4 + c] = UInt8(min(max(unmixed, 0), 255))
    }
    out[i * 4 + 3] = UInt8((alpha * 255).rounded())
    if alpha > 0.04 {
        let x = i % w, y = i / w
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
}
guard maxX >= minX, maxY >= minY else {
    FileHandle.standardError.write(Data("render-logo: no logo found\n".utf8)); exit(4)
}

// Premultiply for CoreGraphics and crop with a small margin.
for i in 0..<(w * h) {
    let alpha = Int(out[i * 4 + 3])
    for c in 0..<3 { out[i * 4 + c] = UInt8(Int(out[i * 4 + c]) * alpha / 255) }
}
let margin = max(2, (maxY - minY) / 40)
let crop = CGRect(
    x: max(0, minX - margin), y: max(0, minY - margin),
    width: min(w, maxX + margin + 1) - max(0, minX - margin),
    height: min(h, maxY + margin + 1) - max(0, minY - margin)
)
guard let full = CGContext(
    data: &out, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)?.makeImage(), let cropped = full.cropping(to: crop) else { exit(5) }

var index = 2
while index + 1 < a.count {
    guard let height = Int(a[index]), height > 0 else { exit(6) }
    let width = Int((Double(cropped.width) * Double(height) / Double(cropped.height)).rounded())
    guard let scaled = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { exit(7) }
    scaled.interpolationQuality = .high
    scaled.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = scaled.makeImage(),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { exit(8) }
    try png.write(to: URL(fileURLWithPath: a[index + 1]))
    print("\(a[index + 1]): \(width)×\(height)")
    index += 2
}
