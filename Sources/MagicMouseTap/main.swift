import AppKit
import MagicMouseTapCore

// `MagicMouseTap --probe [seconds]` prints raw frames from the Magic Mouse for hardware verification.
// It never posts events.
if CommandLine.arguments.contains("--probe") {
    runProbe()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
