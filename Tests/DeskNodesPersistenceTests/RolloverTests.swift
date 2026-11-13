import XCTest
import Foundation
@testable import DeskNodesPersistence

final class RolloverTests: XCTestCase {
    private var directory: URL!
    private var now = Date(timeIntervalSince1970: 0)
    private var url: URL { directory.appendingPathComponent("rollover.sqlite") }
    private var utc: BusinessCalendar { try! BusinessCalendar(timeZone: TimeZone(secondsFromGMT: 0)!) }
    private func instant(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func set(_ text: String) { now = instant(text) }
    private func day(_ key: String) throws -> HistoryDay { try HistoryDay(key) }
    private func store() throws -> Store { try Store(url: url, clock: { self.now }) }
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    private func advance(_ store: Store, to date: String, calendar: BusinessCalendar? = nil) throws -> DailySnapshot {
        set(date)
        guard case let .advanced(snapshot) = try store.rollover(using: calendar ?? utc) else {
            throw StoreError.invalid("expected rollover")
        }
        return snapshot
    }

    func test0359To0400ArchivesOnceAndRestartKeepsCheckpoint() throws {
        set("2026-11-06T03:59:00Z")
        let db = try store(), note = try db.createNote(title: "final")
        let done = try db.createItem(in: note.id, text: "完成 中文 👩🏽‍💻", completed: true)
        let todo = try db.createItem(in: note.id, text: "continue", order: 1)
        XCTAssertEqual(try db.rollover(using: utc), .initialized(try day("2026-11-05")))
        XCTAssertEqual(try db.rollover(using: utc), .unchanged)
        XCTAssertNil(try db.snapshot(day: day("2026-11-04")))
        let snapshot = try advance(db, to: "2026-11-06T04:00:00Z")
        XCTAssertEqual(snapshot.day, try day("2026-11-05"))
        XCTAssertEqual(snapshot.notes[0].items.map(\.id), [done.id, todo.id])
        XCTAssertEqual(snapshot.notes[0].items.last?.carriedTo, try day("2026-11-06"))
        XCTAssertEqual(try db.items(in: note.id), [todo])
        let archived = try XCTUnwrap(db.items(in: note.id, includeDeleted: true).first { $0.id == done.id })
        XCTAssertNil(archived.deletedAt); XCTAssertEqual(archived.archivedDay, snapshot.day)
        XCTAssertThrowsError(try db.update(done)); XCTAssertThrowsError(try db.deleteItem(done.id))
        XCTAssertThrowsError(try db.restoreItem(done))
        XCTAssertEqual(try db.rollover(using: utc), .unchanged)
        let checkpoint = try db.rolloverCheckpoint()
        try db.close()
        let reopened = try store()
        XCTAssertEqual(try reopened.rolloverCheckpoint(), checkpoint)
        XCTAssertEqual(try reopened.rollover(using: utc), .unchanged)
        XCTAssertEqual(try reopened.snapshot(day: snapshot.day), snapshot)
        XCTAssertEqual(try reopened.items(in: note.id).map(\.id), [todo.id])
        let raw = try SQLite(url: url)
        XCTAssertEqual(try raw.query("SELECT COUNT(*) FROM item_archives")[0][0], "1")
        XCTAssertEqual(try raw.query("SELECT COUNT(*) FROM days")[0][0], "1")
    }

    func testNondefaultHourMinutePersistsAndIsUsedAfterReopen() throws {
        set("2026-11-06T05:29:59Z")
        let db = try store(); var settings = try db.settings()
        settings.rolloverHour = 5; settings.rolloverMinute = 30; try db.update(settings)
        try db.rollover(using: utc); try db.close()
        let reopened = try store()
        XCTAssertEqual(try reopened.settings().rolloverMinute, 30)
        XCTAssertEqual(try reopened.rollover(using: utc), .unchanged)
        XCTAssertEqual(try advance(reopened, to: "2026-11-06T05:30:00Z").day, try day("2026-11-05"))
    }

    func testMultiDaySleepClosesOnlyObservedDayWithDirectCarry() throws {
        set("2026-11-01T12:00:00Z")
        let db = try store(), note = try db.createNote()
        let todo = try db.createItem(in: note.id, text: "same identity")
        let done = try db.createItem(in: note.id, completed: true, order: 1)
        try db.rollover(using: utc)
        let snapshot = try advance(db, to: "2026-11-06T12:00:00Z")
        XCTAssertEqual(snapshot.day, try day("2026-11-01"))
        XCTAssertEqual(snapshot.notes[0].items[0].carriedTo, try day("2026-11-06"))
        for key in ["2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06"] {
            XCTAssertNil(try db.snapshot(day: day(key)))
        }
        XCTAssertEqual(try db.items(in: note.id).map(\.id), [todo.id])
        XCTAssertEqual(try db.items(in: note.id, includeDeleted: true).first { $0.id == done.id }?.archivedDay, snapshot.day)
        let next = try advance(db, to: "2026-11-07T04:00:00Z")
        XCTAssertEqual(next.notes[0].items.map(\.id), [todo.id])
        XCTAssertEqual(next.notes[0].items[0].carriedTo, try day("2026-11-07"))
        XCTAssertEqual(try db.rollover(using: utc), .unchanged)
    }

    func testEmptyObservedDaySealsOnceButInitialStartupInventsNoPast() throws {
        set("2026-11-06T12:00:00Z")
        let db = try store()
        XCTAssertEqual(try db.rollover(using: utc), .initialized(try day("2026-11-06")))
        let raw = try SQLite(url: url)
        XCTAssertTrue(try raw.query("SELECT * FROM days").isEmpty)
        let empty = try advance(db, to: "2026-11-10T12:00:00Z")
        XCTAssertTrue(empty.notes.isEmpty)
        XCTAssertEqual(empty.day, try day("2026-11-06"))
        XCTAssertEqual(try db.rollover(using: utc), .unchanged)
        XCTAssertEqual(try raw.query("SELECT COUNT(*) FROM days")[0][0], "1")
        XCTAssertNil(try db.snapshot(day: day("2026-11-09")))
    }

    func testDSTGapNextValidTimeAndFoldFirstOccurrenceUseProductionRollover() throws {
        let la = try BusinessCalendar(timeZone: XCTUnwrap(TimeZone(identifier: "America/Los_Angeles")))
        set("2026-03-08T09:59:59Z") // 01:59:59 PST; 02:30 is missing
        let db = try store(); var settings = try db.settings()
        settings.rolloverHour = 2; settings.rolloverMinute = 30; try db.update(settings)
        XCTAssertEqual(try db.rollover(using: la), .initialized(try day("2026-03-07")))
        XCTAssertEqual(try advance(db, to: "2026-03-08T10:00:00Z", calendar: la).day, try day("2026-03-07"))
        XCTAssertEqual(try db.rollover(using: la), .unchanged)
        // New isolated database for the autumn fold.
        let fold = try Store(url: directory.appendingPathComponent("fold.sqlite"), clock: { self.now })
        settings.rolloverHour = 1; settings.rolloverMinute = 30; try fold.update(settings)
        set("2026-11-01T08:29:59Z")
        XCTAssertEqual(try fold.rollover(using: la), .initialized(try day("2026-10-31")))
        try advance(fold, to: "2026-11-01T08:30:00Z", calendar: la)
        set("2026-11-01T09:15:00Z") // repeated 01:15, already past FIRST boundary
        XCTAssertEqual(try fold.rollover(using: la), .unchanged)
        set("2026-11-01T09:30:00Z")
        XCTAssertEqual(try fold.rollover(using: la), .unchanged)
        let raw = try SQLite(url: directory.appendingPathComponent("fold.sqlite"))
        XCTAssertEqual(try raw.query("SELECT COUNT(*) FROM days")[0][0], "1")
    }

    func testDefaultBoundaryAcrossDSTKeepsLocalFourAM() throws {
        let la = try BusinessCalendar(timeZone: XCTUnwrap(TimeZone(identifier: "America/Los_Angeles")))
        set("2026-03-08T10:59:59Z") // 03:59 PDT
        let db = try store(); try db.rollover(using: la)
        XCTAssertEqual(try advance(db, to: "2026-03-08T11:00:00Z", calendar: la).day, try day("2026-03-07"))
        let fold = try Store(url: directory.appendingPathComponent("default-fold.sqlite"), clock: { self.now })
        set("2026-11-01T11:59:59Z"); try fold.rollover(using: la)
        XCTAssertEqual(try advance(fold, to: "2026-11-01T12:00:00Z", calendar: la).day, try day("2026-10-31"))
    }

    func testBackwardInstantAndRestartCannotBackdateOrArchiveEarly() throws {
        set("2026-11-06T12:00:00Z")
        let db = try store(), note = try db.createNote()
        _ = try db.createItem(in: note.id, completed: true)
        try db.rollover(using: utc)
        let checkpoint = try db.rolloverCheckpoint()
        set("2026-11-05T12:00:00Z")
        XCTAssertEqual(try db.rollover(using: utc), .heldForClockReversal)
        XCTAssertEqual(try db.rolloverCheckpoint(), checkpoint)
        XCTAssertEqual(try db.items(in: note.id).count, 1)
        try db.close(); let reopened = try store()
        XCTAssertEqual(try reopened.rollover(using: utc), .heldForClockReversal)
        XCTAssertNil(try reopened.snapshot(day: day("2026-11-05")))
        set("2026-11-06T12:00:00Z")
        XCTAssertEqual(try reopened.rollover(using: utc), .unchanged)
        try advance(reopened, to: "2026-11-07T04:00:00Z")
        XCTAssertTrue(try reopened.items(in: note.id).isEmpty)
    }

    func testTimezoneDateShiftForwardThenBackFreezesCivilCheckpoint() throws {
        let east = try BusinessCalendar(timeZone: XCTUnwrap(TimeZone(identifier: "Pacific/Kiritimati")))
        let west = try BusinessCalendar(timeZone: XCTUnwrap(TimeZone(identifier: "Pacific/Honolulu")))
        set("2026-11-06T12:00:00Z")
        let db = try store(), note = try db.createNote()
        let todo = try db.createItem(in: note.id)
        XCTAssertEqual(try db.rollover(using: west), .initialized(try day("2026-11-05")))
        guard case let .advanced(snapshot) = try db.rollover(using: east) else { return XCTFail("shift must advance") }
        XCTAssertEqual(snapshot.notes[0].items[0].carriedTo, try day("2026-11-06"))
        set("2026-11-06T13:00:00Z")
        XCTAssertEqual(try db.rollover(using: west), .heldForClockReversal)
        XCTAssertEqual(try db.items(in: note.id).map(\.id), [todo.id])
        set("2026-11-06T14:00:00Z")
        XCTAssertEqual(try db.rollover(using: west), .unchanged)
        set("2026-11-06T14:01:00Z")
        guard case .advanced = try db.rollover(using: east) else { return XCTFail("forward date") }
        XCTAssertNil(try db.snapshot(day: day("2026-11-07")))
    }

    func testDeletionMembershipOnceAndArchiveIsNotTombstone() throws {
        set("2026-11-06T12:00:00Z")
        let db = try store(), note = try db.createNote(title: "retained")
        let removed = try db.createItem(in: note.id, text: "deleted")
        let done = try db.createItem(in: note.id, text: "archived", completed: true, order: 1)
        let todo = try db.createItem(in: note.id, text: "live", order: 2)
        let deletedNote = try db.createNote(title: "deleted note", order: 1)
        let deletedChild = try db.createItem(in: deletedNote.id, text: "child", completed: true)
        try db.rollover(using: utc)
        try db.deleteItem(removed.id); try db.deleteNote(deletedNote.id)
        let first = try advance(db, to: "2026-11-07T04:00:00Z")
        XCTAssertEqual(first.notes.count, 2)
        XCTAssertNotNil(first.notes.first { $0.id == deletedNote.id }?.deletedAt)
        XCTAssertNotNil(first.notes.first { $0.id == deletedNote.id }?.items.first?.deletedAt)
        XCTAssertNotNil(first.notes.first { $0.id == note.id }?.items.first { $0.id == removed.id }?.deletedAt)
        XCTAssertEqual(try db.items(in: note.id).map(\.id), [todo.id])
        let second = try advance(db, to: "2026-11-08T04:00:00Z")
        XCTAssertEqual(second.notes.map(\.id), [note.id])
        XCTAssertEqual(second.notes[0].items.map(\.id), [todo.id])
        XCTAssertEqual(try db.items(in: deletedNote.id, includeDeleted: true).first?.id, deletedChild.id)
        try db.deleteNote(note.id)
        let archived = try XCTUnwrap(db.items(in: note.id, includeDeleted: true).first { $0.id == done.id })
        XCTAssertNil(archived.deletedAt); XCTAssertNotNil(archived.archivedDay)
        XCTAssertEqual(try db.snapshot(day: first.day), first)
        let third = try advance(db, to: "2026-11-09T04:00:00Z")
        XCTAssertEqual(third.notes[0].items.map(\.id), [todo.id])
        XCTAssertTrue(try advance(db, to: "2026-11-10T04:00:00Z").notes.isEmpty)
        XCTAssertEqual(try db.items(in: note.id, includeDeleted: true).count, 3)
    }

    func testWholeTransactionRollbackAtSnapshotArchiveAndCheckpointThenRetry() throws {
        for (index, trigger) in [
            "BEFORE INSERT ON snapshot_items", "BEFORE INSERT ON days",
            "BEFORE INSERT ON item_archives", "BEFORE DELETE ON pending_deleted_items",
            "BEFORE DELETE ON pending_deleted_notes",
            "BEFORE UPDATE ON rollover_state"
        ].enumerated() {
            let path = directory.appendingPathComponent("failure-\(index).sqlite")
            set("2026-11-06T12:00:00Z")
            let db = try Store(url: path, clock: { self.now }), note = try db.createNote()
            let done = try db.createItem(in: note.id, text: "before", completed: true)
            let removed = try db.createItem(in: note.id, text: "deleted")
            let removedNote = try db.createNote(title: "deleted", order: 1)
            try db.deleteNote(removedNote.id)
            try db.deleteItem(removed.id); try db.rollover(using: utc)
            let checkpoint = try db.rolloverCheckpoint()
            let raw = try SQLite(url: path)
            try raw.run("CREATE TRIGGER fail_rollover \(trigger) BEGIN SELECT RAISE(ABORT, 'injected'); END")
            set("2026-11-07T04:00:00Z")
            XCTAssertThrowsError(try db.rollover(using: utc) {
                var edit = done; edit.text = "flushed"; try db.update(edit); return true
            })
            XCTAssertEqual(try db.rolloverCheckpoint(), checkpoint)
            XCTAssertEqual(try db.items(in: note.id), [done])
            for table in ["days", "snapshot_notes", "snapshot_items", "item_archives"] {
                XCTAssertTrue(try raw.query("SELECT * FROM \(table)").isEmpty)
            }
            XCTAssertEqual(try raw.query("SELECT COUNT(*) FROM pending_deleted_items")[0][0], "1")
            XCTAssertEqual(try raw.query("SELECT COUNT(*) FROM pending_deleted_notes")[0][0], "1")
            try db.close(); try raw.run("DROP TRIGGER fail_rollover")
            let reopened = try Store(url: path, clock: { self.now })
            guard case let .advanced(snapshot) = try reopened.rollover(using: utc) else { return XCTFail("retry") }
            XCTAssertEqual(snapshot.notes[0].items.count, 2)
            XCTAssertTrue(try reopened.items(in: note.id).isEmpty)
            XCTAssertEqual(try reopened.rollover(using: utc), .unchanged)
            XCTAssertTrue(try raw.query("PRAGMA foreign_key_check").isEmpty)
            XCTAssertEqual(try raw.query("PRAGMA integrity_check")[0][0], "ok")
            XCTAssertEqual(try reopened.db.query("PRAGMA synchronous")[0][0], "2")
            XCTAssertEqual(try raw.query("PRAGMA journal_mode")[0][0], "wal")
        }
    }

    func testPrepareEditingDefersThenFlushesBeforeFinalSnapshot() throws {
        set("2026-11-06T03:59:00Z")
        let db = try store(), note = try db.createNote()
        let item = try db.createItem(in: note.id, text: "before", completed: true)
        try db.rollover(using: utc)
        let checkpoint = try db.rolloverCheckpoint()
        set("2026-11-06T04:00:00Z")
        XCTAssertEqual(try db.rollover(using: utc, prepareEditing: {
            var edit = item; edit.text = "deferred write must roll back"; try db.update(edit)
            return false
        }), .deferredEditing)
        XCTAssertEqual(try db.rolloverCheckpoint(), checkpoint)
        XCTAssertEqual(try db.items(in: note.id), [item])
        enum Abort: Error { case save }
        XCTAssertThrowsError(try db.rollover(using: utc) {
            var edit = item; edit.text = "not committed"; try db.update(edit); throw Abort.save
        })
        XCTAssertEqual(try db.items(in: note.id), [item])
        guard case let .advanced(snapshot) = try db.rollover(using: utc, prepareEditing: {
            var edit = item; edit.text = "中文 committed"; try db.update(edit); return true
        }) else { return XCTFail("commit") }
        XCTAssertEqual(snapshot.notes[0].items[0].text, "中文 committed")
        XCTAssertTrue(try db.items(in: note.id).isEmpty)
    }

    func testTwoConnectionsCannotDuplicateArchiveOrCarry() throws {
        set("2026-11-06T12:00:00Z")
        let a = try store(), b = try store(), note = try a.createNote()
        _ = try a.createItem(in: note.id, completed: true)
        try a.rollover(using: utc)
        try advance(b, to: "2026-11-07T04:00:00Z")
        XCTAssertEqual(try a.rollover(using: utc), .unchanged)
        let raw = try SQLite(url: url)
        XCTAssertEqual(try raw.query("SELECT COUNT(*) FROM days")[0][0], "1")
        XCTAssertEqual(try raw.query("SELECT COUNT(*) FROM item_archives")[0][0], "1")
        XCTAssertThrowsError(try raw.run("DELETE FROM item_archives"))
        XCTAssertThrowsError(try raw.run("UPDATE item_archives SET day=day"))
        let newItem = try a.createItem(in: note.id, text: "not in the sealed snapshot")
        try raw.run("PRAGMA foreign_keys = ON")
        XCTAssertThrowsError(try raw.run("INSERT INTO item_archives VALUES (?, '2026-11-06')", [.text(newItem.id.rawValue.uuidString)]))
        XCTAssertEqual(try a.items(in: note.id).map(\.id), [newItem.id])
    }

    func testExistingCallerSnapshotIsPreservedAndNoPastDayIsInvented() throws {
        set("2026-11-06T12:00:00Z")
        let db = try store(), note = try db.createNote(title: "N2")
        _ = try db.createItem(in: note.id)
        let old = try db.capture(day: day("2026-11-06"))
        XCTAssertEqual(try db.rollover(using: utc), .initialized(try day("2026-11-07")))
        XCTAssertEqual(try db.snapshot(day: old.day), old)
        set("2026-11-07T12:00:00Z")
        XCTAssertEqual(try db.rollover(using: utc), .unchanged)
        XCTAssertEqual(try advance(db, to: "2026-11-08T04:00:00Z").day, try day("2026-11-07"))
        XCTAssertEqual(try db.snapshot(day: old.day), old)
    }

    func testNativeV4MigrationKeepsSealedHistoryAndSeedsOnlyUnrecordedDeletes() throws {
        set("2026-11-06T12:00:00Z")
        let db = try store(), note = try db.createNote(title: "kept")
        let recorded = try db.createItem(in: note.id, text: "already recorded")
        try db.deleteItem(recorded.id)
        let old = try db.capture(day: day("2026-11-05"))
        let unrecorded = try db.createItem(in: note.id, text: "not yet recorded")
        try db.deleteItem(unrecorded.id)
        let retained = try db.items(in: note.id, includeDeleted: true)
        try db.close()
        let raw = try SQLite(url: url)
        for table in ["item_archives", "pending_deleted_items", "pending_deleted_notes", "rollover_state"] {
            try raw.run("DROP TABLE \(table)")
        }
        try raw.run("DROP TABLE native_preferences")
        try raw.run("ALTER TABLE settings DROP COLUMN edge_preference")
        try raw.run("ALTER TABLE items DROP COLUMN struck"); try raw.run("ALTER TABLE snapshot_items DROP COLUMN struck")
        try raw.run("PRAGMA user_version = 4")
        let migrated = try store()
        XCTAssertEqual(try migrated.items(in: note.id, includeDeleted: true), retained)
        XCTAssertEqual(try migrated.snapshot(day: old.day), old)
        XCTAssertEqual(try raw.query("PRAGMA user_version")[0][0], "8")
        XCTAssertEqual(try raw.query("SELECT item_id FROM pending_deleted_items")[0][0], unrecorded.id.rawValue.uuidString)
        try migrated.rollover(using: utc)
        let snapshot = try advance(migrated, to: "2026-11-07T04:00:00Z")
        XCTAssertEqual(snapshot.notes[0].items.map(\.id), [unrecorded.id])
        XCTAssertThrowsError(try raw.run("UPDATE snapshot_items SET text='lost'"))
    }

    func testFailedV5MigrationRollsBackWithoutUnsealingHistory() throws {
        set("2026-11-06T12:00:00Z")
        let db = try store(); let old = try db.capture(day: day("2026-11-05")); try db.close()
        let raw = try SQLite(url: url)
        for table in ["item_archives", "pending_deleted_items", "pending_deleted_notes", "rollover_state"] { try raw.run("DROP TABLE \(table)") }
        try raw.run("DROP TABLE native_preferences")
        try raw.run("ALTER TABLE settings DROP COLUMN edge_preference")
        try raw.run("PRAGMA user_version = 4")
        try raw.run("CREATE TABLE pending_deleted_items (conflict TEXT)")
        XCTAssertThrowsError(try store())
        XCTAssertEqual(try raw.query("PRAGMA user_version")[0][0], "4")
        XCTAssertTrue(try raw.query("SELECT name FROM sqlite_master WHERE name='rollover_state'").isEmpty)
        XCTAssertEqual(try raw.query("SELECT day FROM days")[0][0], old.day.rawValue)
        XCTAssertThrowsError(try raw.run("DELETE FROM days"))
    }

    func testCalendarValidationAndBoundarySettingsChangeDoNotRewriteHistory() throws {
        XCTAssertThrowsError(try BusinessCalendar(timeZone: .current, calendar: Calendar(identifier: .buddhist)))
        XCTAssertThrowsError(try utc.day(at: Date(timeIntervalSince1970: .infinity), settings: Settings()))
        set("2026-11-06T03:59:00Z")
        let db = try store(); try db.rollover(using: utc)
        let snapshot = try advance(db, to: "2026-11-06T04:00:00Z")
        var settings = try db.settings(); settings.rolloverHour = 6; try db.update(settings)
        XCTAssertEqual(try db.rollover(using: utc), .heldForClockReversal)
        XCTAssertEqual(try db.snapshot(day: snapshot.day), snapshot)
        set("2026-11-06T06:00:00Z")
        XCTAssertEqual(try db.rollover(using: utc), .unchanged)
    }
}
