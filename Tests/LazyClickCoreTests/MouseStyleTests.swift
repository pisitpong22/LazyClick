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

    private func swipe(_ r: Rig, from x0: Float, to x1: Float, y1: Float = 0.5, step: Double = 0.05) {
        r.frame(after: 0.5, [f(1, x0, 0.5)])
        r.frame(after: step, [f(1, (x0 + x1) / 2, (0.5 + y1) / 2)])
        r.frame(after: step, [f(1, x1, y1)])
        r.lift()
    }

    func testSwipeLeftToRightGoesBackOnce() {
        let r = rig(); swipe(r, from: 0.3, to: 0.7)
        XCTAssertEqual(r.actions, [.navigate(back: true)])
    }

    func testSwipeRightToLeftGoesForward() {
        let r = rig(); swipe(r, from: 0.7, to: 0.3)
        XCTAssertEqual(r.actions, [.navigate(back: false)])
    }

    func testSwipeWorksInTrackpadStyle() {
        let r = Rig(); swipe(r, from: 0.3, to: 0.7)
        XCTAssertEqual(r.actions, [.navigate(back: true)])
    }

    func testSlowSideSlideIsScrollNotSwipe() {
        let r = rig(); swipe(r, from: 0.3, to: 0.7, step: 0.3)
        XCTAssertTrue(r.actions.isEmpty)
    }

    func testVerticalSlideIsNotSwipe() {
        let r = rig(); swipe(r, from: 0.3, to: 0.6, y1: 0.9)
        XCTAssertTrue(r.actions.isEmpty)
    }

    func testShortFlickIsNotSwipe() {
        let r = rig(); swipe(r, from: 0.4, to: 0.55)
        XCTAssertTrue(r.actions.isEmpty)
    }

    func testFingerRollWhileMovingMouseIsNotSwipe() {
        let r = rig()
        r.frame(after: 0.5, [f(1, 0.3, 0.5)])
        r.cursor.x += 20; r.frame(after: 0.05, [f(1, 0.7, 0.5)])
        r.lift()
        XCTAssertTrue(r.actions.isEmpty)
    }

    func testTwoFingerSlideIsNotSwipe() {
        let r = rig()
        r.frame(after: 0.5, [f(1, 0.3, 0.3), f(2, 0.3, 0.7)])
        r.frame(after: 0.05, [f(1, 0.7, 0.3), f(2, 0.7, 0.7)])
        r.lift()
        XCTAssertTrue(r.actions.isEmpty)
    }

    func testSwipeCanBeDisabled() {
        let r = rig { $0.swipeNavigationEnabled = false }; swipe(r, from: 0.3, to: 0.7)
        XCTAssertTrue(r.actions.isEmpty)
    }

    func testTrackpadStyleUnchangedByDefault() {
        XCTAssertEqual(GestureConfig().style, .trackpad)
    }
}
