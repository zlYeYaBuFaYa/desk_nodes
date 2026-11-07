import XCTest
import DeskNodesPersistence
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
}
