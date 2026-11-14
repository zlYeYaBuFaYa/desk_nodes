import XCTest
import DeskNodesCore
import DeskNodesPersistence
@testable import DeskNodesActions

final class ToolbarGeometryTests: XCTestCase {
    private let main = DockScreen(id: "main", visible: NoteFrame(x: 0, y: 0, width: 1440, height: 875))
    private let side = DockScreen(id: "side", visible: NoteFrame(x: 1440, y: 0, width: 1000, height: 700))
    private let gap = ToolbarMetrics.edgeGap
    private let d = ToolbarMetrics.entrySize

    private func contains(_ outer: NoteFrame, _ inner: NoteFrame) -> Bool {
        inner.x >= outer.x - 0.001 && inner.y >= outer.y - 0.001
            && inner.x + inner.width <= outer.x + outer.width + 0.001 && inner.y + inner.height <= outer.y + outer.height + 0.001
    }

    func testDroppedEntryStaysPutAndTheCapsuleUnfoldsFromItsGripEnd() throws {
        // An entry dropped near the top of the left edge: no jump, the capsule hangs below it.
        let entry = NoteFrame(x: 10, y: 780, width: d, height: d)
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
        let entry = NoteFrame(x: 10, y: 20, width: d, height: d)
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
        let edge = NoteFrame(x: ToolbarMetrics.snapDistance, y: 300, width: 64, height: 400)
        XCTAssertEqual(ToolbarGeometry.snapEdge(edge, screen: main, screens: [main], orientation: .vertical, paged: false, previous: nil), .left)
        let far = NoteFrame(x: ToolbarMetrics.snapDistance + 1, y: 300, width: 64, height: 400)
        XCTAssertNil(ToolbarGeometry.snapEdge(far, screen: main, screens: [main], orientation: .vertical, paged: false, previous: nil))
        // The right edge of `main` continues into `side`: a seam, not an edge.
        let atSeam = NoteFrame(x: 1440 - 70, y: 300, width: 64, height: 400)
        XCTAssertNil(ToolbarGeometry.snapEdge(atSeam, screen: main, screens: [main, side], orientation: .vertical, paged: false, previous: nil))
        XCTAssertEqual(ToolbarGeometry.snapEdge(atSeam, screen: main, screens: [main], orientation: .vertical, paged: false, previous: nil), .right)
        // A corner at equal distance keeps the previous edge, else left before top.
        let corner = NoteFrame(x: 10, y: 875 - 10 - d, width: d, height: d)
        XCTAssertEqual(ToolbarGeometry.snapEdge(corner, screen: main, screens: [main], orientation: .vertical, paged: false, previous: .top), .top)
        XCTAssertEqual(ToolbarGeometry.snapEdge(corner, screen: main, screens: [main], orientation: .vertical, paged: false, previous: nil), .left)
    }

    func testFreeReleaseUnfoldsFromTheDroppedEntryAndStaysOnScreen() throws {
        let entry = NoteFrame(x: 600, y: 700, width: d, height: d)
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

    func testArrangementAvoidsAHorizontalToolbarRow() {
        let row = NoteFrame(x: gap, y: 875 - gap - 64, width: ToolbarMetrics.length(horizontal: true, paged: false), height: 64)
        let area = Arrangement.area(main, avoiding: row)
        XCTAssertLessThanOrEqual(area.y + area.height, row.y - ArrangeMetrics.gap + 0.001, "cards go below the row, not beside it")
        XCTAssertEqual(area.width, 1440 - ArrangeMetrics.margin * 2)
    }

    // MARK: Home

    func testStandardHomeIsOnTheRightALittleBelowTheMiddle() throws {
        let anchor = ToolbarGeometry.anchor(home: .standard, screen: main)
        XCTAssertEqual(anchor.edge, .right)
        let frames = try XCTUnwrap(ToolbarGeometry.resolve(anchor, orientation: .vertical, paged: false, screens: [main]))
        let entry = try XCTUnwrap(frames.circle)
        XCTAssertEqual(entry.x + entry.width, 1440 - gap)
        XCTAssertEqual(entry.width, d)
        let fromTop = (875 - (entry.y + d / 2)) / 875
        XCTAssertTrue((0.5...0.7).contains(fromTop), "\(fromTop)")
        // The column hangs from the entry and stays on screen.
        XCTAssertEqual(frames.target.y + frames.target.height, entry.y + entry.height, accuracy: 0.001)
        XCTAssertTrue(contains(main.visible, frames.target))
    }

    func testHomeKeepsItsHitZoneClearOfTheCorners() {
        for ratio in [0.0, 1.0] {
            let zone = ToolbarGeometry.homeZone(ToolbarHome(edge: .right, ratio: ratio), screen: main)
            XCTAssertEqual(zone.x + zone.width, 1440, "the zone reaches the edge")
            XCTAssertGreaterThanOrEqual(zone.y, ToolbarMetrics.homeCornerClearance)
            XCTAssertLessThanOrEqual(zone.y + zone.height, 875 - ToolbarMetrics.homeCornerClearance)
        }
    }

    func testDroppedEntryTakesTheNearestOuterEdgeWhereItWasDropped() {
        let home = ToolbarGeometry.home(at: (1400, 600), screen: main, screens: [main])
        XCTAssertEqual(home.edge, .right)
        // The zone it resolves to sits where the entry was dropped.
        let zone = ToolbarGeometry.homeZone(home, screen: main)
        XCTAssertEqual(zone.y + zone.height / 2, 600, accuracy: 0.001)
        // A seam is no edge: next to `side`, the nearest outer edge wins instead.
        XCTAssertEqual(ToolbarGeometry.home(at: (1420, 300), screen: main, screens: [main, side]).edge, .bottom)
        // Dropped in a corner: clamped to the clearance, never into the corner.
        let corner = ToolbarGeometry.home(at: (1430, 10), screen: main, screens: [main])
        XCTAssertEqual(corner.ratio, 0)
    }

    func testAHomeOnASeamMovesToTheOppositeOuterEdge() {
        // `main` continues into `side` on its right: no stopping edge there.
        let home = ToolbarHome(edge: .right, ratio: 0.4)
        XCTAssertEqual(ToolbarGeometry.home(home, on: main, among: [main, side]), ToolbarHome(edge: .left, ratio: 0.4))
        XCTAssertEqual(ToolbarGeometry.home(home, on: side, among: [main, side]), home, "an outer edge stays")
        XCTAssertEqual(ToolbarGeometry.home(home, on: main, among: [main]), home)
    }

    func testStripsKeepToTheLongerStretchBesideTheHomeZone() {
        let low = ToolbarGeometry.homeZone(.standard, screen: main)
        let right = DockGeometry.region(main, edge: .right, avoiding: low)
        XCTAssertGreaterThanOrEqual(right.visible.y, low.y + low.height, "above the zone, the longer stretch")
        XCTAssertEqual(right.visible.x, main.visible.x)
        XCTAssertEqual(DockGeometry.region(main, edge: .left, avoiding: low), main, "a strip on the far edge is untouched")
        let high = ToolbarGeometry.homeZone(ToolbarHome(edge: .right, ratio: 0.9), screen: main)
        let below = DockGeometry.region(main, edge: .right, avoiding: high)
        XCTAssertLessThanOrEqual(below.visible.y + below.visible.height, high.y)
        let top = ToolbarGeometry.homeZone(ToolbarHome(edge: .top, ratio: 0.1), screen: main)
        XCTAssertGreaterThanOrEqual(DockGeometry.region(main, edge: .top, avoiding: top).visible.x, top.x + top.width)
    }
}
