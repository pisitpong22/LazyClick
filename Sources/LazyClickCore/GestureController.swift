import CoreGraphics
import Foundation

/// One-shot timer used only for drag lock. Never repeating, never armed while idle.
public protocol DragLockTimer: AnyObject {
    func schedule(after seconds: Double, _ fire: @escaping () -> Void)
    func cancel()
}

/// Thread-safe glue: raw frames in, synthetic mouse events out. Owns the enable switch and every
/// cleanup path (disable, device loss, sleep, shutdown) so a synthetic button is never left held.
public final class GestureController {
    private let lock = NSLock()
    private let engine: GestureEngine
    private let mouse: SyntheticMouse
    private let cursorProvider: () -> CGPoint
    private let physicalButtonProvider: () -> Bool
    private let timer: DragLockTimer

    private var enabled = false
    private var shutDown = false
    private var scratch: [Contact] = []
    private var implausibleFrames = 0

    /// Called (from the touch thread) once if the private ABI looks wrong and handling was disabled.
    public var onABIFault: (() -> Void)?

    /// Called (from the touch thread, holding the lock) for each synthetic click. Must return immediately.
    public var onClick: (() -> Void)?

    public init(poster: EventPosting,
                timer: DragLockTimer,
                config: GestureConfig = GestureConfig(),
                cursorProvider: @escaping () -> CGPoint,
                physicalButtonProvider: @escaping () -> Bool,
                regionSelectingProvider: @escaping () -> Bool = { false }) {
        self.engine = GestureEngine(config: config)
        self.mouse = SyntheticMouse(poster: poster)
        self.timer = timer
        self.cursorProvider = cursorProvider
        self.physicalButtonProvider = physicalButtonProvider
        scratch.reserveCapacity(MTLayout.maxPlausibleContacts)
        engine.isRegionSelecting = regionSelectingProvider
        engine.onAction = { [unowned self] action in self.perform(action) }
    }

    // MARK: - State

    public var isEnabled: Bool { locked { enabled } }
    public var isMouseHeld: Bool { locked { mouse.isHeld } }

    public func setEnabled(_ on: Bool) {
        locked {
            guard !shutDown else { return }
            if !on && enabled { abortLocked() }
            enabled = on
            if on { implausibleFrames = 0 }
        }
    }

    public func updateConfig(_ config: GestureConfig) {
        locked {
            let wasDragLock = engine.config.dragLockEnabled
            let old = engine.config
            let dragOff = (!config.threeFingerDragEnabled && old.threeFingerDragEnabled)
                || (!config.tapDragEnabled && old.tapDragEnabled)
                || config.style != old.style
            engine.config = config
            if (wasDragLock && !config.dragLockEnabled) || dragOff { abortLocked() }
        }
    }

    /// Magic Mouse went away (Bluetooth drop, battery, unplug) or the driver list is being rebuilt.
    public func deviceDisconnected() { locked { abortLocked() } }

    public func systemWillSleep() { locked { abortLocked() } }

    /// Final cleanup. After this the controller ignores all input.
    public func shutdown() {
        locked {
            abortLocked()
            enabled = false
            shutDown = true
        }
    }

    // MARK: - Input

    /// Entry point for the private-API callback. `base` points at `count` MTTouch records.
    public func handleRawFrame(_ base: UnsafeRawPointer?, count: Int, timestamp: Double) {
        lock.lock()
        defer { lock.unlock() }
        guard enabled else { return }
        switch RawFrameParser.parse(base, count: count, into: &scratch) {
        case .ok:
            implausibleFrames = 0
            processLocked(timestamp)
        case .implausible:
            implausibleFrames += 1
            if implausibleFrames >= 5 {
                abortLocked()
                enabled = false
                onABIFault?()
            }
        }
    }

    /// Test / non-raw entry point.
    public func handleFrame(timestamp: Double, contacts: [Contact]) {
        lock.lock()
        defer { lock.unlock() }
        guard enabled else { return }
        scratch.removeAll(keepingCapacity: true)
        scratch.append(contentsOf: contacts)
        processLocked(timestamp)
    }

    private func processLocked(_ t: Double) {
        if scratch.isEmpty && engine.isIdle { return } // nothing to do, skip OS queries
        let cursor = cursorProvider()
        // Our own synthetic button must not be mistaken for a physical click.
        let physical = mouse.isHeld ? false : physicalButtonProvider()
        engine.process(timestamp: t, contacts: scratch, cursor: cursor, physicalButtonDown: physical)
    }

    // MARK: - Internals

    private func perform(_ action: GestureAction) {
        switch action {
        case let .startDragLockTimer(seconds):
            timer.schedule(after: seconds) { [weak self] in self?.dragLockTimerFired() }
        case .cancelDragLockTimer:
            timer.cancel()
        default:
            mouse.apply(action)
            if case .click = action { onClick?() }
        }
    }

    private func dragLockTimerFired() {
        locked { engine.dragLockTimerFired(cursor: cursorProvider()) }
    }

    private func abortLocked() {
        let cursor = cursorProvider()
        engine.cancelAll(cursor: cursor)
        timer.cancel()
        mouse.releaseHeld(at: cursor) // belt and braces
    }

    @inline(__always)
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
