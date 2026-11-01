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

    private enum Phase {
        case idle          // no fingers
        case session       // fingers down, undecided
        case dragging      // synthetic left button held
        case dragLockWait  // all fingers lifted, button still held until timeout / re-touch
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
    private var sessionStartX: Float = 0.5

    private var lastTap: (time: Double, location: CGPoint, count: Int)?

    public init(config: GestureConfig = GestureConfig()) {
        self.config = config
        tracks.reserveCapacity(8)
        active.reserveCapacity(8)
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
        if config.style == .mouse, config.tapDragEnabled, active.count == 1,
           let prev = lastTap,
           t - prev.time <= config.doubleClickInterval,
           hypot(cursor.x - prev.location.x, cursor.y - prev.location.y) <= config.doubleClickDistance {
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

        if physicalDown { tapValid = false }
        if t - sessionStart > config.maxTapDuration { tapValid = false }

        let moved = hypot(cursor.x - cursorStart.x, cursor.y - cursorStart.y)
        if moved > config.cursorTapTolerance { tapValid = false }

        if n >= 3 {
            if threeSince == nil { threeSince = t }
        } else {
            threeSince = nil
        }

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

        if !tapValid && !(config.threeFingerDragEnabled && peak >= 3) {
            // Nothing else can come of this session; wait for every finger to lift.
            phase = .ignoring
        }
    }

    /// Mouse style: only a single, stationary-on-the-surface finger matters. A touch that follows a left tap
    /// closely becomes a drag as soon as the pointer travels; otherwise it can only end as a tap.
    private func updateMouseStyle(_ t: Double, _ cursor: CGPoint, _ physicalDown: Bool, moved: Double) {
        if physicalDown || slid || peak >= 2 { dragArmed = false }
        if dragArmed, active.count == 1,
           t - sessionStart >= config.dragStabilizeTime,
           moved >= config.dragActivationDistance {
            beginDrag(cursor)
            return
        }
        if !tapValid && !dragArmed { phase = .ignoring }
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
            guard peak == 1 else { return }
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
