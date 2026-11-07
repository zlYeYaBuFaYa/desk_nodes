import XCTest
import DeskNodesPersistence
@testable import DeskNodesActions

final class SharedRevealTests: XCTestCase {
    func testSharedActionsIDsLatestEditsDeletionUndoExpiryAndIsolation() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        var now = Date(timeIntervalSince1970: 100)
        let db = try Store(url: url, clock: { now }); defer { try? db.close() }
        let ordinary = NoteActions(store: db, clock: { now }), reveal = ordinary
        let a = try ordinary.createNote(), b = try reveal.createNote()
        let row = try XCTUnwrap(db.items(in: a.id).first)
        try ordinary.text(row.id, in: a.id, "ordinary")
        let stale = try XCTUnwrap(db.items(in: a.id).first)
        try reveal.text(row.id, in: a.id, "reveal 中文")
        let current = try XCTUnwrap(db.items(in: a.id).first)
        if EditorSynchronization.flush(local: stale.text, committed: current.text, active: false, marked: false) {
            try ordinary.text(row.id, in: a.id, stale.text)
        }
        XCTAssertEqual(try db.items(in: a.id).first?.text, "reveal 中文")
        XCTAssertThrowsError(try reveal.text(row.id, in: b.id, "wrong note"))
        XCTAssertThrowsError(try reveal.reorder(b.id, ids: [row.id]))
        try reveal.deleteItem(row.id, in: a.id)
        XCTAssertTrue(ordinary.prefersDeletionUndo)
        XCTAssertTrue(try ordinary.undoDeletion())
        XCTAssertEqual(try db.items(in: a.id).first?.id, row.id)
        try ordinary.deleteItem(row.id, in: a.id)
        try reveal.title(b.id, "typed after delete")
        XCTAssertFalse(ordinary.prefersDeletionUndo)
        XCTAssertTrue(reveal.canUndoDeletion)
        now.addTimeInterval(5)
        XCTAssertFalse(try reveal.undoDeletion())
        XCTAssertTrue(try db.items(in: a.id).isEmpty)
    }
    func testAllSurfaceCompositionGateAndAtomicActiveOnlyFlush() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        var now = ISO8601DateFormatter().date(from: "2026-11-06T03:59:59Z")!
        let db = try Store(url: url, clock: { now }); defer { try? db.close() }
        let actions = NoteActions(store: db), note = try actions.createNote()
        let row = try XCTUnwrap(db.items(in: note.id).first)
        try actions.text(row.id, in: note.id, "committed")
        try actions.toggle(row.id, in: note.id)
        let calendar = try BusinessCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        try db.rollover(using: calendar); now.addTimeInterval(1)
        var titleMarked = true, itemMarked = false
        func prepare() throws -> Bool {
            guard !titleMarked && !itemMarked else { return false }
            let current = try XCTUnwrap(db.items(in: note.id).first)
            if EditorSynchronization.flush(local: "final 中文", committed: current.text, active: true, marked: itemMarked) {
                try actions.text(row.id, in: note.id, "final 中文")
            }
            // A passive ordinary editor still showing the prior text cannot undo that flush.
            XCTAssertFalse(EditorSynchronization.flush(local: "committed", committed: "final 中文", active: false, marked: false))
            try actions.title(note.id, "最终标题")
            return true
        }
        XCTAssertEqual(try db.rollover(using: calendar, prepareEditing: prepare), .deferredEditing)
        titleMarked = false; itemMarked = true
        XCTAssertEqual(try db.rollover(using: calendar, prepareEditing: prepare), .deferredEditing)
        XCTAssertEqual(try db.items(in: note.id).first?.text, "committed")
        itemMarked = false
        guard case let .advanced(snapshot) = try db.rollover(using: calendar, prepareEditing: prepare) else { return XCTFail("advance") }
        XCTAssertEqual(snapshot.notes[0].title, "最终标题")
        XCTAssertEqual(snapshot.notes[0].items[0].text, "final 中文")
        XCTAssertTrue(try db.items(in: note.id).isEmpty)
    }
}
