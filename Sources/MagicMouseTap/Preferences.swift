import Foundation
import MagicMouseTapCore

/// UserDefaults-backed settings. Reads happen on demand; nothing is polled.
enum Preferences {
    private static let d = UserDefaults.standard

    enum Key {
        static let enabled = "enabled"
        static let oneFinger = "oneFingerTap"
        static let twoFinger = "twoFingerTap"
        static let threeFinger = "threeFingerTap"
        static let threeFingerDrag = "threeFingerDrag"
        static let sensitivity = "tapSensitivity"
        static let dragDistance = "dragActivationDistance"
        static let dragLock = "dragLock"
        static let dragLockTimeout = "dragLockTimeout"
        static let didPromptAccessibility = "didPromptAccessibility"
    }

    static func registerDefaults() {
        d.register(defaults: [
            Key.enabled: true,
            Key.oneFinger: true,
            Key.twoFinger: true,
            Key.threeFinger: true,
            Key.threeFingerDrag: true,
            Key.sensitivity: 0.5,
            Key.dragDistance: 6.0,
            Key.dragLock: false,
            Key.dragLockTimeout: 1.0,
        ])
    }

    static func bool(_ key: String) -> Bool { d.bool(forKey: key) }
    static func set(_ value: Bool, for key: String) { d.set(value, forKey: key) }
    static func double(_ key: String) -> Double { d.double(forKey: key) }
    static func set(_ value: Double, for key: String) { d.set(value, forKey: key) }

    static func resetAdvanced() {
        for k in [Key.sensitivity, Key.dragDistance, Key.dragLock, Key.dragLockTimeout] { d.removeObject(forKey: k) }
    }

    static func gestureConfig() -> GestureConfig {
        var c = GestureConfig()
        c.oneFingerTapEnabled = bool(Key.oneFinger)
        c.twoFingerTapEnabled = bool(Key.twoFinger)
        c.threeFingerTapEnabled = bool(Key.threeFinger)
        c.threeFingerDragEnabled = bool(Key.threeFingerDrag)
        c.tapSensitivity = min(1, max(0, double(Key.sensitivity)))
        c.dragActivationDistance = min(40, max(2, double(Key.dragDistance)))
        c.dragLockEnabled = bool(Key.dragLock)
        c.dragLockTimeout = min(5, max(0.3, double(Key.dragLockTimeout)))
        return c
    }
}
