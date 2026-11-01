import Foundation
import LazyClickCore

/// Hardware verification aid. Prints what MultitouchSupport reports; never posts events.
func runProbe() {
    let args = CommandLine.arguments
    var seconds = 8.0
    if let i = args.firstIndex(of: "--probe"), i + 1 < args.count, let s = Double(args[i + 1]) { seconds = s }

    let adapter = MultitouchAdapter()
    print("availability: \(adapter.availability)")
    print("MTTouch stride assumed: \(MTLayout.stride) bytes")
    adapter.describeDevices().forEach { print($0) }

    var scratch: [Contact] = []
    var frames = 0, implausible = 0, maxFingers = 0
    var lastPrint = 0.0
    MultitouchAdapter.frameHandler = { base, count, ts in
        frames += 1
        let r = RawFrameParser.parse(base, count: count, into: &scratch)
        if r == .implausible { implausible += 1 }
        maxFingers = max(maxFingers, scratch.count)
        if ts - lastPrint > 0.1 || count == 0 {
            lastPrint = ts
            let desc = scratch.map { String(format: "#%d(%.3f,%.3f)", $0.id, $0.x, $0.y) }.joined(separator: " ")
            print(String(format: "t=%.3f raw=%d down=%d ", ts, count, scratch.count) + desc + (r == .ok ? "" : " IMPLAUSIBLE"))
        }
    }
    adapter.startMonitoring()
    print("listening \(Int(seconds))s — touch the Magic Mouse…")
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    adapter.stopMonitoring()
    print("frames=\(frames) implausible=\(implausible) maxSimultaneousDown=\(maxFingers)")
}
