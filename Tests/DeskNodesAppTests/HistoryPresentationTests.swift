import XCTest
@testable import DeskNodesPersistence
@testable import DeskNodesApp

final class HistoryPresentationTests: XCTestCase {
    @MainActor
    func testNavigationReloadAndFailureNeverShowsStaleMonth() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try Store(url: directory.appendingPathComponent("history.sqlite"))
        let day = try HistoryDay("2026-12-31")
        let model = HistoryPresentation(store: store, today: day)
        model.reload()
        XCTAssertTrue(model.snapshots.isEmpty)
        XCTAssertNil(try store.snapshot(day: day))
        let note = try store.createNote(title: "frozen")
        _ = try store.createItem(in: note.id, completed: true)
        let snapshot = try store.capture(day: day)
        model.reload()
        XCTAssertEqual(model.daily, snapshot)
        model.navigate(1)
        XCTAssertEqual(model.selected, try HistoryDay("2027-01-01"))
        XCTAssertNil(model.daily); XCTAssertTrue(model.snapshots.isEmpty)
        model.navigate(-1)
        model.selected = day
        XCTAssertEqual(model.daily, snapshot)
        try store.close()
        model.reload()
        XCTAssertNotNil(model.failure)
        XCTAssertNil(model.daily); XCTAssertTrue(model.snapshots.isEmpty)
    }

    @MainActor
    func testSelectStepAndTodayTurnMonthsButNeverPassToday() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try Store(url: directory.appendingPathComponent("history.sqlite"))
        defer { try? store.close() }
        let today = try HistoryDay("2026-11-13")
        let model = HistoryPresentation(store: store, today: today)
        model.select(try HistoryDay("2026-10-31"))
        XCTAssertEqual(model.month, HistoryMonth(containing: try HistoryDay("2026-10-01")))
        model.step(days: 1)
        XCTAssertEqual(model.selected, try HistoryDay("2026-11-01")); XCTAssertEqual(model.month.first, try HistoryDay("2026-11-01"))
        model.step(days: -7)
        XCTAssertEqual(model.selected, try HistoryDay("2026-10-25"))
        model.select(try HistoryDay("2026-11-10")); model.step(days: 7)
        XCTAssertEqual(model.selected, today, "clamped to today")
        model.select(try HistoryDay("2026-09-02")); model.showToday()
        XCTAssertEqual(model.selected, today); XCTAssertEqual(model.month.first, try HistoryDay("2026-11-01"))
    }

    func testMenuLabelsUseBusinessDaysAndHeatFollowsTheRate() throws {
        let today = try HistoryDay("2026-11-13")
        XCTAssertEqual(HistoryMenuRow.label(try HistoryDay("2026-11-12"), today: today), "昨天 · 11月12日")
        XCTAssertEqual(HistoryMenuRow.label(try HistoryDay("2026-11-11"), today: today), "周三 · 11月11日")
        XCTAssertEqual(HistoryMenuRow.label(try HistoryDay("2026-11-07"), today: today), "周六 · 11月7日")
        XCTAssertEqual(HistoryMenuRow.label(try HistoryDay("2026-11-06"), today: today), "11月6日")

        func snapshot(_ flags: [Bool]) throws -> DailySnapshot {
            let items = flags.enumerated().map { index, done in
                SnapshotItem(id: ItemID(), text: "\(index)", completed: done, struck: false, order: index, deletedAt: nil, carriedTo: nil)
            }
            return DailySnapshot(day: today, capturedAt: Date(), notes: [SnapshotNote(id: NoteID(), title: nil, color: .lemon, order: 0, deletedAt: nil, items: items)])
        }
        XCTAssertEqual(HistoryHeat(nil), .none)
        XCTAssertEqual(HistoryHeat(try snapshot([])), .empty)
        XCTAssertEqual(HistoryHeat(try snapshot([false, false])), .empty, "nothing done reads like nothing there")
        XCTAssertEqual(HistoryHeat(try snapshot([true, false, false])), .low)
        XCTAssertEqual(HistoryHeat(try snapshot([true, false])), .mid)
        XCTAssertEqual(HistoryHeat(try snapshot([true, true])), .full)
    }
}
