import AppKit

// render-png <in.png> <out.png> <px> <bleed|mac|web>
//
// For raster masters that bring their own rounded tile: either framed in gold on a dark,
// uneven background (icon_no_text.png), or a tile on a plain background whose four corners
// share one colour — white (Icon_favorite.png) or black (icon_no_text_2d.png). The tile is
// found by brightness — the gold frame, or else everything that differs from the plain
// background —, its corner radius read off the 45° diagonal; everything outside is dropped.
//   mac   — tile clipped to its own rounded shape, on Apple's grid (824 of 1024), shadow, transparent rest
//   web   — tile clipped to its rounded shape, full size, transparent corners (homepage, favicon)
//   bleed — tile full-bleed, opaque, no alpha (iOS masks the corners itself)
let a = CommandLine.arguments
guard a.count >= 5, let px = Int(a[3]),
      let data = FileManager.default.contents(atPath: a[1]),
      let src = NSBitmapImageRep(data: data), let cg = src.cgImage else {
    FileHandle.standardError.write(Data("render-png: bad arguments\n".utf8)); exit(2)
}
let mode = a[4]
let s = CGFloat(px)

func rgb(_ x: Int, _ y: Int) -> (CGFloat, CGFloat, CGFloat) {
    guard let c = src.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return (0, 0, 0) }
    return (c.redComponent, c.greenComponent, c.blueComponent)
}
func distance(_ p: (CGFloat, CGFloat, CGFloat), _ q: (CGFloat, CGFloat, CGFloat)) -> CGFloat {
    max(abs(p.0 - q.0), abs(p.1 - q.1), abs(p.2 - q.2))
}
func isGold(_ x: Int, _ y: Int) -> Bool {
    let c = rgb(x, y)
    return c.0 > 0.72 && c.1 > 0.5
}

// Four corners of one colour mean a plain background and a tile without a gold frame.
let lastX = src.pixelsWide - 1, lastY = src.pixelsHigh - 1
let ground = rgb(0, 0)
let plainGround = [rgb(lastX, 0), rgb(0, lastY), rgb(lastX, lastY)].allSatisfy { distance($0, ground) < 0.01 }

// Tile bounds: outermost gold pixels (the faint glow outside stays below the threshold),
// or on a plain background the outermost pixels that differ from it.
func isTile(_ x: Int, _ y: Int) -> Bool { plainGround ? distance(rgb(x, y), ground) > 0.06 : isGold(x, y) }
var left = src.pixelsWide, right = 0, top = src.pixelsHigh, bottom = 0
for y in 0..<src.pixelsHigh {
    for x in 0..<src.pixelsWide where isTile(x, y) {
        left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y)
    }
}
guard right > left, bottom > top else { exit(3) }
var diagonal = 0
while diagonal < 600 && !isTile(left + diagonal, top + diagonal) { diagonal += 1 }
let frameW = CGFloat(right - left + 1), frameH = CGFloat(bottom - top + 1)
let radiusFraction = CGFloat(diagonal) / (1 - 1 / sqrt(2)) / frameW

// On a plain background the edge pixels are part background; step in a hair to drop that fringe.
let edge = plainGround ? max(2, Int(frameW * 0.004)) : 0
// CG's origin is bottom-left; the scan above ran top-down.
let crop = CGRect(x: left + edge, y: top + edge, width: Int(frameW) - 2 * edge, height: Int(frameH) - 2 * edge)
guard let tile = cg.cropping(to: crop) else { exit(4) }

func drawTile(in rect: NSRect, clip: Bool) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.saveGState()
    if clip {
        let r = rect.width * radiusFraction
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.clip()
    }
    ctx.interpolationQuality = .high
    ctx.draw(tile, in: rect)
    ctx.restoreGState()
}

let full = NSRect(x: 0, y: 0, width: s, height: s)
var out: NSBitmapImageRep?

if mode == "mac" || mode == "web" {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { exit(5) }
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.setFill()
    full.fill(using: .copy)
    if mode == "mac" {
        // Apple's macOS grid: 824 of 1024 across, centred, shadow below.
        let inset = s * 100 / 1024
        let side = s * 824 / 1024
        let rect = NSRect(x: inset, y: inset, width: side, height: side)
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -s * 10 / 1024)
        shadow.shadowBlurRadius = s * 24 / 1024
        shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.45)
        // Shadow from the tile's shape, then the tile itself on top.
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect, xRadius: side * radiusFraction, yRadius: side * radiusFraction).fill()
        NSGraphicsContext.restoreGraphicsState()
        drawTile(in: rect, clip: true)
    } else {
        drawTile(in: full, clip: true)
    }
    NSGraphicsContext.restoreGraphicsState()
    out = rep
} else {
    // iOS icons must carry no alpha channel — draw opaque, encode as RGB.
    guard let ctx = CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { exit(5) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSColor(calibratedRed: 0.039, green: 0.035, blue: 0.031, alpha: 1).setFill()
    full.fill(using: .copy)
    // A tile from a plain background keeps its rounded shape, so none of that background shows.
    drawTile(in: full, clip: plainGround)
    NSGraphicsContext.restoreGraphicsState()
    guard let image = ctx.makeImage() else { exit(6) }
    out = NSBitmapImageRep(cgImage: image)
}

guard let png = out?.representation(using: .png, properties: [:]) else { exit(7) }
try png.write(to: URL(fileURLWithPath: a[2]))
