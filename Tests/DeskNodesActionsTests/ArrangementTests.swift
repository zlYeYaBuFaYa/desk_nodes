import XCTest
import Foundation
import DeskNodesCore
import DeskNodesPersistence
@testable import DeskNodesActions

final class ArrangementTests: XCTestCase {
    private let main = DockScreen(id: "main", visible: NoteFrame(x: 0, y: 0, width: 1440, height: 875))
    private let side = DockScreen(id: "side", visible: NoteFrame(x: 1440, y: -200, width: 1000, height: 700))
    private let toolbar = NoteFrame(x: 20, y: 500, width: 64, height: 355)

    private func cards(_ heights: [Double], screen: String = "main") -> [Arrangement.Card] {
        heights.map { Arrangement.Card(id: NoteID(), screen: screen, presentedHeight: $0, expandedHeight: $0) }
    }
    private func overlap(_ a: NoteFrame, _ b: NoteFrame) -> Bool {
        a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y
    }

    func testRowsFlowLeftToRightTopAlignedAndClearTheToolbarColumn() {
        let input = cards([230, 180, 260, 200, 150, 220])
        let slots = Arrangement.plan(input, screens: [main], toolbar: toolbar, toolbarScreen: "main")
        XCTAssertEqual(slots.map(\.id), input.map(\.id), "stable durable order")
        let area = Arrangement.area(main, avoiding: toolbar)
        XCTAssertEqual(area.x, toolbar.x + toolbar.width + ArrangeMetrics.gap)
        let first = slots.filter { $0.frame.y + $0.frame.height == area.y + area.height }
        XCTAssertEqual(first.count, 4, "1440pt fits four 288pt cards beside the toolbar")
        XCTAssertEqual(first.map(\.frame.x), [0, 1, 2, 3].map { area.x + Double($0) * (288 + ArrangeMetrics.gap) })
        // Second row starts below the first row's tallest card, with one gap.
        let secondTop = area.y + area.height - 260 - ArrangeMetrics.gap
        XCTAssertEqual(slots[4].frame.y + slots[4].frame.height, secondTop)
        XCTAssertEqual(slots[4].frame.x, area.x)
        for (i, a) in slots.enumerated() {
            XCTAssertFalse(overlap(a.frame, toolbar))
            XCTAssertTrue(a.frame.x >= main.visible.x && a.frame.x + a.frame.width <= main.visible.x + main.visible.width)
            for b in slots[(i + 1)...] { XCTAssertFalse(overlap(a.frame, b.frame)) }
        }
        XCTAssertEqual(Set(slots.map(\.pages)), [1])
    }

    func testRepeatedArrangementIsDeterministic() {
        let input = cards([120, 300, 240, 480, 200])
        XCTAssertEqual(Arrangement.plan(input, screens: [main], toolbar: toolbar, toolbarScreen: "main"),
                       Arrangement.plan(input, screens: [main], toolbar: toolbar, toolbarScreen: "main"))
    }

    func testEachDisplayArrangesOnlyItsOwnCards() {
        let input = cards([200, 200], screen: "main") + cards([200], screen: "side")
        let slots = Arrangement.plan(input, screens: [main, side], toolbar: toolbar, toolbarScreen: "main")
        let onSide = slots.first { $0.screen == "side" }!
        XCTAssertEqual(onSide.frame.x, side.visible.x + ArrangeMetrics.margin, "toolbar column is reserved only on its own display")
        XCTAssertEqual(onSide.frame.y + onSide.frame.height, side.visible.y + side.visible.height - ArrangeMetrics.margin)
    }

    func testOverflowStartsANewPageInsteadOfOverlappingOrLeavingTheScreen() {
        let small = DockScreen(id: "main", visible: NoteFrame(x: 0, y: 0, width: 700, height: 600))
        let slots = Arrangement.plan(cards(Array(repeating: 300, count: 7)), screens: [small], toolbar: nil, toolbarScreen: nil)
        // Two columns, one row of 300pt per page in 556pt of height.
        XCTAssertEqual(slots.map(\.page), [0, 0, 1, 1, 2, 2, 3])
        XCTAssertEqual(Set(slots.map(\.pages)), [4])
        for page in 0..<4 {
            let onPage = slots.filter { $0.page == page }
            for (i, a) in onPage.enumerated() {
                XCTAssertGreaterThanOrEqual(a.frame.y, small.visible.y)
                for b in onPage[(i + 1)...] { XCTAssertFalse(overlap(a.frame, b.frame)) }
            }
        }
    }

    func testFoldedNotesUsePresentedHeightButKeepExpandedSize() {
        let folded = Arrangement.Card(id: NoteID(), screen: "main", presentedHeight: 32, expandedHeight: 240)
        let slot = Arrangement.plan([folded], screens: [main], toolbar: nil, toolbarScreen: nil)[0]
        XCTAssertEqual(slot.frame.height, 240)
        XCTAssertEqual(slot.frame.y + slot.frame.height, main.visible.height - ArrangeMetrics.margin)
    }

    func testPageVisibilityKeepsTheLastPageOfShorterDisplays() {
        XCTAssertTrue(Arrangement.visible(page: 0, pages: 1, current: 2))
        XCTAssertTrue(Arrangement.visible(page: 1, pages: 2, current: 1))
        XCTAssertFalse(Arrangement.visible(page: 0, pages: 2, current: 1))
    }

    func testNewNoteAvoidsToolbarAndExistingNotes() {
        let first = Arrangement.placement(width: 288, height: 200, screen: main, toolbar: toolbar, occupied: [])
        XCTAssertFalse(overlap(first, toolbar))
        XCTAssertEqual(first.x, toolbar.x + toolbar.width + ArrangeMetrics.gap, "first spot sits next to the toolbar")
        let second = Arrangement.placement(width: 288, height: 200, screen: main, toolbar: toolbar, occupied: [first])
        XCTAssertFalse(overlap(second, first))
        XCTAssertEqual(second.y, first.y, "same row when there is room")
        // A completely full screen cascades but stays on screen.
        let full = Arrangement.placement(width: 288, height: 200, screen: main, toolbar: toolbar, occupied: [main.visible])
        XCTAssertTrue(full.x >= 0 && full.x + full.width <= 1440 && full.y >= 0 && full.y + full.height <= 875)
    }

    func testToolbarDefaultClampAndDisplayRecovery() {
        let height = ToolbarMetrics.height(paged: false)
        let initial = ToolbarGeometry.resolve(nil, orientation: .vertical, paged: false, screens: [main])!.target
        XCTAssertEqual(initial.x, ToolbarMetrics.screenMargin)
        XCTAssertEqual(initial.y + initial.height, main.visible.height - ToolbarMetrics.screenMargin)
        let off = NoteFrame(x: 5000, y: -900, width: 64, height: height)
        let clamped = Arrangement.clampToolbar(off, to: main)
        XCTAssertEqual(clamped.x, 1440 - 64); XCTAssertEqual(clamped.y, 0)
        let tiny = DockScreen(id: "tiny", visible: NoteFrame(x: 0, y: 0, width: 400, height: 200))
        let short = Arrangement.clampToolbar(off, to: tiny)
        XCTAssertEqual(short.y + short.height, 200, "the grip stays reachable on a short display")
        // A saved display that is gone re-homes on the primary.
        let rehomed = ToolbarGeometry.resolve(.free(centerX: 2000, centerY: 300, display: "unplugged"), orientation: .vertical,
                                              paged: false, screens: [main, side])!
        XCTAssertEqual(rehomed.screen.id, "main"); XCTAssertEqual(rehomed.target.x, 1440 - 64)
    }

    func testStackHintPrefersTheRightSide() {
        let right = Arrangement.stackHint(beside: toolbar, width: 130, height: 112, screen: main)
        XCTAssertGreaterThan(right.x, toolbar.x + toolbar.width)
        let atEdge = NoteFrame(x: 1440 - 64, y: 300, width: 64, height: 355)
        let left = Arrangement.stackHint(beside: atEdge, width: 130, height: 112, screen: main)
        XCTAssertLessThan(left.x + left.width, atEdge.x)
    }

    func testPresentationTransitionsReverseMidAnimation() {
        var state = DeskPresentation(collapsed: false)
        state = state.toggled(); XCTAssertEqual(state, .collapsing)
        state = state.toggled(); XCTAssertEqual(state, .expanding, "a second click reverses, never queues")
        XCTAssertEqual(state.finished(), .expanded)
        XCTAssertEqual(DeskPresentation.collapsed.toggled(), .expanding)
        XCTAssertEqual(DeskPresentation.collapsing.finished(), .collapsed)
        XCTAssertTrue(DeskPresentation.collapsing.targetsCollapsed)
        XCTAssertFalse(DeskPresentation.expanding.targetsCollapsed)
    }

    func testArrangePersistsGeometryOnlyAndDetachesDockedNotes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let store = try Store(url: url)
        defer { try? store.close(); for s in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + s) } }
        let actions = NoteActions(store: store)
        let free = try actions.createNote(frame: NoteFrame(x: 900, y: 100))
        try actions.title(free.id, "今天要做")
        let item = try store.items(in: free.id)[0]
        try actions.text(item.id, in: free.id, "整理项目需求"); try actions.toggle(item.id, in: free.id)
        try actions.appearance(free.id, color: .mint, level: .topmost, collapsed: true)
        let docked = try actions.createNote()
        try actions.dock(docked.id, edge: .left, displayID: nil, index: 0)
        let before = try store.notes()
        let input = try store.notes().map { Arrangement.Card(id: $0.id, screen: "main", presentedHeight: 200, expandedHeight: 200) }
        let slots = Arrangement.plan(input, screens: [main], toolbar: toolbar, toolbarScreen: "main")
        try actions.arrange(slots, screens: [main])
        let after = try store.notes()
        XCTAssertEqual(after.map(\.id), before.map(\.id))
        for (old, new) in zip(before, after) {
            XCTAssertEqual(new.placement.freeFrame?.width, 288)
            XCTAssertEqual([old.title, old.color.rawValue, old.level.rawValue] as [String?], [new.title, new.color.rawValue, new.level.rawValue])
            XCTAssertEqual(old.collapsed, new.collapsed); XCTAssertEqual(old.order, new.order)
        }
        XCTAssertEqual(try store.items(in: free.id).map { [$0.text, String($0.completed)] }, [["整理项目需求", "true"]])
        XCTAssertNotNil(after.first { $0.id == docked.id }?.freeRestore, "docking's saved free frame is kept")
        XCTAssertNotNil(after.first { $0.id == docked.id }?.placement.freeFrame, "docked notes become free")
        // Arranging the same data again writes nothing new.
        try actions.arrange(slots, screens: [main])
        XCTAssertEqual(try store.notes().map(\.updatedAt), after.map(\.updatedAt))
    }
}
