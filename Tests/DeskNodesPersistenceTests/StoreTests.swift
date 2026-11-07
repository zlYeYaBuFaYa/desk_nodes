import XCTest
import Foundation
import CSQLite
import DeskNodesCore
@testable import DeskNodesPersistence

final class StoreTests: XCTestCase {
    private var directory: URL!
    private var url: URL { directory.appendingPathComponent("test.sqlite3") }
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    private func store() throws -> Store { try Store(url: url, clock: { self.instant }) }
    private func day(_ value: String = "2026-11-06") throws -> HistoryDay { try HistoryDay(value) }

    func testCRUDUnicodeReopenSettingsAndPlacement() throws {
        let db = try store()
        var note = try db.createNote(title: "中文 👩🏽‍💻 e\u{301}\0尾", order: 2)
        XCTAssertEqual(note.createdAt, instant)
        note.placement = .free(displayID: "屏幕-α", x: -1400, y: 24.5, width: 240, height: 150)
        note.color = .mint; note.level = .topmost; note.collapsed = true
        try db.update(note)
        var item = try db.createItem(in: note.id, text: "买菜\n🥬\0终", order: 3)
        item.text += " 改"; item.completed = true; item.order = 0
        try db.update(item)
        var settings = try db.settings()
        XCTAssertEqual(settings.rolloverHour, 4)
        settings.rolloverHour = 5; settings.rolloverMinute = 30
        settings.dockEdge = .right; settings.displayID = "外接"
        try db.update(settings)
        try db.close()
        let reopened = try store()
        XCTAssertEqual(try reopened.notes(), [note])
        XCTAssertEqual(try reopened.items(in: note.id), [item])
        XCTAssertEqual(try reopened.settings(), settings)
        try reopened.deleteItem(item.id)
        XCTAssertTrue(try reopened.items(in: note.id).isEmpty)
        XCTAssertEqual(try reopened.items(in: note.id, includeDeleted: true).first?.deletedAt, instant)
        XCTAssertThrowsError(try reopened.update(item))
        try reopened.deleteNote(note.id)
        XCTAssertTrue(try reopened.notes().isEmpty)
        XCTAssertEqual(try reopened.notes(includeDeleted: true).first?.title, note.title)
        XCTAssertThrowsError(try reopened.createItem(in: note.id))
    }
    func testDockOrderAndDeterministicTies() throws {
        let db = try store()
        let a = try db.createNote(placement: .dock(edge: .left, displayID: "A"), order: 10)
        let b = try db.createNote(placement: .dock(edge: .right, displayID: nil), order: 0)
        let c = try db.createNote(order: 0)
        let tied = [b,c].sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        XCTAssertEqual(try db.notes().map(\.id), (tied + [a]).map(\.id))
        var changed = a; changed.order = 1; changed.level = .ordinary
        try db.update(changed)
        XCTAssertEqual(try db.notes().last, changed)
    }
    func testRollbackAcrossCRUDSettingsSnapshotAndNestedSavepoints() throws {
        let db = try store()
        let note = try db.createNote(title: "before")
        let item = try db.createItem(in: note.id, text: "kept")
        enum Failure: Error { case abort }
        XCTAssertThrowsError(try db.transaction { store in
            var edited = note; edited.title = "lost"; try store.update(edited)
            try store.deleteItem(item.id)
            _ = try store.createNote()
            var settings = try store.settings(); settings.rolloverHour = 9; try store.update(settings)
            try store.capture(day: day())
            throw Failure.abort
        })
        XCTAssertEqual(try db.notes(), [note])
        XCTAssertEqual(try db.items(in: note.id), [item])
        XCTAssertEqual(try db.settings().rolloverHour, 4)
        XCTAssertNil(try db.snapshot(day: day()))
        try db.transaction { store in
            _ = try store.createItem(in: note.id, text: "outer")
            XCTAssertThrowsError(try store.transaction { nested in
                try nested.deleteNote(note.id)
                throw Failure.abort
            })
            XCTAssertEqual(try store.notes(), [note])
        }
        XCTAssertEqual(try db.items(in: note.id).count, 2)
        try db.close()
        XCTAssertEqual(try store().items(in: note.id).count, 2)
    }
    func testImmutableSnapshotRetainsFinalOrderTitleColorAndCarry() throws {
        let db = try store()
        var note = try db.createNote(title: "当天最终", color: .cherry, order: 4)
        var item = try db.createItem(in: note.id, text: "未完成", order: 8)
        let completed = try db.createItem(in: note.id, text: "完成", completed: true, order: 0)
        let removed = try db.createItem(in: note.id, text: "删除前内容", order: 3)
        try db.deleteItem(removed.id)
        let next = try day("2026-11-07")
        let snapshot = try db.capture(day: day(), carryingUnfinishedTo: next)
        XCTAssertEqual(snapshot.notes.first?.items.map(\.id), [completed.id, removed.id, item.id])
        XCTAssertEqual(snapshot.notes.first?.items.last?.carriedTo, next)
        XCTAssertNil(snapshot.notes.first?.items.first?.carriedTo)
        XCTAssertEqual(snapshot.notes.first?.items[1].deletedAt, instant)
        note.title = "later"; note.color = .graphite; note.order = 0; try db.update(note)
        item.text = "changed"; item.completed = true; item.order = 0; try db.update(item)
        try db.deleteNote(note.id)
        XCTAssertEqual(try db.capture(day: day()), snapshot)
        try db.close()
        XCTAssertEqual(try store().snapshot(day: day()), snapshot)
        XCTAssertEqual(snapshot.notes.first?.title, "当天最终")
        XCTAssertEqual(snapshot.notes.first?.color, .cherry)
        XCTAssertEqual(snapshot.notes.first?.order, 4)
        XCTAssertEqual(snapshot.notes.first?.items.last?.text, "未完成")
        XCTAssertEqual(snapshot.notes.first?.items.last?.completed, false)
        let deletedSnapshot = try store().capture(day: next, carryingUnfinishedTo: day("2026-11-08"))
        XCTAssertNotNil(deletedSnapshot.notes.first?.deletedAt)
        XCTAssertTrue(deletedSnapshot.notes[0].items.allSatisfy { $0.carriedTo == nil && $0.deletedAt != nil })
    }
    func testHistorySealedAtSQLLayer() throws {
        let db = try store()
        let note = try db.createNote()
        _ = try db.createItem(in: note.id)
        try db.capture(day: day())
        let raw = try SQLite(url: url)
        for table in ["days", "snapshot_notes", "snapshot_items"] {
            XCTAssertThrowsError(try raw.run("DELETE FROM \(table)"))
            XCTAssertThrowsError(try raw.run("UPDATE \(table) SET day=day"))
        }
        XCTAssertThrowsError(try raw.run("INSERT INTO snapshot_notes VALUES ('2026-11-06', ?,NULL,'paper',0,NULL)", [.text(note.id.rawValue.uuidString)]))
        XCTAssertThrowsError(try raw.run("INSERT INTO snapshot_items SELECT * FROM snapshot_items"))
        XCTAssertTrue(try raw.query("PRAGMA integrity_check").first?[0] == "ok")
        XCTAssertTrue(try raw.query("PRAGMA foreign_key_check").isEmpty)
    }
    func testMigrationFromNativeV1PreservesRowsAndSettings() throws {
        let raw = try SQLite(url: url)
        for sql in Schema.initial { try raw.run(sql) }
        let id = UUID().uuidString
        let placement = String(decoding: try JSONEncoder().encode(Placement.dock(edge: .top, displayID: nil)), as: UTF8.self)
        try raw.run("INSERT INTO notes VALUES (?,NULL,'paper',?,'desktop',0,0,1,1,NULL)", [.text(id), .text(placement)])
        try raw.run("PRAGMA application_id = \(Schema.applicationID)")
        try raw.run("PRAGMA user_version = 1")
        try raw.close()
        let db = try store()
        XCTAssertEqual(try db.notes().first?.id.rawValue.uuidString, id)
        XCTAssertEqual(try db.settings().rolloverHour, 4)
        try db.capture(day: day())
        try db.close()
        let check = try SQLite(url: url)
        XCTAssertEqual(try check.query("PRAGMA user_version")[0][0], "2")
    }
    func testFailedMigrationRollsBackDDLAndVersion() throws {
        let raw = try SQLite(url: url)
        for sql in Schema.initial { try raw.run(sql) }
        try raw.run("PRAGMA application_id = \(Schema.applicationID)")
        try raw.run("PRAGMA user_version = 1")
        try raw.run("CREATE TABLE snapshot_notes (conflict TEXT)")
        XCTAssertThrowsError(try store())
        XCTAssertEqual(try raw.query("PRAGMA user_version")[0][0], "1")
        XCTAssertTrue(try raw.query("SELECT name FROM sqlite_master WHERE name='days'").isEmpty)
        XCTAssertEqual(try raw.query("SELECT * FROM settings").count, 1)
    }
    func testRejectFutureAndForeignDatabasesWithoutChanges() throws {
        let raw = try SQLite(url: url)
        try raw.run("PRAGMA user_version = 999")
        XCTAssertThrowsError(try store()) { XCTAssertEqual($0 as? StoreError, .unsupportedSchema(999)) }
        XCTAssertEqual(try raw.query("PRAGMA user_version")[0][0], "999")
        try raw.run("PRAGMA user_version = 0")
        try raw.run("CREATE TABLE unrelated (value TEXT)")
        XCTAssertThrowsError(try store())
        XCTAssertEqual(try raw.query("SELECT name FROM sqlite_master WHERE type='table'").count, 1)
    }
    func testInvalidInputsAndIsolation() throws {
        let db = try store()
        XCTAssertThrowsError(try db.createNote(order: -1))
        XCTAssertThrowsError(try db.createNote(placement: .free(displayID: nil, x: .nan, y: 0, width: 240, height: 120)))
        var settings = Settings(); settings.rolloverHour = 24
        XCTAssertThrowsError(try db.update(settings))
        XCTAssertThrowsError(try day("2025-02-29"))
        XCTAssertThrowsError(try day("2026-1-01"))
        XCTAssertNoThrow(try day("2024-02-29"))
        XCTAssertThrowsError(try db.capture(day: day(), carryingUnfinishedTo: day()))
        XCTAssertNil(try db.snapshot(day: day()))
        let other = try Store(url: directory.appendingPathComponent("other.sqlite3"))
        _ = try db.createNote()
        XCTAssertTrue(try other.notes().isEmpty)
        try db.close()
        XCTAssertThrowsError(try db.notes())
    }
    func testTwoConnectionsRetryReturnsFirstSnapshot() throws {
        let a = try store(); let b = try store()
        let note = try a.createNote(title: "first")
        let original = try a.capture(day: day())
        var updated = note; updated.title = "second"; try b.update(updated)
        XCTAssertEqual(try b.capture(day: day()), original)
    }
    func testCaptureFailureRollsBackPartialChildrenAndCanRetry() throws {
        let db = try store()
        let note = try db.createNote(title: "final")
        _ = try db.createItem(in: note.id, text: "not lost")
        let raw = try SQLite(url: url)
        try raw.run("CREATE TRIGGER fail_capture BEFORE INSERT ON snapshot_items BEGIN SELECT RAISE(ABORT, 'injected failure'); END")
        XCTAssertThrowsError(try db.capture(day: day()))
        for table in ["days", "snapshot_notes", "snapshot_items"] {
            XCTAssertTrue(try raw.query("SELECT * FROM \(table)").isEmpty)
        }
        XCTAssertEqual(try db.items(in: note.id).first?.text, "not lost")
        try raw.run("DROP TRIGGER fail_capture")
        XCTAssertEqual(try db.capture(day: day()).notes.first?.title, "final")
    }
    func testFullIntegerOrderAndInvalidClock() throws {
        let db = try store()
        let note = try db.createNote(order: Int.max)
        let item = try db.createItem(in: note.id, order: Int.max)
        XCTAssertEqual(try db.notes().first?.order, Int.max)
        XCTAssertEqual(try db.items(in: note.id).first?.order, Int.max)
        let snap = try db.capture(day: day())
        XCTAssertEqual(snap.notes.first?.order, note.order)
        XCTAssertEqual(snap.notes.first?.items.first?.order, item.order)
        let invalid = try Store(url: directory.appendingPathComponent("invalid.sqlite3"),
                                clock: { Date(timeIntervalSince1970: .infinity) })
        XCTAssertThrowsError(try invalid.createNote())
        XCTAssertTrue(try invalid.notes().isEmpty)
    }

}
