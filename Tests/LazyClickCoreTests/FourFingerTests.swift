import CoreGraphics
import XCTest
@testable import LazyClickCore

let four = [f(1, 0.30, 0.5), f(2, 0.42, 0.5), f(3, 0.54, 0.5), f(4, 0.66, 0.5)]

final class FourFingerTests: XCTestCase {
    private func mission(_ r: Rig) -> Int { r.actions.filter { $0 == .missionControl }.count }

    func testFourFingersThenPointerUpFiresMissionControlOnce() {
        let r = Rig()
        r.frame(after: 0, four); r.frame(after: 0.05, four)
        for _ in 0..<6 { r.cursor.y -= 8; r.frame(after: 0.011, four) }
        r.lift(after: 0.02)
        XCTAssertEqual(mission(r), 1)
        XCTAssertEqual(r.begins, 0, "no drag")
        XCTAssertTrue(r.clicks.isEmpty, "no click")
    }

    func testFourFingerStaggeredLandingStillCounts() {
        let r = Rig()
        r.frame(after: 0, [four[0]]); r.frame(after: 0.01, Array(four[0...1]))
        r.frame(after: 0.01, Array(four[0...2])); r.frame(after: 0.01, four)
        r.cursor.y -= 40; r.frame(after: 0.2, four)
        r.lift()
        XCTAssertEqual(mission(r), 1)
        XCTAssertEqual(r.begins, 0)
    }

    func testFourFingersDownDoesNotFireWithoutMovement() {
        let r = Rig()
        r.frame(after: 0, four); r.frame(after: 0.1, four); r.frame(after: 0.1, four)
        r.lift(after: 0.02)
        XCTAssertEqual(mission(r), 0)
        XCTAssertTrue(r.actions.isEmpty, "four-finger tap does nothing")
    }

    func testPointerDownOrSidewaysDoesNotFire() {
        let down = Rig()
        down.frame(after: 0, four); down.cursor.y += 60; down.frame(after: 0.05, four); down.lift()
        XCTAssertEqual(mission(down), 0)

        let side = Rig()
        side.frame(after: 0, four); side.cursor.x += 80; side.cursor.y -= 30; side.frame(after: 0.05, four); side.lift()
        XCTAssertEqual(mission(side), 0)
    }

    func testSmallUpwardJitterDoesNotFire() {
        let r = Rig()
        r.frame(after: 0, four); r.cursor.y -= 10; r.frame(after: 0.05, four); r.lift()
        XCTAssertEqual(mission(r), 0)
    }

    func testFiresOnlyOncePerSessionAndAgainNextSession() {
        let r = Rig()
        r.frame(after: 0, four); r.cursor.y -= 30; r.frame(after: 0.05, four)
        r.cursor.y -= 60; r.frame(after: 0.05, four)
        r.lift()
        XCTAssertEqual(mission(r), 1)
        r.frame(after: 0.5, four); r.cursor.y -= 30; r.frame(after: 0.05, four); r.lift()
        XCTAssertEqual(mission(r), 2)
    }

    func testDisabledFallsBackToThreeFingerDrag() {
        let r = Rig { $0.fourFingerSwipeUpEnabled = false }
        r.frame(after: 0, four); r.frame(after: 0.05, four)
        r.cursor.x += 25; r.frame(after: 0.011, four)
        XCTAssertEqual(mission(r), 0)
        XCTAssertEqual(r.begins, 1, "with the feature off, behaviour is unchanged")
        r.lift()
        XCTAssertEqual(r.ends, 1)
    }

    func testThreeFingerDragStillWorksWhenFeatureEnabled() {
        let r = Rig()
        r.frame(after: 0, three); r.frame(after: 0.15, three)
        r.cursor.x += 25; r.frame(after: 0.011, three)
        XCTAssertEqual(r.begins, 1)
        XCTAssertEqual(mission(r), 0)
        r.lift()
        XCTAssertEqual(r.ends, 1)
    }

    func testThreeFingerTapStillMiddleClick() {
        let r = Rig()
        r.frame(after: 0, three); r.frame(after: 0.05, three); r.lift(after: 0.03)
        XCTAssertEqual(r.clicks(of: .middle), 1)
    }

    func testPhysicalClickDuringFourFingersCancels() {
        let r = Rig()
        r.frame(after: 0, four); r.physicalDown = true; r.cursor.y -= 50; r.frame(after: 0.05, four); r.lift()
        XCTAssertEqual(mission(r), 0)
    }
}
