import XCTest
import Foundation
import DeskNodesPersistence
@testable import DeskNodesActions

final class DockingTests: XCTestCase {
    let primary = DockScreen(id: "primary", visible: NoteFrame(x: 0, y: 24, width: 1440, height: 850))
    let secondary = DockScreen(id: "secondary", visible: NoteFrame(x: -1280, y: -300, width: 1280, height: 650))
    func testPrimaryChosenMissingAndNegativeInsets() {
        XCTAssertEqual(DockGeometry.screen(nil, screens: [primary, secondary]), primary)
        XCTAssertEqual(DockGeometry.screen(nil, screens: [primary, secondary], preferred: "secondary"), secondary)
        XCTAssertEqual(DockGeometry.screen("missing", screens: [primary, secondary]), primary)
        XCTAssertNil(DockGeometry.screen(nil, screens: []))
        XCTAssertEqual(secondary.available, NoteFrame(x: -1272, y: -292, width: 1264, height: 634))
    }
    func testTopShortDisplayAndSideContentCollapse() {
        let ids = (0..<3).map { _ in NoteID() }
        let top = DockGeometry.layout(ids: ids, edge: .top, screen: primary)
        XCTAssertEqual(top.slots[0].frame, NoteFrame(x: 8, y: 606, width: 220, height: 260))
        XCTAssertEqual(top.slots[1].frame.x - top.slots[0].frame.x, 232)
        XCTAssertEqual(DockGeometry.layout(ids: ids, edge: .top, screen: secondary).slots[0].frame.height, 200)
        let tall = DockScreen(id: "tall", visible: NoteFrame(x: 0, y: 24, width: 1440, height: 900))
        let side = DockGeometry.layout(ids: ids, edge: .right, screen: tall, heights: [ids[0]: 300, ids[1]: 999], collapsed: [ids[2]])
        XCTAssertEqual(side.slots.map { $0.frame.height }, [300, 480, 32])
        XCTAssertEqual(side.slots[0].frame.width, DockGeometry.sideWidth)
        XCTAssertEqual(side.slots[0].frame.x, 1144)
        XCTAssertEqual(side.slots[0].frame.y - side.slots[1].frame.y, 492)
    }
    func testOverflowAllocationOrderAndPromotion() {
        let ids = (0..<20).map { _ in NoteID() }
        for edge in [DockEdge.top, .left, .right] {
            let layout = DockGeometry.layout(ids: ids, edge: edge, screen: secondary)
            XCTAssertFalse(layout.overflow.isEmpty); XCTAssertNotNil(layout.tabs)
            XCTAssertEqual(layout.slots.map(\.id) + layout.overflow, ids)
            let promoted = DockGeometry.layout(ids: ids, edge: edge, screen: secondary, selected: ids.last)
            XCTAssertEqual(promoted.slots.first?.id, ids.last)
            XCTAssertEqual(Set(promoted.slots.map(\.id) + promoted.overflow), Set(ids))
            for frame in layout.slots.map(\.frame) + [layout.tabs!] { assertInside(frame, secondary.available) }
        }
    }
    func testTinyRegionsAndClamp() {
        for width in [1.0, 90, 199, 240, 500] {
            for height in [1.0, 80, 120, 200, 350] {
                let screen = DockScreen(id: "tiny", visible: NoteFrame(x: -100, y: -200, width: width, height: height))
                let ids = (0..<8).map { _ in NoteID() }
                for edge in [DockEdge.top, .left, .right] {
                    let layout = DockGeometry.layout(ids: ids, edge: edge, screen: screen)
                    for frame in layout.slots.map(\.frame) + [layout.tabs].compactMap({ $0 }) { assertInside(frame, screen.available) }
                    XCTAssertEqual(Set(layout.slots.map(\.id) + layout.overflow), Set(ids))
                }
                assertInside(DockGeometry.clamp(NoteFrame(x: -999, y: 900, width: 400, height: 600), to: screen), screen.available)
            }
        }
    }
    func testSnapRetentionAndInsertionThresholds() {
        XCTAssertEqual(DockGeometry.snap(x: -800, y: 342, screen: secondary), .top)
        XCTAssertEqual(DockGeometry.snap(x: -1260, y: -100, screen: secondary), .left)
        XCTAssertEqual(DockGeometry.snap(x: -9, y: -100, screen: secondary), .right)
        XCTAssertNil(DockGeometry.snap(x: -800, y: 300, screen: secondary))
        XCTAssertNil(DockGeometry.snap(x: 500, y: 342, screen: secondary))
        XCTAssertTrue(DockGeometry.retains(edge: .top, x: -800, y: 300, screen: secondary))
        XCTAssertFalse(DockGeometry.retains(edge: .top, x: -800, y: 290, screen: secondary))
        let ids = (0..<3).map { _ in NoteID() }
        let layout = DockGeometry.layout(ids: ids, edge: .top, screen: primary)
        XCTAssertEqual(DockGeometry.insertion(x: 600, y: 800, edge: .top, slots: layout.slots, excluding: ids[0]), 2)
        XCTAssertEqual(DockGeometry.insertion(x: 0, y: 800, edge: .top, slots: layout.slots, excluding: ids[0]), 0)
    }
    private func assertInside(_ f: NoteFrame, _ a: NoteFrame, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(f.width, 0, file: file, line: line); XCTAssertGreaterThan(f.height, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(f.x, a.x, file: file, line: line); XCTAssertGreaterThanOrEqual(f.y, a.y, file: file, line: line)
        XCTAssertLessThanOrEqual(f.x + f.width, a.x + a.width, file: file, line: line)
        XCTAssertLessThanOrEqual(f.y + f.height, a.y + a.height, file: file, line: line)
    }
    private func database(_ body: (URL, Store, NoteActions) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try Store(url: url, clock: { Date(timeIntervalSince1970: 1000) })
        defer { try? store.close() }
        try body(url, store, NoteActions(store: store))
    }
    func testAtomicDockOrderDetachReopenUndoAndImmutableHistory() throws {
        try database { url, store, actions in
            let notes = try (0..<4).map { _ in try actions.createNote() }
            let frame = NoteFrame(x: -1000, y: -200, width: 330, height: 550)
            try actions.finalGeometry(notes[0].id, frame: frame, manuallyResized: true)
            try actions.appearance(notes[0].id, level: .ordinary, collapsed: true)
            let item = try XCTUnwrap(store.items(in: notes[0].id).first)
            try actions.text(item.id, in: notes[0].id, "中文 👩🏽‍💻")
            let history = try store.capture(day: HistoryDay("2026-11-06"))
            for note in notes { try actions.dock(note.id, edge: .top, displayID: "secondary", index: Int.max) }
            try actions.dock(notes[3].id, edge: .top, displayID: "secondary", index: 1)
            XCTAssertEqual(try store.notes().map(\.id), [notes[0].id, notes[3].id, notes[1].id, notes[2].id])
            let saved = try XCTUnwrap(store.notes().first)
            XCTAssertEqual(saved.freeRestore?.freeFrame, frame); XCTAssertFalse(saved.automaticHeight)
            XCTAssertTrue(saved.collapsed); XCTAssertEqual(saved.level, .ordinary)
            try actions.deleteNote(saved.id); XCTAssertTrue(try actions.undoDeletion())
            XCTAssertEqual(try store.notes().first, saved)
            try store.close()
            let reopened = try Store(url: url); defer { try? reopened.close() }
            let next = NoteActions(store: reopened)
            try next.detach(saved.id)
            XCTAssertEqual(try reopened.notes().first?.placement.freeFrame, frame)
            XCTAssertEqual(try reopened.items(in: saved.id).first?.id, item.id)
            XCTAssertEqual(try reopened.snapshot(day: history.day), history)
        }
    }
    func testNoGestureWritesAndRollbackFinalGroup() throws {
        try database { _, store, actions in
            let a = try actions.createNote(), b = try actions.createNote()
            let before = try store.notes()
            for x in 0..<100 { _ = DockGeometry.snap(x: Double(x), y: 850, screen: primary) }
            XCTAssertEqual(try store.notes(), before)
            enum Failure: Error { case injected }
            XCTAssertThrowsError(try store.transaction { _ in
                try actions.dock(a.id, edge: .left, displayID: nil, index: 0)
                try actions.dock(b.id, edge: .left, displayID: nil, index: 0)
                throw Failure.injected
            })
            XCTAssertEqual(try store.notes(), before)
            XCTAssertThrowsError(try actions.dock(NoteID(), edge: .top, displayID: nil, index: 0))
            XCTAssertEqual(try store.notes(), before)
        }
    }
    func testDisconnectMigrationPreferenceFallbackAndRestore() throws {
        try database { _, store, actions in
            let free = try actions.createNote(), dock = try actions.createNote()
            try actions.detach(free.id, frame: NoteFrame(x: -1200, y: -200, width: 300, height: 550), displayID: "secondary")
            try actions.dock(dock.id, edge: .right, displayID: "secondary", index: 0)
            try actions.reconcileScreens([primary, secondary])
            let before = try store.notes()
            try actions.reconcileScreens([]); XCTAssertEqual(try store.notes(), before)
            try actions.reconcileScreens([primary])
            let migrated = try store.notes()
            XCTAssertEqual(migrated.first { $0.id == dock.id }?.placement, .dock(edge: .right, displayID: "primary"))
            assertInside(try XCTUnwrap(migrated.first { $0.id == free.id }?.placement.freeFrame), primary.available)
            try actions.reconcileScreens([primary, secondary]); XCTAssertEqual(try store.notes(), migrated)
            XCTAssertEqual(DockGeometry.screen(nil, screens: [primary], preferred: "unavailable"), primary)
        }
    }
    func testCombinedStripsHaveDisjointRegions() {
        let ids = (0..<10).map { _ in NoteID() }
        for screen in [primary, secondary, DockScreen(id: "narrow", visible: NoteFrame(x: -300, y: 0, width: 440, height: 600))] {
            let edges: Set<DockEdge> = [.top, .left, .right]
            let top = DockGeometry.region(edge: .top, occupied: edges, screen: screen)
            let left = DockGeometry.region(edge: .left, occupied: edges, screen: screen)
            let right = DockGeometry.region(edge: .right, occupied: edges, screen: screen)
            let t = DockGeometry.layout(ids: ids, edge: .top, screen: top)
            let l = DockGeometry.layout(ids: ids, edge: .left, screen: left)
            let r = DockGeometry.layout(ids: ids, edge: .right, screen: right)
            let frames = [t, l, r].map { $0.slots.map(\.frame) + [$0.tabs].compactMap { $0 } }
            for a in frames[0] { for b in frames[1] + frames[2] { XCTAssertLessThanOrEqual(b.y + b.height, a.y - 12) } }
            for a in frames[1] { for b in frames[2] { XCTAssertLessThanOrEqual(a.x + a.width + 12, b.x) } }
        }
    }
    func testInsertionMapsPromotedAndOverflowSlotsToDurableOrder() {
        let ids = (0..<12).map { _ in NoteID() }
        let layout = DockGeometry.layout(ids: ids, edge: .top, screen: secondary, selected: ids[8])
        XCTAssertEqual(DockGeometry.insertion(x: -2000, y: 0, edge: .top, slots: layout.slots, ordered: ids, excluding: ids[11]), 8)
        XCTAssertEqual(DockGeometry.insertion(x: 1000, y: 0, edge: .top, slots: layout.slots, ordered: ids, excluding: ids[11]),
                       ids.firstIndex(of: layout.slots.last!.id)! + 1)
    }
    func testResolvedStripOrderCombinesDefaultAndExplicitPrimary() throws {
        try database { _, store, actions in
            let a = try actions.createNote(), b = try actions.createNote(), c = try actions.createNote()
            try actions.dock(a.id, edge: .top, displayID: nil, index: 0)
            try actions.dock(b.id, edge: .top, displayID: primary.id, index: 0, screens: [primary, secondary])
            try actions.dock(c.id, edge: .top, displayID: nil, index: 1, screens: [primary, secondary])
            XCTAssertEqual(try store.notes().map(\.id), [b.id, c.id, a.id])
            XCTAssertEqual(try store.notes().map(\.order), [0, 1, 2])
            XCTAssertEqual(try store.notes().first?.placement, .dock(edge: .top, displayID: primary.id))
        }
    }
    func testUnavailableHardwareIdentityIsNeverPersisted() throws {
        try database { _, store, actions in
            let screen = DockScreen(id: "session-screen-42", visible: primary.visible)
            XCTAssertNil(screen.persistentID)
            let note = try actions.createNote()
            try actions.detach(note.id, frame: NoteFrame(x: -10000, y: 0), displayID: "removed")
            try actions.reconcileScreens([screen])
            XCTAssertNil(try store.notes().first?.placement.displayID)
            assertInside(try XCTUnwrap(store.notes().first?.placement.freeFrame), screen.available)
        }
    }
    func testSnapDetachRestoreLeavesOtherFreeNotesAndParentsUntouched() throws {
        try database { _, store, actions in
            let a = try actions.createNote(), b = try actions.createNote()
            let old = try XCTUnwrap(store.notes().first { $0.id == b.id })
            let before = try store.items(in: a.id)
            let edge = try XCTUnwrap(DockGeometry.snap(x: -1272, y: 0, screen: secondary))
            try actions.dock(a.id, edge: edge, displayID: secondary.id, index: 0)
            try actions.detach(a.id, frame: NoteFrame(x: -1000, y: -200, width: 300, height: 400), displayID: secondary.id)
            let detached = try XCTUnwrap(store.notes().first { $0.id == a.id })
            try actions.dock(a.id, edge: .right, displayID: secondary.id, index: 0)
            try actions.detach(a.id)
            XCTAssertEqual(try store.notes().first { $0.id == a.id }?.placement, detached.placement)
            XCTAssertEqual(try store.notes().first { $0.id == b.id }, old)
            XCTAssertEqual(try store.items(in: a.id), before)
        }
    }

    func testPagedTabsAllocateEveryIdentityInOrderWithinRail() {
        let ids = (0..<31).map { _ in NoteID() }
        for height in [96.0, 200, 260, 634] {
            let frame = NoteFrame(x: -400, y: -100, width: 96, height: height)
            let pages = DockGeometry.tabs(ids: ids, frame: frame, page: 0).pageCount
            var allocated: [NoteID] = []
            for page in 0..<pages {
                let tabs = DockGeometry.tabs(ids: ids, frame: frame, page: page)
                allocated += tabs.slots.map(\.id)
                for slot in tabs.slots {
                    assertInside(slot.frame, frame)
                    XCTAssertGreaterThanOrEqual(slot.frame.y, tabs.control.y + tabs.control.height + 12)
                }
                assertInside(tabs.control, frame)
            }
            XCTAssertEqual(allocated, ids)
            XCTAssertEqual(DockGeometry.tabs(ids: ids, frame: frame, page: 999), DockGeometry.tabs(ids: ids, frame: frame, page: pages - 1))
        }
        let tiny = NoteFrame(x: 0, y: 0, width: 50, height: 20)
        let menuOnly = DockGeometry.tabs(ids: ids, frame: tiny, page: 0)
        XCTAssertTrue(menuOnly.slots.isEmpty); assertInside(menuOnly.control, tiny)
    }
    func testDockFailureAfterFirstRowRollsBackPlacementRestoreAndOrder() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        var writes = 0, fail = false
        let store = try Store(url: url, clock: {
            if fail { writes += 1; if writes == 2 { return Date(timeIntervalSince1970: .nan) } }
            return Date(timeIntervalSince1970: 1000)
        })
        defer { try? store.close() }
        let actions = NoteActions(store: store)
        let a = try actions.createNote(), b = try actions.createNote()
        try actions.dock(a.id, edge: .top, displayID: nil, index: 0)
        let before = try store.notes()
        fail = true
        XCTAssertThrowsError(try actions.dock(b.id, edge: .top, displayID: nil, index: 0))
        XCTAssertEqual(writes, 2)
        XCTAssertEqual(try store.notes(), before)
    }

}
