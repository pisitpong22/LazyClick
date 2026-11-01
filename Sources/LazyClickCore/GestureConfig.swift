import Foundation

/// Which gesture vocabulary is active.
public enum GestureStyle: Int, Sendable {
    /// Trackpad-like: 1/2/3-finger taps = left/right/middle click, three-finger drag.
    case trackpad = 0
    /// Mouse-like: one-finger tap on the left/right half = left/right click; tap, then touch again and
    /// hold while moving the mouse = drag (no three fingers needed).
    case mouse = 1
}

/// All tunables for the gesture engine. Values marked "internal" are not exposed in the UI.
public struct GestureConfig: Equatable, Sendable {
    public var style: GestureStyle = .trackpad

    // Mouse style switches
    public var leftSideTapEnabled = true
    public var rightSideTapEnabled = true
    /// Tap, then touch again within the double-click interval and move the mouse -> drag.
    public var tapDragEnabled = true
    /// Swap which half of the surface counts as "left" (left-handed users / mirrored sensor).
    public var swapSides = false

    // Feature switches (menu)
    public var oneFingerTapEnabled = true
    public var twoFingerTapEnabled = true
    public var threeFingerTapEnabled = true
    public var threeFingerDragEnabled = true

    // Advanced settings (Settings panel)
    /// 0 = strict (short, tiny movement), 1 = relaxed (longer, more movement tolerated).
    public var tapSensitivity: Double = 0.5
    /// Cursor travel (points) with three fingers down before a drag starts.
    public var dragActivationDistance: Double = 6
    public var dragLockEnabled = false
    /// How long the button stays down after all fingers lift when drag lock is on.
    public var dragLockTimeout: Double = 1.0

    // Internal
    /// Fingers that land within this window of the first finger count as one simultaneous gesture.
    public var fingerLandWindow: Double = 0.10
    /// Three fingers must be present this long before a drag may begin (count stabilization).
    public var dragStabilizeTime: Double = 0.03
    /// Optional hold activation for drag (seconds, 0 = off). Always clamped above the tap duration.
    public var dragHoldTime: Double = 0
    /// Cursor travel (points) that disqualifies a tap (mouse is being moved, not tapped).
    public var cursorTapTolerance: Double = 4
    public var doubleClickInterval: Double = 0.4
    public var doubleClickDistance: Double = 6
    /// Contacts closer than this to the left/right edge are ignored (grip / thumb).
    public var edgeInset: Float = 0.03
    /// Normalized x that separates the left half from the right half in mouse style.
    public var sideSplit: Float = 0.5

    public init() {}

    public var maxTapDuration: Double { 0.18 + (0.40 - 0.18) * clamp01(tapSensitivity) }
    public var tapMoveTolerance: Float { Float(0.03 + (0.10 - 0.03) * clamp01(tapSensitivity)) }
    public var effectiveDragHoldTime: Double {
        dragHoldTime <= 0 ? 0 : max(dragHoldTime, maxTapDuration + 0.05)
    }

    private func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }
}
