import XCTest
import Foundation
@testable import DeskNodesPersistence

final class StruckItemTests: XCTestCase {
    private var directory: URL!
    private var now = Date(timeIntervalSince1970: 0)
    private var url: URL { directory.appendingPathComponent("struck.sqlite") }
    private var utc: BusinessCalendar { try! BusinessCalendar(timeZone: TimeZone(secondsFromGMT: 0)!) }
    private func set(_ text: String) { now = ISO8601DateFormatter().date(from: text)! }
    private func store() throws -> Store { try Store(url: url, clock: { self.now }) }
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testStruckPersistsAndCannotAlsoBeCompleted() throws {
        let db = try store(), note = try db.createNote()
        var item = try db.createItem(in: note.id, text: "不做了")
        item.struck = true; try db.update(item)
        XCTAssertEqual(try db.items(in: note.id).first?.struck, true)
        XCTAssertEqual(try db.liveItemsByNote()[note.id]?.first?.struck, true)
        item.completed = true
        XCTAssertThrowsError(try db.update(item))
        try db.close()
        XCTAssertEqual(try store().items(in: note.id).first?.struck, true)
    }
    func testRolloverArchivesStruckWithoutCarryAndHistoryLeavesItOutOfTheCount() throws {
        set("2026-11-06T12:00:00Z")
        let db = try store(), note = try db.createNote()
        var dropped = try db.createItem(in: note.id, text: "划掉")
        dropped.struck = true; try db.update(dropped)
        _ = try db.createItem(in: note.id, text: "完成", completed: true, order: 1)
        let todo = try db.createItem(in: note.id, text: "顺延", order: 2)
        try db.rollover(using: utc)
        set("2026-11-07T04:00:00Z")
        guard case let .advanced(snapshot) = try db.rollover(using: utc) else { return XCTFail("expected rollover") }
        let items = snapshot.notes[0].items
        XCTAssertEqual(items.map(\.struck), [true, false, false])
        XCTAssertNil(items[0].carriedTo)
        XCTAssertNotNil(items[2].carriedTo)
        XCTAssertEqual(try db.items(in: note.id).map(\.id), [todo.id])
        XCTAssertEqual(try db.items(in: note.id, includeDeleted: true).first { $0.id == dropped.id }?.archivedDay?.rawValue, "2026-11-06")
        let counts = HistoryCompletion(notes: snapshot.notes)
        XCTAssertEqual(counts.total, 2); XCTAssertEqual(counts.completed, 1)
        // Archived struck rows round-trip through a backup.
        let backup = try Store.validateBackup(db.exportBackup())
        XCTAssertEqual(backup.contents.items.first { $0.id == dropped.id }?.struck, true)
    }
    func testSchema7BackupWithoutStruckKeysImports() throws {
        let db = try store(), note = try db.createNote()
        _ = try db.createItem(in: note.id, text: "旧备份")
        _ = try db.capture(day: HistoryDay("2026-01-01"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: db.exportBackup()) as? [String: Any])
        json["schema"] = 7
        json["items"] = (json["items"] as? [[String: Any]])?.map { var item = $0; item["struck"] = nil; return item }
        json["history"] = (json["history"] as? [[String: Any]])?.map { day in
            var day = day
            day["notes"] = (day["notes"] as? [[String: Any]])?.map { note in
                var note = note
                note["items"] = (note["items"] as? [[String: Any]])?.map { var item = $0; item["struck"] = nil; return item }
                return note
            }
            return day
        }
        let legacy = try JSONSerialization.data(withJSONObject: json)
        XCTAssertFalse(String(decoding: legacy, as: UTF8.self).contains("struck"))
        let validated = try Store.validateBackup(legacy)
        XCTAssertEqual(validated.contents.items.map(\.struck), [false])
        try db.replace(with: validated, confirmed: true)
        XCTAssertEqual(try db.items(in: note.id).map(\.text), ["旧备份"])
    }
    func testSchema7MigrationAddsStruckWithoutTouchingHistory() throws {
        let db = try store(), note = try db.createNote()
        _ = try db.createItem(in: note.id, text: "保留")
        let snapshot = try db.capture(day: HistoryDay("2026-01-01"))
        try db.close()
        let raw = try SQLite(url: url)
        try raw.run("ALTER TABLE items DROP COLUMN struck"); try raw.run("ALTER TABLE snapshot_items DROP COLUMN struck")
        try raw.run("PRAGMA user_version = 7"); try raw.close()
        let migrated = try store()
        XCTAssertEqual(try migrated.items(in: note.id).map(\.struck), [false])
        XCTAssertEqual(try migrated.snapshot(day: snapshot.day), snapshot)
        try migrated.close()
        let check = try SQLite(url: url)
        XCTAssertEqual(try check.query("PRAGMA user_version")[0][0], "8")
        XCTAssertThrowsError(try check.run("UPDATE snapshot_items SET struck=1"))
    }
}
