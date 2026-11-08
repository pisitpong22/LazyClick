import ApplicationServices
import AppKit
import CoreGraphics
import ServiceManagement
import LazyClickCore

/// Click feedback using the sounds macOS ships in /System/Library/Sounds.
enum ClickSound {
    static let names = ["None", "Tink", "Pop", "Morse", "Purr", "Bottle", "Frog"]

    /// Main thread only. "None" has no matching sound, so it stays silent.
    static func play() {
        guard let sound = NSSound(named: Preferences.string(Preferences.Key.clickSound)) else { return }
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
