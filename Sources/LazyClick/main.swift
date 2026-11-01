import AppKit
import LazyClickCore

// `LazyClick --probe [seconds]` prints raw frames from the Magic Mouse for hardware verification.
// It never posts events.
if CommandLine.arguments.contains("--probe") {
    runProbe()
    exit(0)
}

// `LazyClick --show-settings` opens only the settings window (no touch handling) for UI checks.
if CommandLine.arguments.contains("--show-settings") {
    Preferences.registerDefaults()
    let preview = NSApplication.shared
    preview.setActivationPolicy(.regular)
    let controller = SettingsWindowController(onChange: {}, onClose: { exit(0) })
    controller.present()
    preview.run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
