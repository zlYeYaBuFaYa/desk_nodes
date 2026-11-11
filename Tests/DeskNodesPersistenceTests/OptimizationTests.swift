import XCTest
import Foundation
@testable import DeskNodesPersistence

final class OptimizationTests: XCTestCase {
    private var directory: URL!
    private var now = Date(timeIntervalSince1970: 1_800_000_000.123456)
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    private func store() throws -> Store { try Store(url: directory.appendingPathComponent("db.sqlite3"), clock: { self.now }) }

    func testTimestampsRoundTripWithoutPrecisionLoss() throws {
        let db = try store()
        let note = try db.createNote()
        XCTAssertEqual(try db.notes().first?.createdAt.timeIntervalSince1970, note.createdAt.timeIntervalSince1970)
    }

    func testBlankItemLeavesNoTraceUnlessHistoryReferencesIt() throws {
        let db = try store()
        let note = try db.createNote()
        let blank = try db.createItem(in: note.id, text: "  ")
        let kept = try db.createItem(in: note.id, text: "内容", order: 1)
        XCTAssertThrowsError(try db.discardBlankItem(kept.id))
        try db.discardBlankItem(blank.id)
        XCTAssertEqual(try db.items(in: note.id, includeDeleted: true).map(\.id), [kept.id])
        XCTAssertTrue(try db.db.query("SELECT * FROM pending_deleted_items").isEmpty)

        // Sealed in history: retired silently, and the next daily snapshot does not list it.
        let sealed = try db.createItem(in: note.id, text: "", order: 2)
        _ = try db.capture(day: HistoryDay("2026-11-06"))
        try db.discardBlankItem(sealed.id)
        XCTAssertEqual(try db.items(in: note.id).map(\.id), [kept.id])
        XCTAssertNotNil(try db.items(in: note.id, includeDeleted: true).first { $0.id == sealed.id }?.deletedAt)
        XCTAssertTrue(try db.db.query("SELECT * FROM pending_deleted_items").isEmpty)
    }

    func testAutomaticBackupIsACompleteDatabaseAndKeepsSevenDays() throws {
        let db = try store()
        let note = try db.createNote(title: "备份")
        let backups = directory.appendingPathComponent("Backups")
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        for day in 1...9 { try AutomaticBackup.write(db, day: HistoryDay(String(format: "2026-11-%02d", day)), to: backups) }
        let names = try FileManager.default.contentsOfDirectory(atPath: backups.path).sorted()
        XCTAssertEqual(names, (3...9).map { String(format: "DeskNodes-2026-11-%02d.sqlite3", $0) })
        let copy = try Store(url: backups.appendingPathComponent(names.last!))
        XCTAssertEqual(try copy.notes().map(\.id), [note.id])
        XCTAssertEqual(try copy.notes().first?.title, "备份")
        try copy.close()
    }
}
