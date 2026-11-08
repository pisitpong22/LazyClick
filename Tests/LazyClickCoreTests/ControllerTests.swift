import CoreGraphics
import XCTest
@testable import LazyClickCore

final class MockPoster: EventPosting {
    struct Event: Equatable {
        var kind: SyntheticEventKind
        var button: MouseButton
        var clickCount: Int
        var at: CGPoint
    }
    var events: [Event] = []
    func post(_ kind: SyntheticEventKind, button: MouseButton, clickCount: Int, at: CGPoint, delta: CGPoint) {
        events.append(Event(kind: kind, button: button, clickCount: clickCount, at: at))
    }
    func postMagnify(_ amount: Double, phase: MagnifyPhase) {}
    func postNavigate(back: Bool) {}
    var downs: Int { events.filter { $0.kind == .down }.count }
    var ups: Int { events.filter { $0.kind == .up }.count }
    var buttonHeld: Bool { downs != ups }
}

final class MockTimer: DragLockTimer {
    var fire: (() -> Void)?
    var scheduled: [Double] = []
    var cancels = 0
    func schedule(after seconds: Double, _ fire: @escaping () -> Void) { scheduled.append(seconds); self.fire = fire }
    func cancel() { cancels += 1; fire = nil }
}

final class ControllerTests: XCTestCase {
    var poster: MockPoster!
    var timer: MockTimer!
    var cursor = CGPoint(x: 300, y: 300)
    var physical = false
    var t = 10.0
    var controller: GestureController!

    override func setUp() {
        poster = MockPoster()
        timer = MockTimer()
        cursor = CGPoint(x: 300, y: 300)
        physical = false
        t = 10.0
        controller = make()
        controller.setEnabled(true)
    }

    private func make(_ configure: (inout GestureConfig) -> Void = { _ in }) -> GestureController {
        var c = GestureConfig()
        configure(&c)
        return GestureController(poster: poster, timer: timer, config: c,
                                 cursorProvider: { [unowned self] in self.cursor },
                                 physicalButtonProvider: { [unowned self] in self.physical })
    }

    private func frame(_ dt: Double, _ c: [Contact]) { t += dt; controller.handleFrame(timestamp: t, contacts: c) }

    private func dragStart() {
        frame(0, three); frame(0.12, three)
        cursor.x += 25
        frame(0.011, three)
    }

    func testRegionQueryRunsOncePerMouseStyleTouchAndNeverForEdgeGrip() {
        var queries = 0
        var config = GestureConfig()
        config.style = .mouse
        let c = GestureController(poster: poster, timer: timer, config: config,
                                  cursorProvider: { .zero }, physicalButtonProvider: { false },
                                  regionSelectingProvider: { queries += 1; return false })
        c.setEnabled(true)
        for i in 0..<5 { c.handleFrame(timestamp: Double(i) * 0.01, contacts: [f(1, 0.01, 0.5)]) }
        c.handleFrame(timestamp: 0.1, contacts: [])
        XCTAssertEqual(queries, 0, "a finger resting on the edge is not a touch")
        for i in 0..<5 { c.handleFrame(timestamp: 0.5 + Double(i) * 0.01, contacts: [f(1, 0.3, 0.5)]) }
        XCTAssertEqual(queries, 1)
    }

    func testRegionQueryIsSkippedInTrackpadStyle() {
        var queries = 0
        let c = GestureController(poster: poster, timer: timer, config: GestureConfig(),
                                  cursorProvider: { .zero }, physicalButtonProvider: { false },
                                  regionSelectingProvider: { queries += 1; return false })
        c.setEnabled(true)
        c.handleFrame(timestamp: 0, contacts: [f(1, 0.3, 0.5)])
        XCTAssertEqual(queries, 0)
    }

    func testOneTapPostsDownUpPairWithClickState() {
        frame(0, one); frame(0.05, [])
        XCTAssertEqual(poster.events.map(\.kind), [.down, .up])
        XCTAssertEqual(poster.events.map(\.button), [.left, .left])
        XCTAssertEqual(poster.events.map(\.clickCount), [1, 1])
    }

    func testTwoAndThreeFingerTapsUseRightAndMiddleButtons() {
        frame(0, two); frame(0.05, [])
        frame(0.3, three); frame(0.05, [])
        XCTAssertEqual(poster.events.map(\.button), [.right, .right, .middle, .middle])
        XCTAssertFalse(poster.buttonHeld)
    }

    func testOnClickFiresForTapsButNotDrags() {
        var clicks = 0
        controller.onClick = { clicks += 1 }
        frame(0, one); frame(0.05, [])
        XCTAssertEqual(clicks, 1)
        frame(0.5, []); dragStart(); frame(0.01, [])
        XCTAssertEqual(poster.downs, 2, "the drag really started")
        XCTAssertEqual(clicks, 1)
    }

    func testDragPostsDownDraggedUpAndNeverLeavesButtonHeld() {
        dragStart()
        XCTAssertTrue(poster.buttonHeld)
        XCTAssertTrue(controller.isMouseHeld)
        cursor.x += 10; frame(0.011, three)
        frame(0.01, [])
        XCTAssertFalse(poster.buttonHeld)
        XCTAssertFalse(controller.isMouseHeld)
        XCTAssertEqual(poster.events.first?.kind, .down)
        XCTAssertTrue(poster.events.contains { $0.kind == .dragged })
        XCTAssertEqual(poster.events.filter { $0.button == .middle }.count, 0)
        XCTAssertEqual(poster.downs, 1)
    }

    func testTurningOffMidDragReleasesImmediatelyAndStopsInjecting() {
        dragStart()
        XCTAssertTrue(poster.buttonHeld)
        controller.setEnabled(false)
        XCTAssertFalse(poster.buttonHeld)
        let count = poster.events.count
        cursor.x += 30; frame(0.011, three); frame(0.01, []); frame(0.2, one); frame(0.05, [])
        XCTAssertEqual(poster.events.count, count, "nothing injected while disabled")
    }

    func testDisabledControllerNeverInjects() {
        controller.setEnabled(false)
        frame(0, one); frame(0.05, [])
        XCTAssertTrue(poster.events.isEmpty)
    }

    func testDeviceDisconnectMidDragReleasesButton() {
        dragStart()
        controller.deviceDisconnected()
        XCTAssertFalse(poster.buttonHeld)
        // Stale frames for fingers that vanished with the device are ignored until they "lift".
        frame(0.01, three)
        frame(0.01, [])
        XCTAssertEqual(poster.downs, 1)
    }

    func testReconnectionWorksAfterDisconnect() {
        frame(0, one); frame(0.05, [])
        controller.deviceDisconnected()
        // New device instance reports a fresh session
        frame(0.5, one); frame(0.05, [])
        XCTAssertEqual(poster.downs, 2)
        XCTAssertFalse(poster.buttonHeld)
    }

    func testDisconnectWithFingerDownDoesNotSynthesizeClickOnReconnect() {
        frame(0, one)
        controller.deviceDisconnected()
        frame(0.05, [])
        XCTAssertTrue(poster.events.isEmpty)
    }

    func testSleepReleasesButton() {
        dragStart()
        controller.systemWillSleep()
        XCTAssertFalse(poster.buttonHeld)
    }

    func testShutdownReleasesButtonAndIgnoresLaterInputAndEnable() {
        dragStart()
        controller.shutdown()
        XCTAssertFalse(poster.buttonHeld)
        let n = poster.events.count
        controller.setEnabled(true)
        frame(0.1, one); frame(0.05, [])
        XCTAssertEqual(poster.events.count, n)
        XCTAssertFalse(controller.isEnabled)
        controller.shutdown() // idempotent
    }

    func testPhysicalClickCoexistence() {
        // Physical press while a finger is down: no synthetic click is added on top.
        frame(0, one)
        physical = true; frame(0.03, one)
        physical = false; frame(0.03, [])
        XCTAssertTrue(poster.events.isEmpty)
        // The app's own held button is not mistaken for a physical press (drag continues).
        physical = true // would be reported by the OS for our own synthetic button
        frame(0.3, three); frame(0.05, three)   // physical press blocks drag start
        XCTAssertFalse(controller.isMouseHeld)
        frame(0.01, [])
        physical = false
        dragStart()
        physical = true // OS now reports button state because of OUR synthetic down
        cursor.x += 12; frame(0.011, three)
        XCTAssertTrue(controller.isMouseHeld, "own synthetic button must not abort the drag")
        frame(0.01, [])
        XCTAssertFalse(controller.isMouseHeld)
    }

    func testDragLockTimerIsOneShotAndReleases() {
        controller = make { $0.dragLockEnabled = true; $0.dragLockTimeout = 0.7 }
        controller.setEnabled(true)
        dragStart()
        frame(0.01, [])
        XCTAssertTrue(poster.buttonHeld, "held through the lock window")
        XCTAssertEqual(timer.scheduled, [0.7])
        timer.fire?()
        XCTAssertFalse(poster.buttonHeld)
    }

    func testDisablingDragLockInSettingsReleasesHeldButton() {
        var c = GestureConfig(); c.dragLockEnabled = true
        controller.updateConfig(c)
        dragStart(); frame(0.01, [])
        XCTAssertTrue(poster.buttonHeld)
        c.dragLockEnabled = false
        controller.updateConfig(c)
        XCTAssertFalse(poster.buttonHeld)
    }

    func testRepeatedEnableToggleIsStable() {
        for _ in 0..<50 { controller.setEnabled(false); controller.setEnabled(true) }
        frame(0, one); frame(0.05, [])
        XCTAssertEqual(poster.downs, 1)
        XCTAssertEqual(poster.ups, 1)
    }

    func testAbiFaultDisablesHandlingAfterRepeatedGarbage() {
        var faulted = false
        controller.onABIFault = { faulted = true }
        var junk = [UInt8](repeating: 0xFF, count: MTLayout.stride)
        for _ in 0..<5 {
            junk.withUnsafeMutableBytes { controller.handleRawFrame($0.baseAddress, count: 1, timestamp: 1) }
        }
        XCTAssertTrue(faulted)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertTrue(poster.events.isEmpty)
    }

    func testRawFrameEndToEndTap() {
        func rec(_ id: Int32, _ x: Float) -> [UInt8] {
            var b = [UInt8](repeating: 0, count: MTLayout.stride)
            b.withUnsafeMutableBytes { p in
                p.storeBytes(of: id, toByteOffset: MTLayout.identifierOffset, as: Int32.self)
                p.storeBytes(of: Int32(4), toByteOffset: MTLayout.stageOffset, as: Int32.self)
                p.storeBytes(of: x, toByteOffset: MTLayout.xOffset, as: Float.self)
                p.storeBytes(of: Float(0.5), toByteOffset: MTLayout.yOffset, as: Float.self)
            }
            return b
        }
        var a = rec(1, 0.4) + rec(2, 0.6)
        a.withUnsafeMutableBytes { controller.handleRawFrame($0.baseAddress, count: 2, timestamp: 50.0) }
        a.withUnsafeMutableBytes { controller.handleRawFrame($0.baseAddress, count: 2, timestamp: 50.04) }
        controller.handleRawFrame(nil, count: 0, timestamp: 50.08)
        XCTAssertEqual(poster.events.map(\.button), [.right, .right])
    }
}
