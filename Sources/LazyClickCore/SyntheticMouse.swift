import CoreGraphics
import Foundation

public enum SyntheticEventKind: Sendable { case down, up, dragged }

/// Abstraction over CGEvent posting so the logic can be tested without touching the real pointer.
public protocol EventPosting: AnyObject {
    func post(_ kind: SyntheticEventKind, button: MouseButton, clickCount: Int, at: CGPoint, delta: CGPoint)
    func postMagnify(_ amount: Double, phase: MagnifyPhase)
    func postNavigate(back: Bool)
}

/// Turns engine actions into events and guarantees a held button is always released.
public final class SyntheticMouse {
    private let poster: EventPosting
    private var held: MouseButton?
    private var lastDragPoint = CGPoint.zero

    public init(poster: EventPosting) { self.poster = poster }

    public var isHeld: Bool { held != nil }

    public func apply(_ action: GestureAction) {
        switch action {
        case let .click(button, count, at):
            releaseHeld(at: at)
            poster.post(.down, button: button, clickCount: count, at: at, delta: .zero)
            poster.post(.up, button: button, clickCount: count, at: at, delta: .zero)
        case let .dragBegin(at):
            releaseHeld(at: at)
            held = .left
            lastDragPoint = at
            poster.post(.down, button: .left, clickCount: 1, at: at, delta: .zero)
        case let .dragMove(to):
            guard held != nil else { return }
            let delta = CGPoint(x: to.x - lastDragPoint.x, y: to.y - lastDragPoint.y)
            lastDragPoint = to
            poster.post(.dragged, button: .left, clickCount: 1, at: to, delta: delta)
        case let .dragEnd(at):
            releaseHeld(at: at)
        case let .magnify(amount, phase):
            poster.postMagnify(amount, phase: phase)
        case let .navigate(back):
            poster.postNavigate(back: back)
        case .startDragLockTimer, .cancelDragLockTimer:
            break // handled by the controller
        }
    }

    /// Releases any button this object pressed. Safe to call repeatedly.
    public func releaseHeld(at point: CGPoint) {
        guard let b = held else { return }
        held = nil
        poster.post(.up, button: b, clickCount: 1, at: point, delta: .zero)
    }
}
