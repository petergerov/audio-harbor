import AppKit

// compose-iphone <raw 1320x2868.png> <eyebrow> <headline> <out 1320x2868.png>
//
// iPhone App Store screenshot (6.9″): the app's dark chassis as a background, an amber eyebrow
// and a serif headline on top, the simulator capture below as a rounded screen with a hairline
// bezel and a soft shadow. Same look as compose.swift for the Mac.
// Run from marketing/app-store: `./build-iphone.sh`.
let a = CommandLine.arguments
guard a.count == 5, let screen = NSImage(contentsOfFile: a[1]) else {
    FileHandle.standardError.write(Data("compose-iphone: bad arguments\n".utf8)); exit(2)
}
// A literal "\\n" in the headline forces a line break.
let eyebrow = a[2], headline = a[3].replacingOccurrences(of: "\\n", with: "\n")

let width = 1320, height = 2868
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
    NSGradient(colors: [amber.withAlphaComponent(0.18), amber.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: canvas.width / 2, y: canvas.height + 80), radius: 0,
              toCenter: NSPoint(x: canvas.width / 2, y: canvas.height + 80), radius: 1100, options: [])
    NSColor(calibratedRed: 0.30, green: 0.20, blue: 0.12, alpha: 1).setFill()
    NSRect(x: 0, y: canvas.height - 8, width: canvas.width, height: 8).fill()

    let centred = NSMutableParagraphStyle()
    centred.alignment = .center
    centred.lineSpacing = 6

    let eyebrowText = NSAttributedString(string: eyebrow.uppercased(), attributes: [
        .font: font(40, weight: .semibold, design: .rounded),
        .foregroundColor: amber,
        .kern: 8.0,
        .paragraphStyle: centred,
    ])
    eyebrowText.draw(in: NSRect(x: 0, y: canvas.height - 230, width: canvas.width, height: 56))
    let headlineText = NSAttributedString(string: headline, attributes: [
        .font: font(92, weight: .medium, design: .serif),
        .foregroundColor: ivory,
        .paragraphStyle: centred,
    ])
    headlineText.draw(in: NSRect(x: 90, y: canvas.height - 520, width: canvas.width - 180, height: 270))

    // The screen, scaled to fit under the text: rounded like the device, hairline bezel, shadow.
    let screenHeight: CGFloat = 2180
    let screenWidth = screenHeight * screen.size.width / screen.size.height
    let screenRect = NSRect(x: (canvas.width - screenWidth) / 2, y: 110, width: screenWidth, height: screenHeight)
    let radius = screenWidth * 0.125
    let bezel = screenRect.insetBy(dx: -14, dy: -14)
    let bezelPath = NSBezierPath(roundedRect: bezel, xRadius: radius + 14, yRadius: radius + 14)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.65)
    shadow.shadowBlurRadius = 80
    shadow.shadowOffset = NSSize(width: 0, height: -30)
    shadow.set()
    NSColor(calibratedRed: 0.11, green: 0.10, blue: 0.09, alpha: 1).setFill()
    bezelPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSColor(calibratedRed: 0.32, green: 0.27, blue: 0.21, alpha: 1).setStroke()
    bezelPath.lineWidth = 3
    bezelPath.stroke()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: screenRect, xRadius: radius, yRadius: radius).addClip()
    screen.draw(in: screenRect, from: .zero, operation: .sourceOver, fraction: 1)
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
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: path))
}

write(render(), a[4])
print(a[4])
