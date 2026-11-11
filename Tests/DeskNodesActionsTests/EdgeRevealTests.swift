import XCTest
import DeskNodesPersistence
@testable import DeskNodesActions

final class EdgeRevealTests: XCTestCase {
    let target = RevealTarget(screen: "a", side: .right)
    func screen(_ id: String = "a", _ x: Double = 0, _ y: Double = 0, _ w: Double = 1000, _ h: Double = 1000) -> DockScreen {
        DockScreen(id: id, visible: NoteFrame(x: x, y: y, width: w, height: h))
    }
    func hit(_ x: Double, _ y: Double, _ screens: [DockScreen], _ side: RevealSide = .right) -> RevealTarget? {
        RevealGeometry.target(x: x, y: y, screens: screens, side: side)
    }
    func testMiddleSixtyAndCorners() {
        for y in [0.0, 199, 200, 800, 801, 1000] { XCTAssertNil(hit(999, y, [screen()])) }
        for y in [200.01, 500, 799.99] { XCTAssertEqual(hit(999, y, [screen()]), target) }
        XCTAssertNil(hit(997.99, 500, [screen()])); XCTAssertNil(hit(1000.01, 500, [screen()]))
        XCTAssertNotNil(hit(0, 500, [screen()], .left)); XCTAssertNil(hit(-0.01, 500, [screen()], .left))
    }
    func testNegativeCoordinatesAndBothOuterSides() {
        let s = screen("negative", -1000, -600)
        XCTAssertEqual(hit(-1, -100, [s])?.screen, "negative")
        XCTAssertNotNil(hit(-1000, -100, [s], .left))
        XCTAssertNil(hit(-1000, -400, [s], .left))
    }
    func testTouchingAndPartialSeamsIncludingEndpoints() {
        let screens = [screen(), screen("b", 1000, 400, 1000, 300)]
        for y in [400.0, 500, 700] { XCTAssertNil(hit(999, y, screens)) }
        XCTAssertNotNil(hit(999, 399, screens)); XCTAssertNotNil(hit(999, 701, screens))
        XCTAssertNil(hit(1000, 500, screens, .left))
        XCTAssertNotNil(hit(2000, 550, screens))
    }
    func testOverlappingMonitorAndGap() {
        XCTAssertNil(hit(999, 500, [screen(), screen("b", 800, 300, 600, 500)]))
        XCTAssertNotNil(hit(999, 500, [screen(), screen("b", 1001)]))
        XCTAssertNil(hit(.nan, 500, [screen()])); XCTAssertNil(hit(999, .infinity, [screen()]))
    }
    func testMirroredFramesAndDuplicateIDsFailClosed() {
        XCTAssertNil(hit(999, 500, [screen(), screen("mirror")]))
        XCTAssertNil(hit(0, 500, [screen(), screen()], .left))
        XCTAssertNil(hit(999, 500, [screen(), screen("a", 1000)]))
    }
    func testAutomaticAndManualPreference() {
        for dock in [nil, "bottom", "left", "unexpected"] { XCTAssertEqual(EdgePreference.automatic.resolved(dock: dock), .right) }
        XCTAssertEqual(EdgePreference.automatic.resolved(dock: "right"), .left)
        for dock in [nil, "bottom", "left", "right"] {
            XCTAssertEqual(EdgePreference.left.resolved(dock: dock), .left)
            XCTAssertEqual(EdgePreference.right.resolved(dock: dock), .right)
        }
    }
    func testExactDwellAndExitThresholds() {
        var s = RevealTiming()
        XCTAssertNil(s.sample(time: 0, target: target, inside: false, editing: false))
        XCTAssertNil(s.sample(time: 0.249, target: target, inside: false, editing: false))
        XCTAssertEqual(s.sample(time: 0.25, target: target, inside: false, editing: false), target)
        XCTAssertEqual(s.sample(time: 1, target: nil, inside: false, editing: false), target)
        XCTAssertEqual(s.sample(time: 1.399, target: nil, inside: false, editing: false), target)
        XCTAssertNil(s.sample(time: 1.4, target: nil, inside: false, editing: false))
    }
    func testReentryAndMovingDownInsideNeverDismiss() {
        var s = RevealTiming()
        _ = s.sample(time: 0, target: target, inside: false, editing: false)
        _ = s.sample(time: 0.25, target: target, inside: false, editing: false)
        _ = s.sample(time: 1, target: nil, inside: false, editing: false)
        for t in [1.3, 2, 3, 4] { XCTAssertEqual(s.sample(time: t, target: nil, inside: true, editing: false), target) }
        _ = s.sample(time: 5, target: nil, inside: false, editing: false)
        XCTAssertEqual(s.sample(time: 5.3, target: target, inside: false, editing: false), target)
        XCTAssertEqual(s.sample(time: 6, target: nil, inside: false, editing: true), target)
        XCTAssertEqual(s.sample(time: 9, target: nil, inside: false, editing: true), target)
    }
    func testInterruptedDwellAndDifferentScreen() {
        var s = RevealTiming(); let other = RevealTarget(screen: "b", side: .right)
        _ = s.sample(time: 0, target: target, inside: false, editing: false)
        _ = s.sample(time: 0.2, target: nil, inside: false, editing: false)
        _ = s.sample(time: 1, target: target, inside: false, editing: false)
        XCTAssertNil(s.sample(time: 1.2, target: other, inside: false, editing: false))
        XCTAssertNil(s.sample(time: 1.44, target: other, inside: false, editing: false))
        XCTAssertEqual(s.sample(time: 1.45, target: other, inside: false, editing: false), other)
    }
    func testRapidCyclesAndClockReversal() {
        var s = RevealTiming()
        for index in 0..<50 {
            let t = Double(index * 4)
            XCTAssertNil(s.sample(time: t, target: target, inside: false, editing: false))
            XCTAssertEqual(s.sample(time: t + 0.25, target: target, inside: false, editing: false), target)
            _ = s.sample(time: t + 1, target: nil, inside: false, editing: false)
            XCTAssertNil(s.sample(time: t + 1.5, target: nil, inside: false, editing: false))
        }
        s.reset(); _ = s.sample(time: 10, target: target, inside: false, editing: false)
        XCTAssertNil(s.sample(time: 9, target: target, inside: false, editing: false))
        XCTAssertNil(s.sample(time: 9.24, target: target, inside: false, editing: false))
        XCTAssertEqual(s.sample(time: 9.25, target: target, inside: false, editing: false), target)
        _ = s.sample(time: 10, target: nil, inside: false, editing: false)
        XCTAssertEqual(s.sample(time: 8, target: nil, inside: false, editing: false), target)
        XCTAssertEqual(s.sample(time: .nan, target: nil, inside: false, editing: false), target)
        XCTAssertEqual(s.sample(time: 20, target: nil, inside: false, editing: false), target)
        XCTAssertNil(s.sample(time: 20.5, target: nil, inside: false, editing: false))
    }
    func testPassiveStaleCopyCannotFlushOrReplaceActiveComposition() {
        for active in [false, true] { for marked in [false, true] {
            XCTAssertEqual(EditorSynchronization.flush(local: "old", committed: "new", active: active, marked: marked), active && !marked)
            XCTAssertEqual(EditorSynchronization.receive(local: "old", committed: "new", active: active, marked: marked), !active && !marked)
            XCTAssertFalse(EditorSynchronization.flush(local: "same", committed: "same", active: active, marked: marked))
        } }
    }
}
