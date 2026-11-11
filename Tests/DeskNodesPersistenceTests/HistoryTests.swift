import XCTest
@testable import DeskNodesPersistence

final class HistoryTests: XCTestCase {
    private func day(_ key: String) throws -> HistoryDay { try HistoryDay(key) }
    private func month(_ key: String) throws -> HistoryMonth { HistoryMonth(containing: try day(key)) }
    private func withStore(_ body: (Store, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        let store = try Store(url: url)
        defer { try? store.close() }
        try body(store, url)
    }
    func testMonthYearNavigationAndBounds() throws {
        let december = try month("2026-12-31")
        XCTAssertEqual(december.offset(1)?.first, try day("2027-01-01"))
        XCTAssertEqual(december.offset(1)?.offset(-1), december)
        XCTAssertEqual(try month("2026-01-01").offset(-1)?.title, "2025年12月")
        XCTAssertNil(try month("0001-01-01").offset(-1))
        XCTAssertNil(try month("9999-12-01").offset(1))
    }
    func testLeapDayAndMondayFirstSixWeekGrid() throws {
        XCTAssertEqual(try month("2024-02-29").days.count, 29)
        XCTAssertEqual(try month("2000-02-29").days.count, 29)
        XCTAssertEqual(try month("2100-02-01").days.count, 28)
        let november = try month("2026-11-06")
        XCTAssertEqual(november.cells.count, 42)
        XCTAssertTrue(november.cells.prefix(6).allSatisfy { $0 == nil })
        XCTAssertEqual(november.cells[6], try day("2026-11-01"))
        XCTAssertEqual(november.days.last, try day("2026-11-30"))
        XCTAssertEqual(try month("2026-06-01").cells.first!, try day("2026-06-01"))
    }
    func testTimezoneSelectsBusinessDayButNeverShiftsSnapshotKeys() throws {
        let instant = ISO8601DateFormatter().date(from: "2026-03-01T09:00:00Z")!
        let la = try BusinessCalendar(timeZone: XCTUnwrap(TimeZone(identifier: "America/Los_Angeles")))
        let tokyo = try BusinessCalendar(timeZone: XCTUnwrap(TimeZone(identifier: "Asia/Tokyo")))
        let laDay = try la.day(at: instant, settings: Settings())
        let jpDay = try tokyo.day(at: instant, settings: Settings())
        XCTAssertEqual(laDay, try day("2026-02-28"))
        XCTAssertEqual(jpDay, try day("2026-03-01"))
        XCTAssertEqual(HistoryMonth(containing: laDay).days.last, laDay)
        XCTAssertEqual(try day("2026-11-06").detailLabel, "11月6日 周五")
        XCTAssertEqual(try day("2024-02-29").detailLabel, "2月29日 周四")
    }
    func testMissingAndEmptyDaysHaveNoRateAndReadsNeverCapture() throws {
        try withStore { store, _ in
            let m = try month("2026-11-01")
            XCTAssertTrue(try store.history(in: m).isEmpty)
            XCTAssertNil(HistoryCompletion(snapshots: []).rate)
            XCTAssertEqual(HistoryCompletion(snapshots: []).percentage, "—")
            let empty = try store.capture(day: day("2026-11-03"))
            XCTAssertEqual(try store.history(in: m), [empty])
            XCTAssertNil(HistoryCompletion(snapshots: [empty]).rate)
            XCTAssertNil(try store.snapshot(day: day("2026-11-02")))
        }
    }
    func testWeightedRateIncludesDeletedFlagsWithoutInventingCompletions() throws {
        try withStore { store, _ in
            let note = try store.createNote(title: "original")
            let done = try store.createItem(in: note.id, text: "done", completed: true)
            let first = try store.capture(day: day("2026-11-01"))
            try store.deleteItem(done.id)
            for n in 1...9 { _ = try store.createItem(in: note.id, text: "todo \(n)", order: n) }
            let deleted = try XCTUnwrap(store.items(in: note.id).last)
            try store.deleteItem(deleted.id)
            let second = try store.capture(day: day("2026-11-02"), carryingUnfinishedTo: day("2026-11-06"))
            let counts = HistoryCompletion(snapshots: try store.history(in: month("2026-11-01")))
            XCTAssertEqual(counts.total, 11); XCTAssertEqual(counts.completed, 2)
            XCTAssertEqual(counts.rate!, 2.0 / 11.0, accuracy: 0.000001)
            XCTAssertEqual(counts.percentage, "18%")
            XCTAssertEqual(HistoryCompletion(notes: first.notes).percentage, "100%")
            XCTAssertEqual(second.notes[0].items.filter { $0.carriedTo != nil }.count, 8)
            XCTAssertNotNil(second.notes[0].items.first?.deletedAt)
            XCTAssertTrue(second.notes[0].items.first!.completed)
            XCTAssertNil(first.notes[0].items.first?.deletedAt)
            XCTAssertNotNil(second.notes[0].items.last?.deletedAt)
            XCTAssertFalse(second.notes[0].items.last!.completed)
            XCTAssertNil(second.notes[0].items.last?.carriedTo)
        }
    }
    func testRolloverArchiveDeletionCarryAndReopenKeepFrozenHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("roll.sqlite")
        var now = ISO8601DateFormatter().date(from: "2026-12-31T12:00:00Z")!
        let store = try Store(url: url, clock: { now })
        let utc = try BusinessCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        var note = try store.createNote(title: "frozen")
        let done = try store.createItem(in: note.id, text: "archived", completed: true)
        var todo = try store.createItem(in: note.id, text: "original", order: 1)
        let gone = try store.createNote(title: "deleted group", order: 1)
        _ = try store.createItem(in: gone.id, text: "deleted unfinished")
        try store.rollover(using: utc); try store.deleteNote(gone.id)
        now = now.addingTimeInterval(3 * 86400)
        try store.rollover(using: utc)
        let frozen = try XCTUnwrap(store.history(in: month("2026-12-01")).first)
        XCTAssertEqual(frozen.notes[0].items[1].carriedTo, try day("2027-01-03"))
        XCTAssertEqual(frozen.notes[1].title, "deleted group")
        XCTAssertNotNil(frozen.notes[1].deletedAt)
        XCTAssertEqual(HistoryCompletion(notes: frozen.notes).total, 3)
        XCTAssertEqual(HistoryCompletion(notes: frozen.notes).completed, 1)
        XCTAssertEqual(try store.items(in: note.id, includeDeleted: true).first { $0.id == done.id }?.archivedDay, frozen.day)
        todo.text = "changed live"; todo.completed = true; try store.update(todo)
        note.title = "new title"; try store.update(note); try store.deleteNote(note.id)
        XCTAssertEqual(try store.snapshot(day: frozen.day), frozen)
        XCTAssertNil(frozen.notes[0].deletedAt)
        XCTAssertNil(frozen.notes[0].items[0].deletedAt)
        now = now.addingTimeInterval(86400); try store.rollover(using: utc)
        let january = try store.history(in: month("2027-01-01"))
        XCTAssertEqual(january.count, 1)
        XCTAssertFalse(january[0].notes.flatMap(\.items).contains { $0.id == done.id })
        XCTAssertNil(try store.snapshot(day: day("2027-01-01")))
        try store.close()
        let reopened = try Store(url: url); defer { try? reopened.close() }
        XCTAssertEqual(try reopened.history(in: month("2026-12-01")), [frozen])
        XCTAssertEqual(try reopened.history(in: month("2027-01-01")), january)
    }
    func testSnapshotCodableRoundTripAndInvalidCivilDaysRejected() throws {
        try withStore { store, _ in
            let note = try store.createNote()
            _ = try store.createItem(in: note.id, text: "中文 👩🏽‍💻\nline", completed: true)
            _ = try store.createItem(in: note.id, text: "carry", order: 1)
            let deleted = try store.createItem(in: note.id, text: "deleted", order: 2)
            try store.deleteItem(deleted.id)
            let snapshot = try store.capture(day: day("2024-02-29"), carryingUnfinishedTo: day("2024-03-01"))
            let data = try JSONEncoder().encode(snapshot)
            XCTAssertEqual(try JSONDecoder().decode(DailySnapshot.self, from: data), snapshot)
            for key in ["2023-02-29", "2026-13-01", "0000-01-01", "2026-1-01"] {
                XCTAssertThrowsError(try JSONDecoder().decode(HistoryDay.self, from: JSONEncoder().encode(key)))
            }
        }
    }
    func testLongMonthReadPreservesEveryGroupItemAndOrderWithinMonth() throws {
        try withStore { store, _ in
            try store.transaction { db in
                for n in 0..<30 {
                    let note = try db.createNote(title: "便签 \(n)", order: n)
                    for j in 0..<20 {
                        _ = try db.createItem(in: note.id, text: "\(n)/\(j) 中文\n" + String(repeating: "长内容", count: 20), completed: j % 2 == 0, order: j)
                    }
                }
            }
            _ = try store.capture(day: day("2026-10-31"))
            let expected = try store.capture(day: day("2026-11-01"))
            _ = try store.capture(day: day("2026-12-01"))
            let result = try store.history(in: month("2026-11-30"))
            XCTAssertEqual(result, [expected])
            XCTAssertEqual(result[0].notes.map(\.order), Array(0..<30))
            XCTAssertTrue(result[0].notes.allSatisfy { $0.items.map(\.order) == Array(0..<20) })
            XCTAssertEqual(HistoryCompletion(snapshots: result).total, 600)
            XCTAssertEqual(HistoryCompletion(snapshots: result).percentage, "50%")
        }
    }
    func testCarryLabelsUseActualDestinationIncludingLeapAndYearJump() throws {
        try withStore { store, _ in
            let note = try store.createNote()
            _ = try store.createItem(in: note.id, text: "unfinished")
            let done = try store.createItem(in: note.id, completed: true, order: 1)
            let source = try day("2024-02-28")
            let leap = try store.capture(day: source, carryingUnfinishedTo: day("2024-02-29"))
            XCTAssertEqual(leap.notes[0].items[0].historyCarryLabel(relativeTo: source), "顺延到 2月29日")
            XCTAssertNil(leap.notes[0].items.first { $0.id == done.id }?.historyCarryLabel(relativeTo: source))
            let yearEnd = try day("2024-12-31")
            let next = try store.capture(day: yearEnd, carryingUnfinishedTo: day("2025-01-04"))
            XCTAssertEqual(next.notes[0].items[0].historyCarryLabel(relativeTo: yearEnd), "顺延到 2025-01-04")
        }
    }
    func testOptionalTitleFallbackUsesFrozenTextAndEmptyGroupFallback() throws {
        try withStore { store, _ in
            let a = try store.createNote(title: " \n")
            _ = try store.createItem(in: a.id, text: "  ")
            _ = try store.createItem(in: a.id, text: "first real item", order: 1)
            _ = try store.createNote(order: 1)
            _ = try store.createNote(title: "explicit", order: 2)
            let snapshot = try store.capture(day: day("2026-11-06"))
            XCTAssertEqual(snapshot.notes.map(\.historyTitle), ["first real item", "无标题便签", "explicit"])
        }
    }
}
