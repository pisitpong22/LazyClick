import AppKit

// Renders AppIcon.icns from an SF Symbol. Usage: swift make_icon.swift <output.icns>
guard CommandLine.arguments.count > 1 else { exit(1) }
let out = CommandLine.arguments[1]
let iconset = NSTemporaryDirectory() + "AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let size = NSSize(width: px, height: px)
    let img = NSImage(size: size)
    img.lockFocus()
    let rect = NSRect(origin: .zero, size: size).insetBy(dx: CGFloat(px) * 0.05, dy: CGFloat(px) * 0.05)
    let path = NSBezierPath(roundedRect: rect, xRadius: CGFloat(px) * 0.22, yRadius: CGFloat(px) * 0.22)
    NSGradient(colors: [NSColor(calibratedRed: 0.20, green: 0.52, blue: 0.98, alpha: 1),
                        NSColor(calibratedRed: 0.36, green: 0.28, blue: 0.86, alpha: 1)])!.draw(in: path, angle: -90)
    let name = NSImage(systemSymbolName: "magicmouse", accessibilityDescription: nil) != nil ? "magicmouse" : "computermouse"
    if let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: CGFloat(px) * 0.55, weight: .regular)) {
        let tinted = NSImage(size: sym.size)
        tinted.lockFocus()
        sym.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        NSColor.white.set()
        NSRect(origin: .zero, size: sym.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        let r = NSRect(x: (size.width - tinted.size.width) / 2, y: (size.height - tinted.size.height) / 2,
                       width: tinted.size.width, height: tinted.size.height)
        tinted.draw(in: r)
    }
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base).png"))
    try render(base * 2).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset, "-o", out]
try p.run(); p.waitUntilExit()
exit(p.terminationStatus)
