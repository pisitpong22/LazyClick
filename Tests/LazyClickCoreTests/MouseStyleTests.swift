import CoreGraphics
import XCTest
@testable import LazyClickCore

private let leftFinger = [f(1, 0.30, 0.5)]
private let rightFinger = [f(1, 0.70, 0.5)]

final class MouseStyleTests: XCTestCase {
    private func rig(_ tweak: (inout GestureConfig) -> Void = { _ in }) -> Rig {
        Rig { $0.style = .mouse; tweak(&$0) }
    }
    private func tap(_ r: Rig, _ c: [Contact]) { r.frame(after: 0.3, c); r.frame(after: 0.05, c); r.lift(after: 0.03) }

    func testLeftHalfTapIsLeftClick() {
        let r = rig(); tap(r, leftFinger)
        XCTAssertEqual(r.actions, [.click(.left, clickCount: 1, at: r.cursor)])
    }

    func testRightHalfTapIsRightClick() {
        let r = rig(); tap(r, rightFinger)
        XCTAssertEqual(r.actions, [.click(.right, clickCount: 1, at: r.cursor)])
    }

    func testSwapSidesMirrorsTheHalves() {
        let r = rig { $0.swapSides = true }
        tap(r, leftFinger)
        XCTAssertEqual(r.clicks(of: .right), 1)
        XCTAssertEqual(r.clicks(of: .left), 0)
    }

    func testSideTogglesDisableEachClick() {
        let a = rig { $0.leftSideTapEnabled = false }; tap(a, leftFinger)
        XCTAssertTrue(a.actions.isEmpty)
        let b = rig { $0.rightSideTapEnabled = false }; tap(b, rightFinger)
        XCTAssertTrue(b.actions.isEmpty)
    }

    func testMultiFingerTapsDoNothingInMouseStyle() {
        let two = rig(); tap(two, [f(1, 0.30, 0.5), f(2, 0.70, 0.5)])
        XCTAssertTrue(two.actions.isEmpty)
        let three = rig(); tap(three, [f(1, 0.30, 0.5), f(2, 0.50, 0.5), f(3, 0.70, 0.5)])
        XCTAssertTrue(three.actions.isEmpty)
    }

    func testThreeFingerDragIsOffInMouseStyle() {
        let r = rig()
        r.frame(after: 0, [f(1, 0.30, 0.5), f(2, 0.50, 0.5), f(3, 0.70, 0.5)])
        r.frame(after: 0.2, [f(1, 0.30, 0.5), f(2, 0.50, 0.5), f(3, 0.70, 0.5)])
        r.cursor.x += 40; r.frame(after: 0.011, [f(1, 0.30, 0.5), f(2, 0.50, 0.5), f(3, 0.70, 0.5)])
        r.lift()
        XCTAssertEqual(r.begins, 0)
    }

    func testQuickDoubleTapLeftIsDoubleClickNotDrag() {
        let r = rig()
        tap(r, leftFinger)
        r.frame(after: 0.1, leftFinger); r.frame(after: 0.04, leftFinger); r.lift(after: 0.03)
        XCTAssertEqual(r.clicks.count, 2)
        XCTAssertEqual(r.actions.last, .click(.left, clickCount: 2, at: r.cursor))
        XCTAssertEqual(r.begins, 0)
    }

    func testTapThenTouchAndMovePointerDragsAndReleasesOnLift() {
        let r = rig()
        tap(r, leftFinger)
        let start = r.cursor
        r.frame(after: 0.1, leftFinger)
        r.frame(after: 0.1, leftFinger)               // held longer than a tap
        for _ in 0..<5 { r.cursor.x += 10; r.frame(after: 0.011, leftFinger) }
        XCTAssertEqual(r.begins, 1)
        XCTAssertTrue(r.actions.contains(.dragBegin(at: start)))
        XCTAssertGreaterThanOrEqual(r.moves, 4)
        XCTAssertEqual(r.ends, 0)
        r.lift()
        XCTAssertEqual(r.ends, 1)
        XCTAssertEqual(r.clicks.count, 1, "only the first tap clicked")
    }

    func testDragMayStartRightAfterSecondTouchLands() {
        let r = rig()
        tap(r, leftFinger)
        r.frame(after: 0.1, leftFinger)
        r.cursor.x += 20; r.frame(after: 0.05, leftFinger)
        XCTAssertEqual(r.begins, 1)
        r.lift()
        XCTAssertEqual(r.ends, 1)
    }

    func testMovingPointerWithoutPriorTapNeverDrags() {
        let r = rig()
        r.frame(after: 0, leftFinger); r.frame(after: 0.1, leftFinger)
        for _ in 0..<5 { r.cursor.x += 10; r.frame(after: 0.011, leftFinger) }
        r.lift()
        XCTAssertEqual(r.begins, 0)
        XCTAssertTrue(r.clicks.isEmpty)
    }

    func testSecondTouchTooLateDoesNotDrag() {
        let r = rig()
        tap(r, leftFinger)
        r.frame(after: 0.8, leftFinger)
        r.cursor.x += 30; r.frame(after: 0.05, leftFinger)
        r.lift()
        XCTAssertEqual(r.begins, 0)
    }

    func testRightTapThenTouchDoesNotDrag() {
        let r = rig()
        tap(r, rightFinger)
        r.frame(after: 0.1, rightFinger)
        r.cursor.x += 30; r.frame(after: 0.05, rightFinger)
        r.lift()
        XCTAssertEqual(r.begins, 0)
    }

    func testFingerSlidingAfterTapIsScrollNotDrag() {
        let r = rig()
        tap(r, leftFinger)
        r.frame(after: 0.1, leftFinger)
        r.frame(after: 0.05, [f(1, 0.30, 0.75)])      // finger slides along the surface
        r.cursor.x += 30; r.frame(after: 0.05, [f(1, 0.30, 0.80)])
        r.lift()
        XCTAssertEqual(r.begins, 0)
    }

    func testFingertipShiftWhilePushingMouseStillDrags() {
        let r = rig()
        tap(r, leftFinger)
        r.frame(after: 0.1, leftFinger)
        r.cursor.x += 5; r.frame(after: 0.02, leftFinger)
        // the push rolls the fingertip past the tap tolerance while the pointer travels
        r.cursor.x += 10; r.frame(after: 0.02, [f(1, 0.30, 0.60)])
        XCTAssertEqual(r.begins, 1)
        r.lift()
        XCTAssertEqual(r.ends, 1)
    }

    func testQuickTapThenImmediateDragWithoutPause() {
        let r = rig()
        tap(r, leftFinger)
        r.cursor.x += 30                                // pointer already moving as the finger lands
        r.frame(after: 0.1, leftFinger)
        r.cursor.x += 10; r.frame(after: 0.04, leftFinger)
        XCTAssertEqual(r.begins, 1)
        r.lift()
        XCTAssertEqual(r.ends, 1)
        XCTAssertEqual(r.clicks.count, 1)
    }

    func testTapDragDisabled() {
        let r = rig { $0.tapDragEnabled = false }
        tap(r, leftFinger)
        r.frame(after: 0.1, leftFinger)
        r.cursor.x += 30; r.frame(after: 0.05, leftFinger)
        r.lift()
        XCTAssertEqual(r.begins, 0)
    }

    func testPhysicalClickDuringArmedTouchCancelsDrag() {
        let r = rig()
        tap(r, leftFinger)
        r.frame(after: 0.1, leftFinger)
        r.physicalDown = true
        r.cursor.x += 30; r.frame(after: 0.05, leftFinger)
        r.lift()
        XCTAssertEqual(r.begins, 0)
    }

    func testTrackpadStyleUnchangedByDefault() {
        XCTAssertEqual(GestureConfig().style, .trackpad)
    }
}
