import XCTest
import Foundation
@testable import DeskNodesPersistence

final class RecentlyDeletedTests: XCTestCase {
    private var directory: URL!
    private var now = Date(timeIntervalSince1970: 1_800_000_000.25)
    private var db: Store!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        db = try Store(url: directory.appendingPathComponent("db.sqlite3"), clock: { self.now })
    }
    override func tearDownWithError() throws { try db.close(); try FileManager.default.removeItem(at: directory) }

    func testListsNotesWithTheirRowsAndSeparatelyDeletedRowsNewestFirst() throws {
        let note = try db.createNote(title: "购物")
        let early = try db.createItem(in: note.id, text: "早删", order: 0)
        let kept = try db.createItem(in: note.id, text: "牛奶", order: 1)
        _ = try db.createItem(in: note.id, text: " ", order: 2) // blank: never listed
        let other = try db.createNote(title: "工作", order: 1)
        let row = try db.createItem(in: other.id, text: "周报")
        try db.deleteItem(early.id)
        now.addTimeInterval(60); try db.deleteItem(row.id)
        now.addTimeInterval(60); try db.deleteNote(note.id)
        let list = try db.recentlyDeleted(now: now)
        XCTAssertEqual(list.notes.map(\.note.id), [note.id])
        XCTAssertEqual(list.notes[0].items.map(\.id), [kept.id], "rows deleted earlier are not part of the note deletion")
        XCTAssertEqual(list.items.map(\.item.id), [row.id], "rows of a deleted note are restored through the note")
        XCTAssertEqual(list.items[0].note.id, other.id)
    }

    func testRestoreNoteBringsBackOnlyRowsDeletedWithItAndLeavesHistoryAlone() throws {
        let note = try db.createNote()
        let early = try db.createItem(in: note.id, text: "早删")
        let kept = try db.createItem(in: note.id, text: "保留", order: 1)
        try db.deleteItem(early.id)
        now.addTimeInterval(1); try db.deleteNote(note.id)
        let sealed = try db.capture(day: HistoryDay("2026-11-06"))
        now.addTimeInterval(1); try db.restoreDeletedNote(note.id)
        XCTAssertEqual(try db.notes().map(\.id), [note.id])
        XCTAssertEqual(try db.items(in: note.id).map(\.id), [kept.id])
        XCTAssertEqual(try db.snapshot(day: HistoryDay("2026-11-06")), sealed)
        XCTAssertTrue(try db.db.query("SELECT * FROM pending_deleted_notes").isEmpty)
        XCTAssertEqual(try db.db.query("SELECT item_id FROM pending_deleted_items").compactMap { $0[0] }, [early.id.rawValue.uuidString])
        XCTAssertThrowsError(try db.restoreDeletedNote(note.id))
    }

    func testRestoredNoteAlwaysHasARowToTypeInto() throws {
        let note = try db.createNote()
        try db.deleteNote(note.id)
        try db.restoreDeletedNote(note.id)
        XCTAssertEqual(try db.items(in: note.id).count, 1)
    }

    func testRestoreItemAppendsToItsLiveNoteAndRefusesWhileNoteIsDeleted() throws {
        let note = try db.createNote()
        let a = try db.createItem(in: note.id, text: "a", order: 0)
        let b = try db.createItem(in: note.id, text: "b", order: 1)
        try db.deleteItem(a.id)
        try db.restoreDeletedItem(a.id)
        XCTAssertEqual(try db.items(in: note.id).map(\.id), [b.id, a.id])
        try db.deleteItem(b.id); now.addTimeInterval(1); try db.deleteNote(note.id)
        XCTAssertThrowsError(try db.restoreDeletedItem(b.id))
        XCTAssertThrowsError(try db.restoreDeletedItem(a.id), "deleted with the note: restored through the note")
    }

    func testEntriesLeaveTheListAfterThirtyDays() throws {
        let note = try db.createNote()
        try db.deleteNote(note.id)
        XCTAssertEqual(try db.recentlyDeleted(now: now.addingTimeInterval(29.9 * 86_400)).notes.count, 1)
        XCTAssertTrue(try db.recentlyDeleted(now: now.addingTimeInterval(30.1 * 86_400)).isEmpty)
        XCTAssertNotNil(try db.notes(includeDeleted: true).first?.deletedAt, "the tombstone itself is kept for history")
    }

    func testCountMatchesTheListWithoutLoadingIt() throws {
        func same(_ label: String) throws {
            let list = try db.recentlyDeleted(now: now)
            XCTAssertEqual(try db.recentlyDeletedCount(now: now), list.notes.count + list.items.count, label)
        }
        try same("empty")
        let live = try db.createNote(title: "live")
        let row = try db.createItem(in: live.id, text: "周报")
        let blanks = try [" ", "\t\n", "\u{3000}", "\u{00A0} "].enumerated().map { try db.createItem(in: live.id, text: $1, order: $0 + 1) }
        try db.deleteItem(row.id); for blank in blanks { try db.deleteItem(blank.id) }
        try same("blank rows, ideographic space included, are not listed")
        let gone = try db.createNote(title: "gone")
        _ = try db.createItem(in: gone.id, text: "随便签删除")
        now.addTimeInterval(1); try db.deleteNote(gone.id)
        try same("rows of a deleted note count with the note")
        now.addTimeInterval(31 * 86_400)
        try same("expired")
    }
}
