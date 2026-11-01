import CoreGraphics
import XCTest
@testable import MagicMouseTapCore

/// Drives the engine with simulated touch frames. Time only advances through `frame`.
final class Rig {
    let engine: GestureEngine
    var actions: [GestureAction] = []
    var t = 100.0
    var cursor = CGPoint(x: 500, y: 400)
    var physicalDown = false

    init(_ configure: (inout GestureConfig) -> Void = { _ in }) {
        var c = GestureConfig()
        configure(&c)
        engine = GestureEngine(config: c)
        engine.onAction = { [unowned self] in self.actions.append($0) }
    }

    func frame(after dt: Double, _ contacts: [Contact]) {
        t += dt
        engine.process(timestamp: t, contacts: contacts, cursor: cursor, physicalButtonDown: physicalDown)
    }

    func lift(after dt: Double = 0.01) { frame(after: dt, []) }

    var clicks: [GestureAction] {
        actions.filter { if case .click = $0 { return true } else { return false } }
    }
    func clicks(of b: MouseButton) -> Int {
        actions.filter { if case let .click(x, _, _) = $0 { return x == b } else { return false } }.count
    }
    var begins: Int { actions.filter { if case .dragBegin = $0 { return true } else { return false } }.count }
    var ends: Int { actions.filter { if case .dragEnd = $0 { return true } else { return false } }.count }
    var moves: Int { actions.filter { if case .dragMove = $0 { return true } else { return false } }.count }
}

func f(_ id: Int32, _ x: Float = 0.5, _ y: Float = 0.5) -> Contact { Contact(id: id, x: x, y: y) }

// Convenient finger sets (distinct, inside the edge inset)
let one = [f(1, 0.40, 0.5)]
let two = [f(1, 0.40, 0.5), f(2, 0.55, 0.5)]
let three = [f(1, 0.35, 0.5), f(2, 0.50, 0.5), f(3, 0.65, 0.5)]

final class TapTests: XCTestCase {
    func testOneFingerTapIsExactlyOneLeftClick() {
        let r = Rig()
        r.frame(after: 0, one)
        r.frame(after: 0.03, one)
        XCTAssertTrue(r.actions.isEmpty, "nothing may be emitted while the finger is down")
        r.lift(after: 0.05)
        XCTAssertEqual(r.actions, [.click(.left, clickCount: 1, at: r.cursor)])
    }

    func testRestingFingerNeverClicksUntilLiftAndLongHoldNeverClicks() {
        let r = Rig()
        for _ in 0..<200 { r.frame(after: 0.01, one) } // 2 seconds resting
        XCTAssertTrue(r.actions.isEmpty)
        r.lift()
        XCTAssertTrue(r.actions.isEmpty, "a long rest is not a tap")
    }

    func testTwoFingerTapIsOneRightClickAndNoLeftClick() {
        let r = Rig()
        r.frame(after: 0, two)
        r.frame(after: 0.04, two)
        r.lift(after: 0.04)
        XCTAssertEqual(r.clicks(of: .right), 1)
        XCTAssertEqual(r.clicks(of: .left), 0)
        XCTAssertEqual(r.clicks.count, 1)
    }

    func testTwoFingerTapWithStaggeredLandingAndLift() {
        let r = Rig()
        r.frame(after: 0, [two[0]])           // first finger
        r.frame(after: 0.006, two)            // second 6 ms later
        r.frame(after: 0.05, two)
        r.frame(after: 0.02, [two[1]])        // fingers leave 20 ms apart
        r.lift(after: 0.01)
        XCTAssertEqual(r.clicks.count, 1)
        XCTAssertEqual(r.clicks(of: .right), 1)
    }

    func testThreeFingerTapIsOneMiddleClickOnly() {
        let r = Rig()
        r.frame(after: 0, [three[0]])
        r.frame(after: 0.008, [three[0], three[1]])
        r.frame(after: 0.008, three)
        r.frame(after: 0.05, three)
        r.frame(after: 0.01, [three[0], three[1]])
        r.frame(after: 0.01, [three[0]])
        r.lift(after: 0.01)
        XCTAssertEqual(r.clicks, [.click(.middle, clickCount: 1, at: r.cursor)])
        XCTAssertEqual(r.begins, 0)
    }

    func testLateThirdFingerIsARestingHandNotATap() {
        let r = Rig()
        r.frame(after: 0, two)
        r.frame(after: 0.05, two)
        r.frame(after: 0.07, three) // lands 120 ms after the first
        r.lift(after: 0.03)
        XCTAssertTrue(r.clicks.isEmpty)
    }

    func testTapThatIsTooSlowIsRejected() {
        let r = Rig()
        r.frame(after: 0, one)
        r.frame(after: 0.5, one)
        r.lift()
        XCTAssertTrue(r.clicks.isEmpty)
    }

    func testRelaxedSensitivityAcceptsSlowerTap() {
        let r = Rig { $0.tapSensitivity = 1.0 }
        r.frame(after: 0, one)
        r.frame(after: 0.3, one)
        r.lift(after: 0.05)
        XCTAssertEqual(r.clicks(of: .left), 1)
    }

    func testStrictSensitivityRejectsModerateTap() {
        let r = Rig { $0.tapSensitivity = 0 }
        r.frame(after: 0, one)
        r.frame(after: 0.25, one)
        r.lift(after: 0.01)
        XCTAssertTrue(r.clicks.isEmpty)
    }

    func testCursorMovementDuringOneFingerTouchCancelsTap() {
        let r = Rig()
        r.frame(after: 0, one)
        r.cursor.x += 30
        r.frame(after: 0.03, one)
        r.lift(after: 0.03)
        XCTAssertTrue(r.clicks.isEmpty)
    }

    func testDisabledGestureProducesNothing() {
        let r = Rig { $0.oneFingerTapEnabled = false }
        r.frame(after: 0, one); r.lift(after: 0.05)
        XCTAssertTrue(r.actions.isEmpty)
        let r2 = Rig { $0.twoFingerTapEnabled = false; $0.threeFingerTapEnabled = false }
        r2.frame(after: 0, two); r2.lift(after: 0.05)
        r2.frame(after: 0.5, three); r2.lift(after: 0.05)
        XCTAssertTrue(r2.actions.isEmpty)
    }

    func testEdgeContactsAreIgnored() {
        let r = Rig()
        let edge = [f(9, 0.005, 0.5)]
        r.frame(after: 0, edge); r.lift(after: 0.05)
        XCTAssertTrue(r.actions.isEmpty)
        // A gripping edge finger plus one real fingertip is still a one-finger tap.
        r.frame(after: 0.5, edge + one); r.lift(after: 0.05)
        XCTAssertEqual(r.clicks(of: .left), 1)
    }
}

final class ScrollRejectionTests: XCTestCase {
    func testTwoFingerScrollNeverClicks() {
        let r = Rig()
        r.frame(after: 0, two)
        var moving = two
        for i in 1...12 {
            moving = moving.map { f($0.id, $0.x, $0.y + 0.03) }
            r.frame(after: 0.012, moving)
            _ = i
        }
        r.lift(after: 0.01)
        XCTAssertTrue(r.clicks.isEmpty)
    }

    func testOneFingerSwipeNeverClicks() {
        let r = Rig()
        r.frame(after: 0, one)
        r.frame(after: 0.03, [f(1, 0.40, 0.65)])
        r.lift(after: 0.02)
        XCTAssertTrue(r.clicks.isEmpty)
    }

    func testScrollThenQuickTapOnNextSessionStillWorks() {
        let r = Rig()
        r.frame(after: 0, two)
        r.frame(after: 0.02, two.map { f($0.id, $0.x, $0.y + 0.2) })
        r.lift()
        XCTAssertTrue(r.clicks.isEmpty)
        r.frame(after: 0.2, one); r.lift(after: 0.04)
        XCTAssertEqual(r.clicks(of: .left), 1)
    }

    func testTwoFingerScrollEndingWithOneFingerLiftingFirstDoesNotLeftClick() {
        let r = Rig()
        r.frame(after: 0, two)
        r.frame(after: 0.02, two.map { f($0.id, $0.x, $0.y + 0.15) })
        r.frame(after: 0.02, [f(2, 0.55, 0.65)])   // one finger left
        r.lift(after: 0.02)
        XCTAssertTrue(r.clicks.isEmpty)
    }
}

final class DragTests: XCTestCase {
    private func startDrag(_ r: Rig, fingers: [Contact] = three) {
        r.frame(after: 0, fingers)
        r.frame(after: 0.02, fingers)
        r.frame(after: 0.02, fingers)
        r.cursor.x += 20
        r.frame(after: 0.012, fingers)
    }

    func testThreeFingerMoveStartsDragAndReleaseEndsIt() {
        let r = Rig()
        let start = r.cursor
        startDrag(r)
        XCTAssertEqual(r.begins, 1)
        XCTAssertEqual(r.actions.first, .dragBegin(at: start))
        for _ in 0..<5 { r.cursor.x += 10; r.frame(after: 0.011, three) }
        XCTAssertGreaterThanOrEqual(r.moves, 5)
        XCTAssertEqual(r.ends, 0)
        r.lift()
        XCTAssertEqual(r.ends, 1)
    }

    func testCompletedDragNeverProducesMiddleOrAnyOtherClick() {
        let r = Rig()
        startDrag(r)
        for _ in 0..<4 { r.cursor.y += 8; r.frame(after: 0.011, three) }
        // fingers lift one by one, a few ms apart
        r.frame(after: 0.01, [three[0], three[1]])
        r.frame(after: 0.01, [three[0]])
        r.lift(after: 0.01)
        XCTAssertTrue(r.clicks.isEmpty)
        XCTAssertEqual(r.begins, 1)
        XCTAssertEqual(r.ends, 1)
    }

    func testDragContinuesWhenFingerCountDropsAndEndsOnlyWhenAllLift() {
        let r = Rig()
        startDrag(r)
        r.frame(after: 0.01, two)
        r.cursor.x += 15; r.frame(after: 0.01, two)
        r.frame(after: 0.01, one)
        r.cursor.x += 15; r.frame(after: 0.01, one)
        XCTAssertEqual(r.ends, 0)
        XCTAssertGreaterThanOrEqual(r.moves, 3)
        r.lift()
        XCTAssertEqual(r.ends, 1)
        XCTAssertTrue(r.clicks.isEmpty)
    }

    func testDragNeedsDeliberateMovement() {
        let r = Rig()
        r.frame(after: 0, three)
        r.cursor.x += 5 // below the 6 pt activation threshold, but above the 4 pt tap tolerance
        r.frame(after: 0.05, three)
        r.frame(after: 0.05, three)
        XCTAssertEqual(r.begins, 0)
        r.lift()
        XCTAssertTrue(r.clicks.isEmpty, "moved cursor disqualifies the tap too")
    }

    func testThreeFingerTapWithTinyJitterStillMiddleClicksNotDrag() {
        let r = Rig()
        r.frame(after: 0, three)
        r.cursor.x += 2
        r.frame(after: 0.05, three)
        r.lift(after: 0.04)
        XCTAssertEqual(r.begins, 0)
        XCTAssertEqual(r.clicks(of: .middle), 1)
    }

    func testDragRequiresThreeFingersStable() {
        let r = Rig()
        r.frame(after: 0, two)
        r.cursor.x += 40
        r.frame(after: 0.05, two) // two fingers + mouse motion = just moving the mouse
        XCTAssertEqual(r.begins, 0)
        r.lift()
        XCTAssertTrue(r.actions.isEmpty)
    }

    func testDragDisabledMeansNoDragAndNoClick() {
        let r = Rig { $0.threeFingerDragEnabled = false }
        startDrag(r)
        r.lift()
        XCTAssertTrue(r.actions.isEmpty)
    }

    func testPhysicalClickBlocksDragStart() {
        let r = Rig()
        r.physicalDown = true
        startDrag(r)
        XCTAssertEqual(r.begins, 0)
    }

    func testHoldActivationIsClampedAboveTapDuration() {
        var c = GestureConfig()
        c.dragHoldTime = 0.05
        XCTAssertGreaterThan(c.effectiveDragHoldTime, c.maxTapDuration)
        let r = Rig { $0.dragHoldTime = 0.05 }
        r.frame(after: 0, three)
        r.frame(after: 0.2, three)
        XCTAssertEqual(r.begins, 0, "still within quick-tap time")
        r.frame(after: 0.2, three) // 0.4 s > clamped hold
        XCTAssertEqual(r.begins, 1)
        r.lift()
        XCTAssertEqual(r.ends, 1)
        XCTAssertTrue(r.clicks.isEmpty)
    }

    func testBackToBackDragsAreIndependent() {
        let r = Rig()
        startDrag(r); r.lift()
        startDrag(r); r.lift()
        XCTAssertEqual(r.begins, 2)
        XCTAssertEqual(r.ends, 2)
        XCTAssertTrue(r.clicks.isEmpty)
    }

    func testDragLockHoldsUntilTimerThenReleases() {
        let r = Rig { $0.dragLockEnabled = true; $0.dragLockTimeout = 1 }
        startDrag(r)
        r.lift()
        XCTAssertEqual(r.ends, 0)
        XCTAssertTrue(r.actions.contains(.startDragLockTimer(seconds: 1)))
        r.engine.dragLockTimerFired(cursor: r.cursor)
        XCTAssertEqual(r.ends, 1)
        // A late duplicate timer fire is harmless.
        r.engine.dragLockTimerFired(cursor: r.cursor)
        XCTAssertEqual(r.ends, 1)
    }

    func testDragLockResumesWhenFingersReturnInTime() {
        let r = Rig { $0.dragLockEnabled = true }
        startDrag(r)
        r.lift()
        r.frame(after: 0.3, one)
        XCTAssertTrue(r.actions.contains(.cancelDragLockTimer))
        XCTAssertEqual(r.ends, 0)
        r.cursor.x += 25; r.frame(after: 0.011, one)
        r.lift()
        XCTAssertEqual(r.begins, 1, "same drag continued, not a new press")
        XCTAssertTrue(r.clicks.isEmpty)
        XCTAssertTrue(r.actions.contains(.startDragLockTimer(seconds: 1)))
    }
}

final class DoubleClickTests: XCTestCase {
    private func tap(_ r: Rig, gap: Double) {
        r.frame(after: gap, one); r.lift(after: 0.04)
    }

    func testTwoQuickTapsGiveClickCountOneThenTwo() {
        let r = Rig()
        tap(r, gap: 0); tap(r, gap: 0.12)
        XCTAssertEqual(r.clicks, [.click(.left, clickCount: 1, at: r.cursor), .click(.left, clickCount: 2, at: r.cursor)])
    }

    func testSlowSecondTapIsASeparateSingleClick() {
        let r = Rig()
        tap(r, gap: 0); tap(r, gap: 0.8)
        XCTAssertEqual(r.clicks.compactMap { if case let .click(_, c, _) = $0 { return c } else { return nil } }, [1, 1])
    }

    func testSecondTapAtDifferentSpotIsNotADoubleClick() {
        let r = Rig()
        tap(r, gap: 0)
        r.cursor.x += 200
        tap(r, gap: 0.1)
        XCTAssertEqual(r.clicks.compactMap { if case let .click(_, c, _) = $0 { return c } else { return nil } }, [1, 1])
    }

    func testTripleTapThenCountWrapsAround() {
        let r = Rig()
        for i in 0..<4 { tap(r, gap: i == 0 ? 0 : 0.1) }
        XCTAssertEqual(r.clicks.compactMap { if case let .click(_, c, _) = $0 { return c } else { return nil } }, [1, 2, 3, 1])
    }

    func testRightClickBetweenTapsBreaksTheDoubleClick() {
        let r = Rig()
        tap(r, gap: 0)
        r.frame(after: 0.1, two); r.lift(after: 0.04)
        tap(r, gap: 0.1)
        let counts = r.clicks.compactMap { if case let .click(b, c, _) = $0 { return b == .left ? c : nil } else { return nil } }
        XCTAssertEqual(counts, [1, 1])
    }

    func testRapidRepeatedTwoFingerTapsEachGiveOneRightClick() {
        let r = Rig()
        for i in 0..<5 { r.frame(after: i == 0 ? 0 : 0.05, two); r.lift(after: 0.04) }
        XCTAssertEqual(r.clicks(of: .right), 5)
        XCTAssertEqual(r.clicks(of: .left), 0)
    }
}

final class InterruptionTests: XCTestCase {
    func testCancelDuringDragReleasesOnceAndFingersMustLiftBeforeNextGesture() {
        let r = Rig()
        r.frame(after: 0, three); r.frame(after: 0.05, three)
        r.cursor.x += 30; r.frame(after: 0.011, three)
        XCTAssertEqual(r.begins, 1)
        r.engine.cancelAll(cursor: r.cursor)
        XCTAssertEqual(r.ends, 1)
        r.cursor.x += 30; r.frame(after: 0.011, three) // fingers still down: must not restart
        r.frame(after: 0.011, three)
        XCTAssertEqual(r.begins, 1)
        r.lift()
        XCTAssertEqual(r.ends, 1)
        XCTAssertTrue(r.clicks.isEmpty)
        // After everything lifted, normal operation resumes.
        r.frame(after: 0.3, one); r.lift(after: 0.04)
        XCTAssertEqual(r.clicks(of: .left), 1)
    }

    func testCancelWhileFingersRestingDoesNotCreateTap() {
        let r = Rig()
        r.frame(after: 0, one)
        r.engine.cancelAll(cursor: r.cursor)
        r.lift(after: 0.05)
        XCTAssertTrue(r.actions.isEmpty)
    }

    func testCancelDuringDragLockWaitCancelsTimerAndReleases() {
        let r = Rig { $0.dragLockEnabled = true }
        r.frame(after: 0, three); r.frame(after: 0.05, three)
        r.cursor.x += 30; r.frame(after: 0.011, three)
        r.lift()
        r.engine.cancelAll(cursor: r.cursor)
        XCTAssertEqual(r.ends, 1)
        XCTAssertTrue(r.actions.contains(.cancelDragLockTimer))
    }

    func testPhysicalClickDuringOneFingerTouchSuppressesTap() {
        let r = Rig()
        r.frame(after: 0, one)
        r.physicalDown = true
        r.frame(after: 0.03, one)
        r.physicalDown = false
        r.lift(after: 0.03)
        XCTAssertTrue(r.clicks.isEmpty)
    }

    func testPhysicalClickDuringTwoFingerTouchSuppressesTap() {
        let r = Rig()
        r.frame(after: 0, two)
        r.physicalDown = true
        r.frame(after: 0.03, two)
        r.physicalDown = false
        r.lift(after: 0.02)
        XCTAssertTrue(r.clicks.isEmpty)
    }

    func testPhysicalClickSeenOnlyOnTheLiftFrameSuppressesTap() {
        let r = Rig()
        r.frame(after: 0, one)
        r.frame(after: 0.03, one)
        r.physicalDown = true
        r.lift(after: 0.02)
        XCTAssertTrue(r.clicks.isEmpty)
    }

    func testSessionAfterPhysicalClickRecovers() {
        let r = Rig()
        r.frame(after: 0, one); r.physicalDown = true; r.frame(after: 0.03, one)
        r.physicalDown = false; r.lift()
        r.frame(after: 0.2, one); r.lift(after: 0.04)
        XCTAssertEqual(r.clicks(of: .left), 1)
    }

    func testEngineIgnoresHoveringAndEmptyFramesWhenIdle() {
        let r = Rig()
        for _ in 0..<100 { r.lift(after: 0.01) }
        XCTAssertTrue(r.actions.isEmpty)
        XCTAssertTrue(r.engine.isIdle)
    }
}

final class RawParserTests: XCTestCase {
    private func record(id: Int32, stage: Int32, x: Float, y: Float) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: MTLayout.stride)
        b.withUnsafeMutableBytes { p in
            p.storeBytes(of: id, toByteOffset: MTLayout.identifierOffset, as: Int32.self)
            p.storeBytes(of: stage, toByteOffset: MTLayout.stageOffset, as: Int32.self)
            p.storeBytes(of: x, toByteOffset: MTLayout.xOffset, as: Float.self)
            p.storeBytes(of: y, toByteOffset: MTLayout.yOffset, as: Float.self)
        }
        return b
    }

    func testLayoutConstantsMatchTheDocumentedMTTouchRecord() {
        XCTAssertEqual(MTLayout.stride, 96)
        XCTAssertEqual(MTLayout.identifierOffset, 16)
        XCTAssertEqual(MTLayout.stageOffset, 20)
        XCTAssertEqual(MTLayout.xOffset, 32)
        XCTAssertEqual(MTLayout.yOffset, 36)
    }

    func testParsesOnlyContactsThatAreDown() {
        let bytes = record(id: 7, stage: 4, x: 0.25, y: 0.75)
            + record(id: 8, stage: 2, x: 0.5, y: 0.5) // hovering
            + record(id: 9, stage: 3, x: 0.6, y: 0.1)
            + record(id: 10, stage: 7, x: 0.1, y: 0.1) // leaving
        var out: [Contact] = []
        let r = bytes.withUnsafeBytes { RawFrameParser.parse($0.baseAddress, count: 4, into: &out) }
        XCTAssertEqual(r, .ok)
        XCTAssertEqual(out, [Contact(id: 7, x: 0.25, y: 0.75), Contact(id: 9, x: 0.6, y: 0.1)])
    }

    func testZeroCountIsFineEvenWithNilPointer() {
        var out = [Contact(id: 1, x: 0, y: 0)]
        XCTAssertEqual(RawFrameParser.parse(nil, count: 0, into: &out), .ok)
        XCTAssertTrue(out.isEmpty)
    }

    func testRejectsGarbageAndAbsurdCounts() {
        var out: [Contact] = []
        let junk = record(id: 1, stage: 4, x: .nan, y: 0.5)
        XCTAssertEqual(junk.withUnsafeBytes { RawFrameParser.parse($0.baseAddress, count: 1, into: &out) }, .implausible)
        let offscreen = record(id: 1, stage: 4, x: 55, y: 0.5)
        XCTAssertEqual(offscreen.withUnsafeBytes { RawFrameParser.parse($0.baseAddress, count: 1, into: &out) }, .implausible)
        XCTAssertEqual(RawFrameParser.parse(nil, count: 3, into: &out), .implausible)
        XCTAssertEqual(junk.withUnsafeBytes { RawFrameParser.parse($0.baseAddress, count: 500, into: &out) }, .implausible)
        XCTAssertTrue(out.isEmpty)
    }
}
