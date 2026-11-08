import CoreGraphics

public enum MouseButton: Int, Sendable {
    case left, right, middle
}

/// One finger currently touching the surface. Coordinates are normalized 0...1.
public struct Contact: Equatable, Sendable {
    public var id: Int32
    public var x: Float
    public var y: Float
    public init(id: Int32, x: Float, y: Float) {
        self.id = id
        self.x = x
        self.y = y
    }
}

public enum MagnifyPhase: Sendable { case began, changed, ended }

/// What the gesture engine asks the outside world to do. The engine never touches the OS itself.
public enum GestureAction: Equatable, Sendable {
    case click(MouseButton, clickCount: Int, at: CGPoint)
    case dragBegin(at: CGPoint)
    case dragMove(to: CGPoint)
    case dragEnd(at: CGPoint)
    /// Two-finger pinch. `amount` > 0 zooms in, < 0 zooms out (same scale as a trackpad magnify event).
    case magnify(amount: Double, phase: MagnifyPhase)
    /// One-finger sideways swipe: go back or forward in the frontmost app.
    case navigate(back: Bool)
    case startDragLockTimer(seconds: Double)
    case cancelDragLockTimer
}
