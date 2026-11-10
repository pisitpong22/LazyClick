import CoreGraphics
import Foundation

/// Posts real CGEvents. Every event carries `marker` in `eventSourceUserData` so it is recognizable as ours.
public final class CGEventPoster: EventPosting {
    public static let marker: Int64 = 0x4D4D_5441 // "MMTA"

    private let source: CGEventSource?
    private var dragTap: CFMachPort?
    private var held: (button: MouseButton, clicks: Int)? // the synthetic button a drag is holding

    public init() {
        source = CGEventSource(stateID: .hidSystemState)
    }

    deinit { if let dragTap { CFMachPortInvalidate(dragTap) } } // the tap holds an unretained self

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

    /// Cmd+[ / Cmd+]: the standard back/forward shortcut. Mouse buttons 4/5 are ignored by Safari and Finder.
    public func postNavigate(back: Bool) {
        let key: CGKeyCode = back ? 0x21 : 0x1E // kVK_ANSI_LeftBracket / kVK_ANSI_RightBracket
        for down in [true, false] {
            guard let ev = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return }
            ev.flags = .maskCommand
            ev.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            ev.post(tap: .cghidEventTap)
        }
    }

    public func post(_ kind: SyntheticEventKind, button: MouseButton, clickCount: Int, at: CGPoint, delta: CGPoint) {
        if kind == .dragged, let tap = dragTap ?? makeDragTap() {
            held = (button, clickCount)
            if CGEvent.tapIsEnabled(tap: tap) { return } // the tap is already turning every real move into a drag
            CGEvent.tapEnable(tap: tap, enable: true)
        } else if kind == .up, let dragTap {
            CGEvent.tapEnable(tap: dragTap, enable: false)
            held = nil
        }
        send(kind, button: button, clickCount: clickCount, at: at, delta: delta)
    }

    private func send(_ kind: SyntheticEventKind, button: MouseButton, clickCount: Int, at: CGPoint, delta: CGPoint) {
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
            ev.setDoubleValueField(.mouseEventPressure, value: 1) // drawing apps read 0 as no ink
        }
        ev.post(tap: .cghidEventTap)
    }

    /// While a synthetic button is held, the mouse's own moves become drags. Touch frames are too sparse to pace a
    /// drag, and posting a position already passed pulls the pointer back. Nil until Accessibility is granted.
    /// Each move is swallowed and replaced by our own drag: a retyped real move keeps the mouse's button-up state,
    /// and window drags (Chrome, Electron title bars) end on it.
    private func makeDragTap() -> CFMachPort? {
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(1 << CGEventType.mouseMoved.rawValue),
                                          callback: { _, type, event, info in
            guard type == .mouseMoved, let info else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<CGEventPoster>.fromOpaque(info).takeUnretainedValue()
            guard let held = me.held else { return Unmanaged.passUnretained(event) }
            me.send(.dragged, button: held.button, clickCount: held.clicks, at: event.location,
                    delta: CGPoint(x: Double(event.getIntegerValueField(.mouseEventDeltaX)),
                                   y: Double(event.getIntegerValueField(.mouseEventDeltaY))))
            return nil
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return nil }
        CGEvent.tapEnable(tap: tap, enable: false) // tapCreate starts it on; idle mouse moves must not pass through us
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        dragTap = tap
        return tap
    }
}
