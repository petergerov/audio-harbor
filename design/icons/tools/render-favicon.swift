import AppKit

// render-favicon <in.png> <px> <out.png> [<px> <out.png> ...]
//
// For masters whose dark tile sits on a light, opaque background (Icon_favorite.png).
// The light corners are flood-filled from the four image corners and made transparent;
// the anti-aliased rim keeps a partial alpha (dark tile over white: alpha = 1 - brightness).
// Then the image is scaled to each requested size.
let a = CommandLine.arguments
guard a.count >= 4, a.count % 2 == 0,
      let data = FileManager.default.contents(atPath: a[1]),
      let src = NSBitmapImageRep(data: data), let cg = src.cgImage else {
    FileHandle.standardError.write(Data("render-favicon: bad arguments\n".utf8)); exit(2)
}
let w = cg.width, h = cg.height

// Straight RGBA copy of the master.
var px = [UInt8](repeating: 0, count: w * h * 4)
guard let ctx = CGContext(
    data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(3) }
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

func darkest(_ i: Int) -> Int { Int(min(px[i * 4], px[i * 4 + 1], px[i * 4 + 2])) }

// Flood fill the light background from the corners (gold has a low blue channel, so it never qualifies).
var background = [Bool](repeating: false, count: w * h)
var stack = [0, w - 1, (h - 1) * w, h * w - 1]
while let i = stack.popLast() {
    guard !background[i], darkest(i) > 128 else { continue }
    background[i] = true
    let x = i % w, y = i / w
    if x > 0 { stack.append(i - 1) }
    if x < w - 1 { stack.append(i + 1) }
    if y > 0 { stack.append(i - w) }
    if y < h - 1 { stack.append(i + w) }
}

// Background and its one-pixel rim: black with alpha from brightness.
for i in 0..<(w * h) {
    let x = i % w, y = i / w
    let rim = !background[i] && (
        (x > 0 && background[i - 1]) || (x < w - 1 && background[i + 1]) ||
        (y > 0 && background[i - w]) || (y < h - 1 && background[i + w]))
    guard background[i] || rim else { continue }
    let alpha = UInt8(max(0, min(255, 255 - darkest(i))))
    px[i * 4] = 0; px[i * 4 + 1] = 0; px[i * 4 + 2] = 0; px[i * 4 + 3] = alpha
}
guard let cut = ctx.makeImage() else { exit(4) }

for k in stride(from: 2, to: a.count, by: 2) {
    guard let size = Int(a[k]) else { exit(2) }
    guard let out = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { exit(5) }
    out.interpolationQuality = .high
    out.draw(cut, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let image = out.makeImage(),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { exit(6) }
    try png.write(to: URL(fileURLWithPath: a[k + 1]))
}
