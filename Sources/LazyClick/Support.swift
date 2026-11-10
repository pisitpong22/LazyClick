import ApplicationServices
import AppKit
import CoreGraphics
import ServiceManagement
import LazyClickCore

/// Click feedback: synthesized mouse clicks, plus the sounds macOS ships in /System/Library/Sounds.
enum ClickSound {
    private static let synthesized = ClickSynth.voices.reduce(into: [String: NSSound]()) {
        $0[$1.name] = NSSound(data: ClickSynth.wav($1))
    }
    /// "Magic Mouse" is Contents/Resources/Magic Mouse.wav, which `NSSound(named:)` finds by file name.
    static let names = ["None", "Magic Mouse"] + ClickSynth.voices.map(\.name) + ["Tink", "Pop", "Morse", "Purr", "Bottle", "Frog"]

    static var isOn: Bool { Preferences.clickSound != "None" }

    /// Main thread only. Plays the restored sound as confirmation when turning on.
    static func toggle() {
        Preferences.clickSound = isOn ? "None" : Preferences.string(Preferences.Key.lastClickSound)
        play()
    }

    /// Main thread only. "None" has no matching sound, so it stays silent.
    static func play() {
        let name = Preferences.clickSound
        guard let sound = synthesized[name] ?? NSSound(named: name) else { return }
        sound.stop() // play() is ignored while already playing, which would mute fast double taps
        sound.volume = Float(Preferences.double(Preferences.Key.clickVolume))
        sound.play()
    }
}

enum Permission {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system Accessibility prompt (and adds the app to the list, unchecked). Never changes anything itself.
    static func request() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    @discardableResult
    static func set(_ on: Bool) -> Error? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error
        }
    }
}

/// Single-shot timer for drag lock. Idle unless a drag-lock window is open.
final class OneShotTimer: DragLockTimer {
    private var source: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "lazyclick.draglock", qos: .userInteractive)

    func schedule(after seconds: Double, _ fire: @escaping () -> Void) {
        cancel()
        let s = DispatchSource.makeTimerSource(queue: queue)
        s.schedule(deadline: .now() + seconds)
        s.setEventHandler { fire() }
        source = s
        s.resume()
    }

    func cancel() {
        source?.cancel()
        source = nil
    }
}

enum CursorState {
    /// Current pointer location in global display coordinates (same space CGEvent uses).
    static func location() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

    /// A physical button is down (the app's own synthetic button is filtered out by the controller).
    static func physicalButtonDown() -> Bool {
        let s = CGEventSourceStateID.combinedSessionState
        return CGEventSource.buttonState(s, button: .left)
            || CGEventSource.buttonState(s, button: .right)
            || CGEventSource.buttonState(s, button: .center)
    }

    static func regionSelecting() -> Bool {
        GestureEngine.regionSelecting(windows: CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? [])
    }

    static func overScreenshotThumbnail(_ point: CGPoint) -> Bool {
        GestureEngine.overScreenshotThumbnail(point, windows: CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? [])
    }
}


/// Battery level of the paired Magic Mouse, read from the IO registry (no Bluetooth permission needed).
enum MouseBattery {
    /// Calls `completion` on the main queue with 0...100, or nil if no Magic Mouse reports a level.
    static func read(_ completion: @escaping (Int?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
            p.arguments = ["-r", "-k", "BatteryPercent", "-l"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            var text = ""
            if (try? p.run()) != nil {
                text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                p.waitUntilExit()
            }
            var percent: Int?
            // ProductID 617 = Magic Mouse 2, 781 = Magic Mouse (1st gen)
            for block in text.components(separatedBy: "+-o ") where block.contains("\"ProductID\" = 617") || block.contains("\"ProductID\" = 781") {
                if let r = block.range(of: #""BatteryPercent" = (\d+)"#, options: .regularExpression) {
                    percent = Int(block[r].split(separator: "=").last?.trimmingCharacters(in: .whitespaces) ?? "")
                    break
                }
            }
            DispatchQueue.main.async { completion(percent) }
        }
    }
}

/// Opens a mail draft with version info filled in, so feedback arrives with what we need to debug.
enum Feedback {
    static func send() {
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?"))"
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = "madeforme.apps@gmail.com"
        c.queryItems = [
            URLQueryItem(name: "subject", value: "LazyClick Feedback"),
            URLQueryItem(name: "body", value: "\n\n---\nLazyClick \(version)\nmacOS \(ProcessInfo.processInfo.operatingSystemVersionString)\nStyle: \(Preferences.style)"),
        ]
        if let url = c.url { NSWorkspace.shared.open(url) }
    }
}
