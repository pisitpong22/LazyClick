import CoreGraphics
import Foundation

/// Touch-lifecycle gesture state machine. Pure logic: no OS calls, no timers, no allocation per frame.
///
/// A *session* starts when the first finger lands (count 0 -> >0) and ends when the last finger lifts.
/// Taps are decided only at session end, so fingers landing or lifting a few milliseconds apart can
/// never produce intermediate 1- or 2-finger clicks. A drag takes over the session and permanently
/// disqualifies it from producing a tap, so a drag can never end in a middle click.
public final class GestureEngine {
    public var config: GestureConfig
    public var onAction: ((GestureAction) -> Void)?
    /// Asked once per touch in mouse style: is the OS region-screenshot crosshair up?
    /// Any click there ends the selection, so tap-then-drag can't work.
    public var isRegionSelecting: () -> Bool = { false }

    private enum Phase {
        case idle          // no fingers
        case session       // fingers down, undecided
        case dragging      // synthetic left button held
        case dragLockWait  // all fingers lifted, button still held until timeout / re-touch
        case pinching      // two-finger zoom in progress
        case ignoring      // gesture disqualified; wait for all fingers to lift
    }

    private struct Track {
        var id: Int32
        var startX: Float
        var startY: Float
    }

    private var phase: Phase = .idle
    private var requireLift = false

    private var tracks: [Track] = []
    private var active: [Contact] = []

    private var sessionStart: Double = 0
    private var peak = 0
    private var tapValid = false
    private var cursorStart = CGPoint.zero
    private var threeSince: Double?
    private var lastCursor = CGPoint.zero
    private var slid = false           // a finger slid across the surface (scroll/swipe)
    private var dragArmed = false      // mouse style: this touch follows a left tap closely -> may become a drag
    private var regionDrag = false     // mouse style: this touch landed during a region screenshot
    private var swipeOpen = false      // this touch can still become a back/forward swipe
    private var sessionStartX: Float = 0.5
    private var pinchGap: Float = 0

    private var lastTap: (time: Double, location: CGPoint, count: Int)?

    public init(config: GestureConfig = GestureConfig()) {
        self.config = config
        tracks.reserveCapacity(8)
        active.reserveCapacity(8)
    }

    /// Reads a CGWindowList result. `screencapture` owns a window while the crosshair is up. "Screenshot" always has a
    /// low full-screen window, and only the Cmd+Shift+5 toolbar, which needs real clicks, sits above the crosshair.
    /// shortcut: "Screenshot" is the name seen on this Mac, switch to a pid/bundle-id check if another locale renames it.
    public static func regionSelecting(windows: [[String: Any]]) -> Bool {
        func topLayer(_ owner: String) -> Int {
            windows.filter { $0[kCGWindowOwnerName as String] as? String == owner }
                .compactMap { $0[kCGWindowLayer as String] as? Int }.max() ?? -1
        }
        let crosshair = topLayer("screencapture")
        return crosshair >= 0 && topLayer("Screenshot") < crosshair
    }

    public var isIdle: Bool { phase == .idle && !requireLift }
    /// True while the synthetic left button is (or may be) held.
    public var isDragging: Bool { phase == .dragging || phase == .dragLockWait }

    // MARK: - Input

    public func process(timestamp t: Double,
                        contacts: [Contact],
                        cursor: CGPoint,
                        physicalButtonDown: Bool) {
        active.removeAll(keepingCapacity: true)
        let inset = config.edgeInset
        for c in contacts where c.x >= inset && c.x <= 1 - inset {
            active.append(c)
        }
        let n = active.count

        switch phase {
        case .idle:
            if n == 0 {
                requireLift = false
                return
            }
            if requireLift {
                requireLift = false
                phase = .ignoring
                return
            }
            startSession(t, cursor)
        case .dragLockWait:
            if n == 0 { return }
            emit(.cancelDragLockTimer)
            resumeDrag(cursor)
        default:
            break
        }

        if n == 0 {
            finishSession(t, cursor, physicalDown: physicalButtonDown)
            return
        }

        switch phase {
        case .session: updateSession(t, cursor, physicalButtonDown)
        case .dragging: updateDrag(cursor)
        case .pinching: updatePinch()
        default: break
        }
    }

    /// Host calls this when the one-shot drag-lock timer fires.
    public func dragLockTimerFired(cursor: CGPoint) {
        guard phase == .dragLockWait else { return }
        phase = .idle
        lastTap = nil
        emit(.dragEnd(at: cursor))
    }

    /// Abort everything (disable, disconnect, sleep, shutdown). Releases a held button.
    /// Fingers that are still down must lift before another gesture can start.
    public func cancelAll(cursor: CGPoint) {
        if phase == .dragLockWait { emit(.cancelDragLockTimer) }
        if phase == .dragging || phase == .dragLockWait { emit(.dragEnd(at: cursor)) }
        if phase == .pinching { emit(.magnify(amount: 0, phase: .ended)) }
        // Only demand a lift if we know fingers are on the surface; otherwise the next touch is legitimate.
        requireLift = (phase != .idle)
        phase = .idle
        tracks.removeAll(keepingCapacity: true)
        threeSince = nil
        peak = 0
        tapValid = false
        lastTap = nil
    }

    // MARK: - Session handling

    private func startSession(_ t: Double, _ cursor: CGPoint) {
        phase = .session
        sessionStart = t
        peak = active.count
        tapValid = true
        slid = false
        cursorStart = cursor
        sessionStartX = active.first?.x ?? 0.5
        threeSince = nil
        dragArmed = false
        regionDrag = config.style == .mouse && config.tapDragEnabled && isRegionSelecting()
        if config.style == .mouse, config.tapDragEnabled, active.count == 1,
           regionDrag || lastTap.map({ t - $0.time <= config.doubleClickInterval }) == true {
            // Time only: a quick tap-and-drag is already moving the pointer when the finger lands.
            dragArmed = true
        }
        tracks.removeAll(keepingCapacity: true)
        for c in active { tracks.append(Track(id: c.id, startX: c.x, startY: c.y)) }
    }

    private func updateSession(_ t: Double, _ cursor: CGPoint, _ physicalDown: Bool) {
        let n = active.count
        let inLandWindow = (t - sessionStart) <= config.fingerLandWindow

        if inLandWindow {
            peak = max(peak, n)
        } else if n > peak {
            tapValid = false // a finger arrived late: resting hand, not a simultaneous tap
        }

        let tolerance = config.tapMoveTolerance
        for c in active {
            if let i = tracks.firstIndex(where: { $0.id == c.id }) {
                let tr = tracks[i]
                if max(abs(c.x - tr.startX), abs(c.y - tr.startY)) > tolerance {
                    tapValid = false // fingers sliding: scroll / swipe
                    slid = true
                }
            } else {
                tracks.append(Track(id: c.id, startX: c.x, startY: c.y))
                if !inLandWindow { tapValid = false }
            }
        }

        if peak == 2, !physicalDown, let (now, start) = fingerGaps(), abs(now - start) > config.pinchActivation {
            phase = .pinching
            tapValid = false
            pinchGap = start
            emit(.magnify(amount: 0, phase: .began))
            updatePinch()
            return
        }

        if physicalDown { tapValid = false }
        if t - sessionStart > config.maxTapDuration { tapValid = false }

        let moved = hypot(cursor.x - cursorStart.x, cursor.y - cursorStart.y)
        if moved > config.cursorTapTolerance { tapValid = false }

        if n >= 3 {
            if threeSince == nil { threeSince = t }
        } else {
            threeSince = nil
        }

        if updateSwipe(t, physicalDown, moved: moved) { return }

        if config.style == .mouse {
            updateMouseStyle(t, cursor, physicalDown, moved: moved)
            return
        }

        if config.threeFingerDragEnabled,
           peak >= 3,
           !physicalDown,
           let since = threeSince,
           t - since >= config.dragStabilizeTime {
            let hold = config.effectiveDragHoldTime
            if moved >= config.dragActivationDistance || (hold > 0 && t - since >= hold) {
                beginDrag(cursor)
                return
            }
        }

        if !tapValid && !swipeOpen && !(config.threeFingerDragEnabled && peak >= 3) {
            // Nothing else can come of this session; wait for every finger to lift.
            phase = .ignoring
        }
    }

    /// Mouse style: only a single, stationary-on-the-surface finger matters. A touch that follows a left tap
    /// closely becomes a drag as soon as the pointer travels; otherwise it can only end as a tap.
    private func updateMouseStyle(_ t: Double, _ cursor: CGPoint, _ physicalDown: Bool, moved: Double) {
        // Pushing the mouse shifts the fingertip on the surface; only a slide while the pointer is still is a scroll.
        if physicalDown || peak >= 2 || (slid && moved < config.cursorTapTolerance) { dragArmed = false }
        if dragArmed, active.count == 1,
           moved >= config.dragActivationDistance {
            beginDrag(cursor)
            return
        }
        if !tapValid && !dragArmed && !swipeOpen { phase = .ignoring }
    }

    /// One finger flicked sideways while the mouse stays still: left-to-right = back, right-to-left = forward.
    /// Returns true if it fired; otherwise `swipeOpen` says whether the flick can still complete.
    private func updateSwipe(_ t: Double, _ physicalDown: Bool, moved: Double) -> Bool {
        swipeOpen = false
        guard config.swipeNavigationEnabled, peak == 1, active.count == 1, !physicalDown,
              moved < config.cursorTapTolerance, t - sessionStart <= config.swipeMaxDuration,
              let tr = tracks.first(where: { $0.id == active[0].id }) else { return false }
        let dx = active[0].x - tr.startX
        // The sensor is ~1.75x taller than wide, so 3x normalized is ~1.7x in real distance.
        guard abs(dx) >= config.swipeDistance, abs(dx) > 3 * abs(active[0].y - tr.startY) else {
            swipeOpen = true
            return false
        }
        phase = .ignoring
        tapValid = false
        lastTap = nil
        emit(.navigate(back: dx > 0))
        return true
    }

    /// Current and session-start distance between the two fingers, nil unless exactly two tracked fingers.
    private func fingerGaps() -> (now: Float, start: Float)? {
        guard active.count == 2,
              let a = tracks.first(where: { $0.id == active[0].id }),
              let b = tracks.first(where: { $0.id == active[1].id }) else { return nil }
        return (hypot(active[0].x - active[1].x, active[0].y - active[1].y),
                hypot(a.startX - b.startX, a.startY - b.startY))
    }

    private func updatePinch() {
        guard let (now, _) = fingerGaps() else { // a finger lifted or a third landed: end the zoom
            phase = .ignoring
            emit(.magnify(amount: 0, phase: .ended))
            return
        }
        let delta = Double(now - pinchGap) * config.pinchGain
        pinchGap = now
        if delta != 0 { emit(.magnify(amount: delta, phase: .changed)) }
    }

    private func beginDrag(_ cursor: CGPoint) {
        phase = .dragging
        tapValid = false
        lastTap = nil
        lastCursor = cursorStart
        emit(.dragBegin(at: cursorStart))
        updateDrag(cursor)
    }

    private func resumeDrag(_ cursor: CGPoint) {
        phase = .dragging
        lastCursor = cursor
        tracks.removeAll(keepingCapacity: true)
        for c in active { tracks.append(Track(id: c.id, startX: c.x, startY: c.y)) }
    }

    private func updateDrag(_ cursor: CGPoint) {
        if cursor != lastCursor {
            lastCursor = cursor
            emit(.dragMove(to: cursor))
        }
    }

    private func finishSession(_ t: Double, _ cursor: CGPoint, physicalDown: Bool) {
        let wasPhase = phase
        tracks.removeAll(keepingCapacity: true)
        threeSince = nil

        switch wasPhase {
        case .dragging:
            if config.dragLockEnabled {
                phase = .dragLockWait
                emit(.startDragLockTimer(seconds: config.dragLockTimeout))
            } else {
                phase = .idle
                emit(.dragEnd(at: cursor))
            }
        case .pinching:
            phase = .idle
            emit(.magnify(amount: 0, phase: .ended))
        case .session:
            phase = .idle
            let duration = t - sessionStart
            if tapValid && !physicalDown && duration <= config.maxTapDuration {
                emitTap(peak: peak, time: t, cursor: cursor)
            }
        default:
            phase = .idle
        }
        peak = 0
        tapValid = false
    }

    private func emitTap(peak: Int, time t: Double, cursor: CGPoint) {
        if config.style == .mouse {
            guard peak == 1, !regionDrag else { return }
            let isLeftHalf = (sessionStartX < config.sideSplit) != config.swapSides
            if isLeftHalf {
                if config.leftSideTapEnabled { emitLeftTap(time: t, cursor: cursor) }
            } else if config.rightSideTapEnabled {
                lastTap = nil
                emit(.click(.right, clickCount: 1, at: cursor))
            }
            return
        }
        switch peak {
        case 1 where config.oneFingerTapEnabled:
            emitLeftTap(time: t, cursor: cursor)
        case 2 where config.twoFingerTapEnabled:
            lastTap = nil
            emit(.click(.right, clickCount: 1, at: cursor))
        case 3 where config.threeFingerTapEnabled:
            lastTap = nil
            emit(.click(.middle, clickCount: 1, at: cursor))
        default:
            break
        }
    }

    private func emitLeftTap(time t: Double, cursor: CGPoint) {
        var count = 1
        if let prev = lastTap,
           t - prev.time <= config.doubleClickInterval,
           hypot(cursor.x - prev.location.x, cursor.y - prev.location.y) <= config.doubleClickDistance {
            count = prev.count >= 3 ? 1 : prev.count + 1
        }
        lastTap = (t, cursor, count)
        emit(.click(.left, clickCount: count, at: cursor))
    }

    @inline(__always)
    private func emit(_ action: GestureAction) {
        onAction?(action)
    }
}
