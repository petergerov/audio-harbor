import AppKit

// compose <raw window.png> <eyebrow> <headline> <out 2560x1600.png> <out 1280x800.png>
//
// Mac App Store screenshot: the app's dark chassis as a background, an amber eyebrow and a
// serif headline on top, the window capture centred below with a soft shadow.
// Run from marketing/app-store: `./build.sh` (renders every screenshot in screenshots.txt).
let a = CommandLine.arguments
guard a.count == 6,
      let window = NSImage(contentsOfFile: a[1]),
      let windowRep = window.representations.first else {
    FileHandle.standardError.write(Data("compose: bad arguments\n".utf8)); exit(2)
}
let eyebrow = a[2], headline = a[3]

let width = 2560, height = 1600
let canvas = NSSize(width: width, height: height)

let amber = NSColor(calibratedRed: 0.98, green: 0.72, blue: 0.22, alpha: 1)
let ivory = NSColor(calibratedRed: 0.94, green: 0.91, blue: 0.85, alpha: 1)

func font(_ size: CGFloat, weight: NSFont.Weight, design: NSFontDescriptor.SystemDesign) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

func render() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = canvas
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let full = NSRect(origin: .zero, size: canvas)

    // Chassis: warm near-black, lighter at the top, a faint amber bloom behind the headline.
    NSGradient(colors: [
        NSColor(calibratedRed: 0.105, green: 0.09, blue: 0.075, alpha: 1),
        NSColor(calibratedRed: 0.045, green: 0.04, blue: 0.035, alpha: 1),
    ])!.draw(in: full, angle: -90)
    NSGradient(colors: [amber.withAlphaComponent(0.16), amber.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: canvas.width / 2, y: canvas.height + 120), radius: 0,
              toCenter: NSPoint(x: canvas.width / 2, y: canvas.height + 120), radius: 1150, options: [])
    // A walnut hairline along the top edge, like the app's chassis.
    NSColor(calibratedRed: 0.30, green: 0.20, blue: 0.12, alpha: 1).setFill()
    NSRect(x: 0, y: canvas.height - 6, width: canvas.width, height: 6).fill()

    let centred = NSMutableParagraphStyle()
    centred.alignment = .center

    // Eyebrow and headline.
    let eyebrowText = NSAttributedString(string: eyebrow.uppercased(), attributes: [
        .font: font(30, weight: .semibold, design: .rounded),
        .foregroundColor: amber,
        .kern: 7.0,
        .paragraphStyle: centred,
    ])
    eyebrowText.draw(in: NSRect(x: 0, y: canvas.height - 150, width: canvas.width, height: 44))
    let headlineText = NSAttributedString(string: headline, attributes: [
        .font: font(76, weight: .medium, design: .serif),
        .foregroundColor: ivory,
        .paragraphStyle: centred,
    ])
    headlineText.draw(in: NSRect(x: 120, y: canvas.height - 268, width: canvas.width - 240, height: 104))

    // The window, scaled to fit under the text, with a deep soft shadow.
    let aspect = CGFloat(windowRep.pixelsWide) / CGFloat(windowRep.pixelsHigh)
    let windowHeight: CGFloat = 1170
    let windowWidth = windowHeight * aspect
    let windowRect = NSRect(x: (canvas.width - windowWidth) / 2, y: 90, width: windowWidth, height: windowHeight)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
    shadow.shadowBlurRadius = 70
    shadow.shadowOffset = NSSize(width: 0, height: -24)
    shadow.set()
    window.draw(in: windowRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, _ path: String) {
    // App Store Connect rejects alpha in screenshots: flatten to opaque RGB.
    let cg = rep.cgImage!
    let ctx = CGContext(
        data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    ctx.interpolationQuality = .high
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: path))
}

func scaled(_ rep: NSBitmapImageRep, to size: NSSize) -> NSBitmapImageRep {
    let ctx = CGContext(
        data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.interpolationQuality = .high
    ctx.draw(rep.cgImage!, in: CGRect(origin: .zero, size: size))
    return NSBitmapImageRep(cgImage: ctx.makeImage()!)
}

let full = render()
write(full, a[4])
write(scaled(full, to: NSSize(width: 1280, height: 800)), a[5])
print("\(a[4]), \(a[5])")
