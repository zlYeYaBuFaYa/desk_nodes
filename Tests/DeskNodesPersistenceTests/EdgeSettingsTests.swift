import XCTest
@testable import DeskNodesPersistence

final class EdgeSettingsTests: XCTestCase {
    func testV5MigrationAndManualPreferenceReopenPreserveHistory() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let db = try Store(url: url)
        let note = try db.createNote(title: "原始")
        _ = try db.createItem(in: note.id, text: "中文")
        let day = try HistoryDay("2026-11-06"), snapshot = try db.capture(day: day)
        try db.close()
        let raw = try SQLite(url: url)
        try raw.run("ALTER TABLE settings DROP COLUMN edge_preference")
        try raw.run("PRAGMA user_version = 5"); try raw.close()
        let migrated = try Store(url: url)
        XCTAssertEqual(try migrated.settings().edgePreference, .automatic)
        var settings = try migrated.settings(); settings.edgePreference = .left
        try migrated.update(settings); try migrated.close()
        let reopened = try Store(url: url); defer { try? reopened.close() }
        XCTAssertEqual(try reopened.settings().edgePreference, .left)
        XCTAssertEqual(try reopened.snapshot(day: day), snapshot)
        settings.edgePreference = .right; try reopened.update(settings)
        XCTAssertEqual(try reopened.settings().edgePreference, .right)
        settings.edgePreference = .automatic; try reopened.update(settings)
        XCTAssertEqual(try reopened.settings().edgePreference, .automatic)
    }
    func testFailedV6MigrationPreservesVersionAndPreferenceConstraint() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let db = try Store(url: url); try db.close()
        let raw = try SQLite(url: url); defer { try? raw.close() }
        try raw.run("PRAGMA user_version = 5") // conflicting existing column
        XCTAssertThrowsError(try Store(url: url))
        XCTAssertEqual(try raw.query("PRAGMA user_version")[0][0], "5")
        XCTAssertEqual(try raw.query("SELECT edge_preference FROM settings")[0][0], "automatic")
        XCTAssertThrowsError(try raw.run("UPDATE settings SET edge_preference='top'"))
    }
}
