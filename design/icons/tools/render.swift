import AppKit

// render <in.svg> <out.png> <px> <bleed|mac>
let a = CommandLine.arguments
guard a.count >= 5, let px = Int(a[3]), let img = NSImage(contentsOfFile: a[1]) else {
    FileHandle.standardError.write(Data("render: bad arguments\n".utf8)); exit(2)
}
let mac = a[4] == "mac"
let s = CGFloat(px)

let full = NSRect(x: 0, y: 0, width: s, height: s)
var out: NSBitmapImageRep?

if mac {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { exit(3) }
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    full.fill(using: .copy)
    // Apple's macOS grid: 824 of 1024 across, centred, shadow below.
    let inset = s * 100 / 1024
    let side = s * 824 / 1024
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -s * 10 / 1024)
    shadow.shadowBlurRadius = s * 24 / 1024
    shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.45)
    shadow.set()
    img.draw(in: NSRect(x: inset, y: inset, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    out = rep
} else {
    // iOS icons must carry no alpha channel, and CoreGraphics has no 24-bit
    // context — draw opaque with the alpha byte ignored, then encode as RGB.
    guard let ctx = CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { exit(3) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor(calibratedRed: 0.039, green: 0.035, blue: 0.031, alpha: 1).setFill()
    full.fill(using: .copy)
    img.draw(in: full)
    NSGraphicsContext.restoreGraphicsState()
    guard let cg = ctx.makeImage() else { exit(4) }
    out = NSBitmapImageRep(cgImage: cg)
}

guard let data = out?.representation(using: .png, properties: [:]) else { exit(5) }
try data.write(to: URL(fileURLWithPath: a[2]))
