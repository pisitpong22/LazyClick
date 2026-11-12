import AppKit

// Draws the disk image window background: an arrow from the app icon to Applications and one line of help.
// Usage: swift make_dmg_background.swift <out.png> <scale>. Layout must match the icon positions in build.sh.
let size = CGSize(width: 660, height: 400)
let out = CommandLine.arguments[1]
let scale = CGFloat(Double(CommandLine.arguments[2]) ?? 1)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

NSColor.white.setFill()
NSRect(origin: .zero, size: size).fill()

// Arrow between the icons Finder places at (180, 180) and (480, 180) from the top-left; drawing is bottom-left.
let y: CGFloat = size.height - 180
let arrow = CGMutablePath()
arrow.move(to: CGPoint(x: 268, y: y))
arrow.addLine(to: CGPoint(x: 390, y: y))
arrow.move(to: CGPoint(x: 368, y: y - 22))
arrow.addLine(to: CGPoint(x: 391, y: y))
arrow.addLine(to: CGPoint(x: 368, y: y + 22))
let ctx = NSGraphicsContext.current!.cgContext
ctx.addPath(arrow.copy(strokingWithWidth: 7, lineCap: .round, lineJoin: .round, miterLimit: 10))
ctx.clip()
// Light to dark, pointing the eye toward Applications.
let gradient = CGGradient(colorsSpace: nil, colors: [NSColor(white: 0.82, alpha: 1).cgColor, NSColor(white: 0.42, alpha: 1).cgColor] as CFArray, locations: nil)!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 264, y: y), end: CGPoint(x: 396, y: y), options: [])
ctx.resetClip()

let text = "To install LazyClick, drag it to Applications." as NSString
let para = NSMutableParagraphStyle()
para.alignment = .center
text.draw(in: NSRect(x: 0, y: size.height - 348, width: size.width, height: 30), withAttributes: [
    .font: NSFont.systemFont(ofSize: 17, weight: .medium),
    .foregroundColor: NSColor(white: 0.40, alpha: 1),
    .paragraphStyle: para,
])
NSGraphicsContext.current = nil
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
