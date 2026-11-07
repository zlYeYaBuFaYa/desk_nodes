import XCTest
@testable import DeskNodesPersistence

final class BackupTests: XCTestCase {
    private var directory: URL!
    private var now = Date(timeIntervalSince1970: 1793966400)
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    private func store(_ name: String = UUID().uuidString) throws -> Store {
        try Store(url: directory.appendingPathComponent(name), clock: { self.now })
    }
    private func contents(_ store: Store) throws -> NativeBackup {
        try JSONDecoder().decode(NativeBackup.self, from: store.exportBackup())
    }
    private func validate(_ value: NativeBackup) throws -> ValidatedBackup {
        try Store.validateBackup(JSONEncoder().encode(value))
    }
    private func populated() throws -> Store {
        let db = try store()
        var settings = Settings(); settings.rolloverHour = 23; settings.rolloverMinute = 59
        settings.dockEdge = .right; settings.displayID = "外接🖥"; settings.edgePreference = .left
        try db.update(settings)
        var pref = NativePreferences(); pref.hotkey = "Command+Shift+7"; pref.loginDecision = .declined; try db.update(pref)
        var note = try db.createNote(title: nil, color: .mint, placement: .free(displayID: "屏幕", x: -600, y: -50, width: 321, height: 501), level: .topmost, order: 9)
        note.freeRestore = .free(displayID: nil, x: -7, y: 22, width: 240, height: 320)
        note.collapsed = true; note.automaticHeight = false; try db.update(note)
        _ = try db.createItem(in: note.id, text: "中文👩🏽‍💻e\u{301}\0\n第二行", completed: true, order: 7)
        _ = try db.createItem(in: note.id, text: "顺延", order: 12)
        let calendar = try BusinessCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        try db.rollover(using: calendar)
        now.addTimeInterval(86400 * 4)
        try db.rollover(using: calendar)
        let tombstone = try db.createNote(title: "删除", color: .graphite, order: 1)
        _ = try db.createItem(in: tombstone.id, text: "墓碑", order: 2)
        try db.deleteNote(tombstone.id)
        let item = try db.createItem(in: note.id, text: "待记录删除", order: 88)
        try db.deleteItem(item.id)
        return db
    }
    func testFullFidelityRoundTripAndReopen() throws {
        let source = try populated(), expected = try contents(source)
        let target = try store("target")
        _ = try target.createNote(title: "replace")
        try target.replace(with: Store.validateBackup(source.exportBackup()), confirmed: true)
        XCTAssertEqual(try contents(target), expected)
        try target.close()
        let reopened = try store("target")
        XCTAssertEqual(try contents(reopened), expected)
        XCTAssertEqual(expected.history.count, 1)
        XCTAssertEqual(expected.pendingNotes.count, 1); XCTAssertEqual(expected.pendingItems.count, 2)
        XCTAssertNotNil(expected.checkpoint)
        XCTAssertEqual(expected.items.filter { $0.archivedDay != nil }.count, 1)
        XCTAssertEqual(expected.history[0].notes[0].items.last?.carriedTo, expected.checkpoint?.activeDay)
        XCTAssertEqual(try reopened.settings(), try source.settings())
        XCTAssertEqual(try reopened.preferences().loginDecision, .declined)
        // Imported checkpoint/archive/pending/carry state must drive the same NEXT
        // rollover, not merely compare equal immediately after decoding.
        now.addTimeInterval(86400)
        let calendar = try BusinessCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(try reopened.rollover(using: calendar), try source.rollover(using: calendar))
        XCTAssertEqual(try contents(reopened), try contents(source))
    }
    func testImportedHistoryRemainsSealedAndArchivesImmutable() throws {
        let source = try populated(), target = try store("seal")
        try target.replace(with: Store.validateBackup(source.exportBackup()), confirmed: true)
        let raw = try SQLite(url: directory.appendingPathComponent("seal"))
        for sql in ["DELETE FROM days", "UPDATE snapshot_notes SET title='bad'", "UPDATE snapshot_items SET text='bad'", "DELETE FROM item_archives", "UPDATE item_archives SET day=day", "INSERT INTO snapshot_notes SELECT * FROM snapshot_notes", "INSERT INTO snapshot_items SELECT * FROM snapshot_items"] {
            XCTAssertThrowsError(try raw.run(sql), sql)
        }
        XCTAssertTrue(try raw.query("PRAGMA foreign_key_check").isEmpty)
        let old = try contents(target).history
        let live = try XCTUnwrap(target.notes().first)
        _ = try target.createItem(in: live.id, text: "after")
        XCTAssertEqual(try contents(target).history, old)
    }
    func testMalformedMissingCollectionsAndForeignFormatLeaveOriginal() throws {
        let target = try populated(), before = try target.exportBackup()
        for bytes in [Data("{".utf8), Data("{}".utf8), Data("{\"notes\":[]}".utf8)] {
            XCTAssertThrowsError(try Store.validateBackup(bytes))
            XCTAssertEqual(try target.exportBackup(), before)
        }
        var value = try contents(target); value.format = "tauri"
        XCTAssertThrowsError(try validate(value)); XCTAssertEqual(try target.exportBackup(), before)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: before) as? [String: Any])
        for key in ["notes", "items", "history", "settings", "preferences", "pendingNotes", "pendingItems"] {
            var broken = json; broken.removeValue(forKey: key)
            XCTAssertThrowsError(try Store.validateBackup(JSONSerialization.data(withJSONObject: broken)), key)
        }
        json["items"] = "wrong type"
        XCTAssertThrowsError(try Store.validateBackup(JSONSerialization.data(withJSONObject: json)))
    }
    func testIncompatibleEnvelopeAndSchemaVersions() throws {
        let db = try populated(), original = try contents(db)
        for version in [-1, 0, 2, 100] {
            var value = original; value.version = version; XCTAssertThrowsError(try validate(value))
        }
        for schema in [0, 6, 8] {
            var value = original; value.schema = schema; XCTAssertThrowsError(try validate(value))
        }
    }
    func testDuplicateIdentitiesAndSnapshotMembershipRejected() throws {
        let original = try contents(populated())
        var bad = original; bad.notes.append(bad.notes[0]); XCTAssertThrowsError(try validate(bad))
        bad = original; bad.items.append(bad.items[0]); XCTAssertThrowsError(try validate(bad))
        bad = original; bad.history.append(bad.history[0]); XCTAssertThrowsError(try validate(bad))
        bad = original; bad.pendingItems.append(bad.pendingItems[0]); XCTAssertThrowsError(try validate(bad))
        let snapshot = original.history[0], note = snapshot.notes[0]
        bad = original; bad.history = [DailySnapshot(day: snapshot.day, capturedAt: snapshot.capturedAt, notes: [note, note])]
        XCTAssertThrowsError(try validate(bad))
        let duplicate = SnapshotNote(id: note.id, title: note.title, color: note.color, order: note.order, deletedAt: note.deletedAt, items: note.items + note.items)
        bad = original; bad.history = [DailySnapshot(day: snapshot.day, capturedAt: snapshot.capturedAt, notes: [duplicate])]
        XCTAssertThrowsError(try validate(bad))
    }
    func testOrphanLiveSnapshotArchiveAndPendingReferencesRejected() throws {
        let original = try contents(populated())
        var bad = original; bad.notes = []; XCTAssertThrowsError(try validate(bad))
        bad = original; bad.items = []; XCTAssertThrowsError(try validate(bad))
        bad = original; bad.history = []; XCTAssertThrowsError(try validate(bad))
        bad = original; bad.pendingNotes = [NoteID()]; XCTAssertThrowsError(try validate(bad))
        bad = original; bad.pendingItems = [ItemID()]; XCTAssertThrowsError(try validate(bad))
        bad = original; bad.pendingNotes = [bad.notes.first { $0.deletedAt == nil }!.id]; XCTAssertThrowsError(try validate(bad))
        bad = original; bad.pendingItems = [bad.items.first { $0.archivedDay != nil }!.id]; XCTAssertThrowsError(try validate(bad))
    }
    func testInvalidGeometryOrdersSettingsAndHotkeyRejected() throws {
        let original = try contents(populated())
        var bad = original; bad.notes[0].order = -1; XCTAssertThrowsError(try validate(bad))
        bad = original; bad.items[0].order = -1; XCTAssertThrowsError(try validate(bad))
        bad = original; bad.notes[0].placement = .free(displayID: nil, x: 0, y: 0, width: 0, height: 120); XCTAssertThrowsError(try validate(bad))
        bad = original; bad.notes[0].freeRestore = .dock(edge: .top, displayID: nil); XCTAssertThrowsError(try validate(bad))
        bad = original; bad.settings.hour = 24; XCTAssertThrowsError(try validate(bad))
        bad = original; bad.settings.minute = -1; XCTAssertThrowsError(try validate(bad))
        bad = original; bad.preferences.hotkey = "Option+Command+D"; XCTAssertThrowsError(try validate(bad))
    }
    func testInvalidCivilDayCarryAndCheckpointRejected() throws {
        let original = try contents(populated()), snapshot = original.history[0], note = original.history[0].notes[0]
        let item = note.items[0]
        let carried = SnapshotItem(id: item.id, text: item.text, completed: true, order: item.order, deletedAt: nil, carriedTo: snapshot.day)
        var bad = original
        bad.history = [DailySnapshot(day: snapshot.day, capturedAt: snapshot.capturedAt, notes: [SnapshotNote(id: note.id, title: note.title, color: note.color, order: note.order, deletedAt: nil, items: [carried])])]
        XCTAssertThrowsError(try validate(bad))
        bad = original; bad.checkpoint?.activeDay = snapshot.day; XCTAssertThrowsError(try validate(bad))
        let bytes = try JSONEncoder().encode(original)
        let text = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: snapshot.day.rawValue, with: "2026-02-30")
        XCTAssertThrowsError(try Store.validateBackup(Data(text.utf8)))
    }
    func testCancelAndCompositionRefusalPreserveEveryTable() throws {
        let source = try populated(), target = try store(), backup = try Store.validateBackup(source.exportBackup())
        _ = try target.createNote(title: "keep")
        let before = try target.exportBackup()
        var prepared = false
        XCTAssertThrowsError(try target.replace(with: backup, confirmed: false, prepareEditing: { prepared = true; return true }))
        XCTAssertFalse(prepared)
        XCTAssertThrowsError(try target.replace(with: backup, confirmed: true, prepareEditing: { false }))
        XCTAssertEqual(try target.exportBackup(), before)
        XCTAssertThrowsError(try target.transaction { _ in try target.replace(with: backup, confirmed: true) })
        XCTAssertEqual(try target.exportBackup(), before)
    }
    func testBackupCopyInterruptedAfterWritingPageRollsBackAndRetryWorks() throws {
        let source = try populated(), note = try XCTUnwrap(source.notes().first)
        for i in 0..<20 { _ = try source.createItem(in: note.id, text: String(repeating: "长Unicode👩🏽‍💻", count: 1000), order: i) }
        let backup = try Store.validateBackup(source.exportBackup()), target = try store("rollback")
        _ = try target.createNote(title: "unchanged")
        let before = try target.exportBackup()
        XCTAssertThrowsError(try target.replace(with: backup, confirmed: true, prepareEditing: { true }, interruptAfterPage: true))
        XCTAssertEqual(try target.exportBackup(), before)
        try target.close(); let reopened = try store("rollback")
        XCTAssertEqual(try reopened.exportBackup(), before)
        try reopened.replace(with: backup, confirmed: true)
        XCTAssertEqual(try contents(reopened), backup.contents)
    }
    func testExportCompositionRefusalAndFlushAreAtomic() throws {
        let db = try store(), note = try db.createNote(), item = try db.createItem(in: note.id, text: "before")
        let before = try db.exportBackup()
        XCTAssertThrowsError(try db.exportBackup {
            var edited = item; edited.text = "intermediate"; try db.update(edited); return false
        })
        XCTAssertEqual(try db.exportBackup(), before)
        let bytes = try db.exportBackup {
            var edited = item; edited.text = "final中文"; try db.update(edited); return true
        }
        XCTAssertEqual(try Store.validateBackup(bytes).contents.items[0].text, "final中文")
        enum Failure: Error { case flush }
        XCTAssertThrowsError(try db.exportBackup { throw Failure.flush })
        XCTAssertEqual(try db.items(in: note.id)[0].text, "final中文")
    }
    func testExportFlushFailureRollsBackAllCommittedEditorWrites() throws {
        let db = try populated(), before = try db.exportBackup()
        let note = try XCTUnwrap(db.notes().first)
        let item = try XCTUnwrap(db.items(in: note.id).first)
        enum Failure: Error { case flush }
        XCTAssertThrowsError(try db.exportBackup {
            var edited = item; edited.text = "已提交，但导出事务失败"
            try db.update(edited)
            var titled = note; titled.title = "未完成的刷新"
            try db.update(titled)
            throw Failure.flush
        })
        XCTAssertEqual(try db.exportBackup(), before)
        try db.close()
    }
    func testInterruptedImportPreservesHotkeyPolicyAndEveryDestinationTable() throws {
        let target = try populated(), before = try target.exportBackup()
        let source = try store(), note = try source.createNote(title: "导入候选")
        for i in 0..<20 { _ = try source.createItem(in: note.id, text: String(repeating: "大备份", count: 1000) + String(i)) }
        var preferences = try source.preferences(); preferences.hotkey = "Control+Shift+8"
        try source.update(preferences)
        let backup = try Store.validateBackup(source.exportBackup())
        let binding = HotkeyBinding<Int>(), old = try Hotkey(target.preferences().hotkey)
        let candidate = try Hotkey(preferences.hotkey)
        var retired: [Int] = []
        try binding.replace(old, register: { _ in 1 }, persist: {}, unregister: { retired.append($0) })
        XCTAssertThrowsError(try binding.replace(candidate, register: { _ in 2 }, persist: {
            try target.replace(with: backup, confirmed: true, prepareEditing: { true }, interruptAfterPage: true)
        }, unregister: { retired.append($0) }))
        XCTAssertEqual(binding.binding, old); XCTAssertEqual(retired, [2])
        XCTAssertEqual(try target.exportBackup(), before)
        try binding.replace(candidate, register: { _ in 3 }, persist: {
            try target.replace(with: backup, confirmed: true)
        }, unregister: { retired.append($0) })
        XCTAssertEqual(binding.binding, candidate); XCTAssertEqual(retired, [2, 1])
        XCTAssertEqual(try contents(target), try contents(source))
    }
    func testEmptyBackupAndExtremeOrderAreSupported() throws {
        let source = try store(), target = try populated()
        try target.replace(with: Store.validateBackup(source.exportBackup()), confirmed: true)
        XCTAssertEqual(try contents(target), try contents(source))
        let note = try source.createNote(title: "", order: Int.max)
        _ = try source.createItem(in: note.id, text: "\0", order: Int.max)
        try target.replace(with: Store.validateBackup(source.exportBackup()), confirmed: true)
        XCTAssertEqual(try contents(target), try contents(source))
    }
    func testSchema6MigrationDefaultsAndRollback() throws {
        let db = try store("v6"), note = try db.createNote(title: "保留")
        let snap = try db.capture(day: HistoryDay("2026-01-01")); try db.close()
        let raw = try SQLite(url: directory.appendingPathComponent("v6"))
        try raw.run("DROP TABLE native_preferences"); try raw.run("PRAGMA user_version=6")
        let migrated = try store("v6")
        XCTAssertEqual(try migrated.preferences(), NativePreferences())
        XCTAssertEqual(try migrated.notes()[0].id, note.id); XCTAssertEqual(try migrated.snapshot(day: snap.day), snap)
        try migrated.close()
        try raw.run("PRAGMA user_version=6") // Inject conflicting table.
        XCTAssertThrowsError(try store("v6"))
        XCTAssertEqual(try raw.query("PRAGMA user_version"), [["6"]])
        XCTAssertEqual(try raw.query("SELECT COUNT(*) FROM notes"), [["1"]])
    }
    func testLoginFirstLaunchDecisionPersistenceAndBackupHasNoOSSideEffects() throws {
        let db = try store("consent")
        XCTAssertTrue(try db.preferences().shouldAskForLogin)
        var preferences = try db.preferences(); preferences.loginDecision = .declined; try db.update(preferences)
        try db.close(); let reopened = try store("consent")
        XCTAssertFalse(try reopened.preferences().shouldAskForLogin)
        let target = try store(); try target.replace(with: Store.validateBackup(reopened.exportBackup()), confirmed: true)
        XCTAssertEqual(try target.preferences().loginDecision, .declined)
        preferences.loginDecision = .requested; try target.update(preferences)
        XCTAssertFalse(try target.preferences().shouldAskForLogin)
        try target.replace(with: Store.validateBackup(reopened.exportBackup()), confirmed: true)
        XCTAssertEqual(try target.preferences().loginDecision, .declined)
    }
}
