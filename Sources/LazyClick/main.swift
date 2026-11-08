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
    if let i = CommandLine.arguments.firstIndex(of: "--demo"), i + 1 < CommandLine.arguments.count,
       let kind = DemoKind.allCases.first(where: { String(describing: $0) == CommandLine.arguments[i + 1] }) {
        controller.previewDemo(kind)
    }
    preview.run()
}

// `LazyClick --show-onboarding [--page <n>]` opens only the first-run window for UI checks.
if CommandLine.arguments.contains("--show-onboarding") {
    let preview = NSApplication.shared
    preview.setActivationPolicy(.regular)
    let controller = OnboardingWindowController(onClose: { exit(0) })
    controller.present()
    if let i = CommandLine.arguments.firstIndex(of: "--page"), i + 1 < CommandLine.arguments.count,
       let n = Int(CommandLine.arguments[i + 1]) {
        controller.showPage(n)
    }
    preview.run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
