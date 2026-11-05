import CoreGraphics
import Foundation

/// Posts real CGEvents. Every event carries `marker` in `eventSourceUserData` so it is recognizable as ours.
public final class CGEventPoster: EventPosting {
    public static let marker: Int64 = 0x4D4D_5441 // "MMTA"

    private let source: CGEventSource?

    public init() {
        source = CGEventSource(stateID: .hidSystemState)
    }

    public static func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
    }

    /// Trackpad-style magnify via the undocumented gesture event (type 29). Field numbers are reverse-engineered:
    /// 110 = HID event type (8 = zoom), 113 = amount, 132 = NSEventPhase (1 began, 4 changed, 8 ended).
    public func postMagnify(_ amount: Double, phase: MagnifyPhase) {
        guard let ev = CGEvent(source: source), let type = CGEventType(rawValue: 29),
              let fType = CGEventField(rawValue: 110), let fAmount = CGEventField(rawValue: 113),
              let fPhase = CGEventField(rawValue: 132) else { return }
        ev.type = type
        ev.setIntegerValueField(fType, value: 8)
        ev.setDoubleValueField(fAmount, value: amount)
        ev.setIntegerValueField(fPhase, value: phase == .began ? 1 : phase == .changed ? 4 : 8)
        ev.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        ev.post(tap: .cghidEventTap)
    }

    public func post(_ kind: SyntheticEventKind, button: MouseButton, clickCount: Int, at: CGPoint, delta: CGPoint) {
        let type: CGEventType
        let cgButton: CGMouseButton
        switch (button, kind) {
        case (.left, .down): type = .leftMouseDown; cgButton = .left
        case (.left, .up): type = .leftMouseUp; cgButton = .left
        case (.left, .dragged): type = .leftMouseDragged; cgButton = .left
        case (.right, .down): type = .rightMouseDown; cgButton = .right
        case (.right, .up): type = .rightMouseUp; cgButton = .right
        case (.right, .dragged): type = .rightMouseDragged; cgButton = .right
        case (.middle, .down): type = .otherMouseDown; cgButton = .center
        case (.middle, .up): type = .otherMouseUp; cgButton = .center
        case (.middle, .dragged): type = .otherMouseDragged; cgButton = .center
        }
        guard let ev = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: at, mouseButton: cgButton) else { return }
        ev.setIntegerValueField(.mouseEventClickState, value: Int64(max(1, clickCount)))
        ev.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        if kind == .dragged {
            ev.setIntegerValueField(.mouseEventDeltaX, value: Int64(delta.x.rounded()))
            ev.setIntegerValueField(.mouseEventDeltaY, value: Int64(delta.y.rounded()))
        }
        ev.post(tap: .cghidEventTap)
    }
}
