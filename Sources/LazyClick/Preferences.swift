import Foundation
import LazyClickCore

/// UserDefaults-backed settings. Reads happen on demand; nothing is polled.
enum Preferences {
    private static let d = UserDefaults.standard

    enum Key {
        static let enabled = "enabled"
        static let oneFinger = "oneFingerTap"
        static let twoFinger = "twoFingerTap"
        static let threeFinger = "threeFingerTap"
        static let threeFingerDrag = "threeFingerDrag"
        static let style = "gestureStyle"
        static let leftSideTap = "leftSideTap"
        static let rightSideTap = "rightSideTap"
        static let tapDrag = "tapDrag"
        static let swapSides = "swapSides"
        static let didPromptAccessibility = "didPromptAccessibility"
        static let clickSound = "clickSound"
        static let clickVolume = "clickVolume"
    }

    static func registerDefaults() {
        d.register(defaults: [
            Key.enabled: true,
            Key.oneFinger: true,
            Key.twoFinger: true,
            Key.threeFinger: true,
            Key.threeFingerDrag: true,
            Key.style: 1, // mouse style (Magic Mouse is the target device)
            Key.leftSideTap: true,
            Key.rightSideTap: true,
            Key.tapDrag: true,
            Key.swapSides: false,
            Key.clickSound: "None",
            Key.clickVolume: 0.5,
        ])
    }

    static func bool(_ key: String) -> Bool { d.bool(forKey: key) }
    static var style: GestureStyle {
        get { GestureStyle(rawValue: d.integer(forKey: Key.style)) ?? .trackpad }
        set { d.set(newValue.rawValue, forKey: Key.style) }
    }
    static func set(_ value: Bool, for key: String) { d.set(value, forKey: key) }
    static func double(_ key: String) -> Double { d.double(forKey: key) }
    static func set(_ value: Double, for key: String) { d.set(value, forKey: key) }
    static func string(_ key: String) -> String { d.string(forKey: key) ?? "" }
    static func set(_ value: String, for key: String) { d.set(value, forKey: key) }

    static func gestureConfig() -> GestureConfig {
        var c = GestureConfig()
        c.oneFingerTapEnabled = bool(Key.oneFinger)
        c.twoFingerTapEnabled = bool(Key.twoFinger)
        c.threeFingerTapEnabled = bool(Key.threeFinger)
        c.threeFingerDragEnabled = bool(Key.threeFingerDrag)
        c.style = style
        c.leftSideTapEnabled = bool(Key.leftSideTap)
        c.rightSideTapEnabled = bool(Key.rightSideTap)
        c.tapDragEnabled = bool(Key.tapDrag)
        c.swapSides = bool(Key.swapSides)
        return c
    }
}
