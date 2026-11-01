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
