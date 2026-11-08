import AppKit

// Renders AppIcon.icns from the master artwork. Usage: swift make_icon.swift <master.png> <output.icns>
guard CommandLine.arguments.count > 2,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil),
      let master = CGImageSourceCreateImageAtIndex(source, 0, nil) else { exit(1) }
let out = CommandLine.arguments[2]
let iconset = NSTemporaryDirectory() + "AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(master, in: CGRect(x: 0, y: 0, width: px, height: px))
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
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
