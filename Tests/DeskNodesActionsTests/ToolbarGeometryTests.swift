import XCTest
import DeskNodesCore
import DeskNodesPersistence
@testable import DeskNodesActions

final class ToolbarGeometryTests: XCTestCase {
    private let main = DockScreen(id: "main", visible: NoteFrame(x: 0, y: 0, width: 1440, height: 875))
    private let side = DockScreen(id: "side", visible: NoteFrame(x: 1440, y: 0, width: 1000, height: 700))
    private let gap = ToolbarMetrics.edgeGap

    private func contains(_ outer: NoteFrame, _ inner: NoteFrame) -> Bool {
        inner.x >= outer.x - 0.001 && inner.y >= outer.y - 0.001
            && inner.x + inner.width <= outer.x + outer.width + 0.001 && inner.y + inner.height <= outer.y + outer.height + 0.001
    }

    func testDroppedEntryStaysPutAndTheCapsuleUnfoldsFromItsGripEnd() throws {
        // An entry dropped near the top of the left edge: no jump, the capsule hangs below it.
        let entry = NoteFrame(x: 10, y: 780, width: 48, height: 48)
        let (anchor, frames) = try XCTUnwrap(ToolbarGeometry.release(entry, round: true, pointer: (30, 800), last: nil, previous: nil,
                                                                      orientation: .vertical, paged: false, screens: [main]))
        XCTAssertEqual(anchor.edge, .left)
        let circle = try XCTUnwrap(frames.circle)
        XCTAssertEqual(circle.x, gap); XCTAssertEqual(circle.y, entry.y, accuracy: 0.001, "the entry stays where it was dropped")
        XCTAssertEqual(frames.target.x, gap)
        XCTAssertEqual(frames.target.y + frames.target.height, circle.y + circle.height, accuracy: 0.001, "grip end level with the entry")
        XCTAssertTrue(contains(frames.target, circle))
    }

    func testCapsuleSlidesAlongTheEdgeButStillCoversTheEntry() throws {
        let entry = NoteFrame(x: 10, y: 20, width: 48, height: 48)
        let (_, frames) = try XCTUnwrap(ToolbarGeometry.release(entry, round: true, pointer: (30, 40), last: nil, previous: nil,
                                                                 orientation: .vertical, paged: false, screens: [main]))
        let circle = try XCTUnwrap(frames.circle)
        XCTAssertEqual(frames.target.y, gap, "pushed up to fit above the bottom")
        XCTAssertTrue(contains(frames.target, circle))
        XCTAssertTrue(contains(main.visible, frames.target))
    }

    func testRepeatedResolveDoesNotDrift() throws {
        let anchor = ToolbarAnchor.snapped(.right, ratio: 0.37, display: nil)
        let a = try XCTUnwrap(ToolbarGeometry.resolve(anchor, orientation: .vertical, paged: false, screens: [main]))
        let b = try XCTUnwrap(ToolbarGeometry.resolve(anchor, orientation: .vertical, paged: false, screens: [main]))
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.target.x + a.target.width, main.visible.width - gap)
        // Releasing the expanded capsule where it rests keeps the same anchor.
        let (again, _) = try XCTUnwrap(ToolbarGeometry.release(a.target, round: false, pointer: (1400, 400), last: nil, previous: .right,
                                                                orientation: .vertical, paged: false, screens: [main]))
        guard case .snapped(.right, let ratio, _) = again else { return XCTFail("\(again)") }
        let c = try XCTUnwrap(ToolbarGeometry.resolve(.snapped(.right, ratio: ratio, display: nil), orientation: .vertical, paged: false, screens: [main]))
        XCTAssertEqual(c.target.y, a.target.y, accuracy: 0.001)
    }

    func testHorizontalAcrossASideEdgeUnfoldsInwardCentredOnTheEntry() throws {
        let frames = try XCTUnwrap(ToolbarGeometry.resolve(.snapped(.left, ratio: 0.5, display: nil), orientation: .horizontal,
                                                           paged: false, screens: [main]))
        let circle = try XCTUnwrap(frames.circle)
        XCTAssertEqual(frames.target.x, gap)
        XCTAssertEqual(frames.target.width, ToolbarMetrics.length(horizontal: true, paged: false))
        XCTAssertEqual(frames.target.y + frames.target.height / 2, circle.y + circle.height / 2, accuracy: 0.001)
    }

    func testSnapPicksTheNearestOuterEdgeAndIgnoresSeams() {
        let nearLeft = NoteFrame(x: 20, y: 300, width: 64, height: 400)
        XCTAssertEqual(ToolbarGeometry.snapEdge(nearLeft, screen: main, screens: [main], orientation: .vertical, paged: false, previous: nil), .left)
        let far = NoteFrame(x: 40, y: 300, width: 64, height: 400)
        XCTAssertNil(ToolbarGeometry.snapEdge(far, screen: main, screens: [main], orientation: .vertical, paged: false, previous: nil))
        // The right edge of `main` continues into `side`: a seam, not an edge.
        let atSeam = NoteFrame(x: 1440 - 70, y: 300, width: 64, height: 400)
        XCTAssertNil(ToolbarGeometry.snapEdge(atSeam, screen: main, screens: [main, side], orientation: .vertical, paged: false, previous: nil))
        XCTAssertEqual(ToolbarGeometry.snapEdge(atSeam, screen: main, screens: [main], orientation: .vertical, paged: false, previous: nil), .right)
        // A corner at equal distance keeps the previous edge, else left before top.
        let corner = NoteFrame(x: 10, y: 875 - 10 - 48, width: 48, height: 48)
        XCTAssertEqual(ToolbarGeometry.snapEdge(corner, screen: main, screens: [main], orientation: .vertical, paged: false, previous: .top), .top)
        XCTAssertEqual(ToolbarGeometry.snapEdge(corner, screen: main, screens: [main], orientation: .vertical, paged: false, previous: nil), .left)
    }

    func testFreeReleaseUnfoldsFromTheDroppedEntryAndStaysOnScreen() throws {
        let entry = NoteFrame(x: 600, y: 700, width: 48, height: 48)
        let (anchor, frames) = try XCTUnwrap(ToolbarGeometry.release(entry, round: true, pointer: (620, 720), last: nil, previous: nil,
                                                                      orientation: .vertical, paged: false, screens: [main]))
        XCTAssertNil(anchor.edge); XCTAssertNil(frames.circle)
        XCTAssertEqual(frames.target.y + frames.target.height, entry.y + entry.height, accuracy: 0.001)
        XCTAssertEqual(frames.target.x + frames.target.width / 2, entry.x + entry.width / 2, accuracy: 0.001)
        XCTAssertTrue(contains(main.visible, frames.target))
    }

    func testMissingDisplayFallsBackToPrimaryKeepingTheRatio() throws {
        let frames = try XCTUnwrap(ToolbarGeometry.resolve(.snapped(.bottom, ratio: 1, display: "gone"), orientation: .horizontal,
                                                           paged: true, screens: [main, side]))
        XCTAssertEqual(frames.screen.id, "main")
        XCTAssertEqual(frames.target.y, gap)
        XCTAssertEqual(frames.target.x + frames.target.width, main.visible.width - gap, accuracy: 0.001)
    }

    func testTinyDisplayShrinksTheLongSideToScroll() {
        let tiny = DockScreen(id: "tiny", visible: NoteFrame(x: 0, y: 0, width: 400, height: 300))
        let size = ToolbarGeometry.size(.vertical, paged: true, on: tiny)
        XCTAssertEqual(size.height, 300 - gap * 2)
        XCTAssertEqual(ToolbarGeometry.size(.vertical, paged: false, on: main).height, ToolbarMetrics.height(paged: false))
    }

    func testArrangementAndStripsAvoidAHorizontalToolbarRow() {
        let row = NoteFrame(x: gap, y: 875 - gap - 64, width: ToolbarMetrics.length(horizontal: true, paged: false), height: 64)
        let area = Arrangement.area(main, avoiding: row)
        XCTAssertLessThanOrEqual(area.y + area.height, row.y - ArrangeMetrics.gap + 0.001, "cards go below the row, not beside it")
        XCTAssertEqual(area.width, 1440 - ArrangeMetrics.margin * 2)
        let strip = DockGeometry.region(main, edge: .top, avoiding: row)
        XCTAssertLessThanOrEqual(strip.visible.y + strip.visible.height, row.y)
        let column = NoteFrame(x: gap, y: 200, width: 64, height: 400)
        let left = DockGeometry.region(main, edge: .left, avoiding: column)
        XCTAssertGreaterThanOrEqual(left.visible.x, column.x + column.width)
        XCTAssertEqual(DockGeometry.region(main, edge: .right, avoiding: column), main, "a strip on the far edge is untouched")
    }
}
