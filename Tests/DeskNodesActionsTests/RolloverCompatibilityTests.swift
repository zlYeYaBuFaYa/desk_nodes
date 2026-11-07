import XCTest
import Foundation
import DeskNodesPersistence
@testable import DeskNodesActions

final class RolloverCompatibilityTests: XCTestCase {
    func testItemAndNoteDeleteUndoAcrossBoundaryPreserveSealedDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var now = ISO8601DateFormatter().date(from: "2026-11-06T03:59:58Z")!
        let db = try Store(url: directory.appendingPathComponent("undo.sqlite"), clock: { now })
        defer { try? db.close() }
        let actions = NoteActions(store: db, clock: { now })
        let calendar = try BusinessCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        let note = try actions.createNote()
        let item = try XCTUnwrap(db.items(in: note.id).first)
        try actions.text(item.id, in: note.id, "删除后撤销 中文")
        try db.rollover(using: calendar)
        try actions.deleteItem(item.id, in: note.id)
        now.addTimeInterval(2)
        guard case let .advanced(snapshot) = try db.rollover(using: calendar) else { return XCTFail("rollover") }
        XCTAssertNotNil(snapshot.notes[0].items[0].deletedAt)
        XCTAssertTrue(try actions.undoDeletion())
        XCTAssertEqual(try db.items(in: note.id).first?.text, "删除后撤销 中文")
        XCTAssertEqual(try db.snapshot(day: snapshot.day), snapshot)
        // A completed archive in a note must remain archived when the note is deleted/undone.
        try actions.toggle(item.id, in: note.id)
        now.addTimeInterval(86400)
        try db.rollover(using: calendar)
        let archived = try db.items(in: note.id, includeDeleted: true)
        XCTAssertNotNil(archived.first?.archivedDay)
        let live = try actions.add(in: note.id)
        try actions.deleteNote(note.id)
        XCTAssertTrue(try actions.undoDeletion())
        XCTAssertEqual(try db.items(in: note.id).map(\.id), [live.id])
        XCTAssertEqual(try db.items(in: note.id, includeDeleted: true).first { $0.id == item.id }, archived.first)
        // Delete note two seconds before another boundary; undo restores children, never history.
        now.addTimeInterval(86398)
        try actions.deleteNote(note.id)
        now.addTimeInterval(2)
        guard case let .advanced(deleted) = try db.rollover(using: calendar) else { return XCTFail("rollover") }
        XCTAssertNotNil(deleted.notes[0].deletedAt)
        XCTAssertTrue(try actions.undoDeletion())
        XCTAssertEqual(try db.items(in: note.id).map(\.id), [live.id])
        XCTAssertEqual(try db.snapshot(day: deleted.day), deleted)
        now.addTimeInterval(86400)
        guard case let .advanced(restored) = try db.rollover(using: calendar) else { return XCTFail("rollover") }
        XCTAssertNil(restored.notes[0].deletedAt)
        XCTAssertEqual(restored.notes[0].items.map(\.id), [live.id])
    }

    func testExpiredDeletionCannotRestoreArchiveOrAlterHistory() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        var now = ISO8601DateFormatter().date(from: "2026-11-06T03:59:59Z")!
        let db = try Store(url: url, clock: { now }); defer { try? db.close() }
        let actions = NoteActions(store: db, clock: { now })
        let calendar = try BusinessCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        let note = try actions.createNote(), item = try XCTUnwrap(db.items(in: note.id).first)
        try db.rollover(using: calendar); try actions.deleteItem(item.id, in: note.id)
        now.addTimeInterval(6)
        guard case let .advanced(snapshot) = try db.rollover(using: calendar) else { return XCTFail("rollover") }
        XCTAssertFalse(try actions.undoDeletion())
        XCTAssertTrue(try db.items(in: note.id).isEmpty)
        XCTAssertEqual(try db.snapshot(day: snapshot.day), snapshot)
        XCTAssertEqual(try db.items(in: note.id, includeDeleted: true).count, 1)
    }
}
