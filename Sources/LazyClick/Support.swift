import ApplicationServices
import AppKit
import CoreGraphics
import ServiceManagement
import LazyClickCore

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
