import XCTest
import Foundation
import DeskNodesCore
import DeskNodesPersistence
@testable import DeskNodesActions

final class WindowStateTests: XCTestCase {
    func testBoundsAndNegativeOrigins() throws {
        let value = try NoteFrame(x: -1800, y: -220, width: 1, height: 900).bounded()
        XCTAssertEqual(value, NoteFrame(x: -1800, y: -220, width: 200, height: 600))
        XCTAssertEqual(try NoteFrame(x: 0, y: 0, width: 500, height: 1).bounded(), NoteFrame(x: 0, y: 0, width: 400, height: 120))
        for invalid in [Double.nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try NoteFrame(x: invalid, y: 0).bounded())
            XCTAssertThrowsError(try NoteFrame(x: 0, y: 0, width: invalid).bounded())
        }
    }
    func testCollapseAnchorsTopAndDoesNotLoseExpandedSize() {
        let expanded = NoteFrame(x: -320, y: -10, width: 310, height: 540)
        XCTAssertEqual(expanded.presenting(collapsed: true), NoteFrame(x: -320, y: 498, width: 310, height: 32))
        XCTAssertEqual(expanded.presenting(collapsed: false), expanded)
    }
    func testAutoHeightAndFallback() {
        XCTAssertEqual(NoteFrame.automaticHeight(content: 20), 120)
        XCTAssertEqual(NoteFrame.automaticHeight(content: 336), 336)
        XCTAssertEqual(NoteFrame.automaticHeight(content: 800), 480)
        XCTAssertEqual(WindowModes.collapsedTitle(nil, firstItem: "首项"), "首项")
        XCTAssertEqual(WindowModes.collapsedTitle("", firstItem: nil), "")
        XCTAssertEqual(WindowModes.collapsedTitle("标题", firstItem: "首项"), "标题")
    }
    func testAllTopmostRestoreAndTransientRaise() {
        var modes = WindowModes()
        let choices: [WindowLevel] = [.desktop, .ordinary, .topmost]
        XCTAssertEqual(choices.map { modes.effective($0) }, choices)
        modes.allTopmost = true
        XCTAssertEqual(choices.map { modes.effective($0) }, [.topmost, .topmost, .topmost])
        modes.allTopmost = false
        XCTAssertEqual(choices.map { modes.effective($0) }, choices)
        XCTAssertEqual(modes.effective(.desktop, temporarilyRaised: true), .ordinary)
        XCTAssertEqual(modes.effective(.desktop), .desktop)
        XCTAssertEqual(modes.effective(.ordinary, temporarilyRaised: true), .ordinary)
    }
    private func database(_ body: (URL, Store, NoteActions) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let store = try Store(url: url, clock: { Date(timeIntervalSince1970: 1000) })
        defer { try? store.close() }
        try body(url, store, NoteActions(store: store))
    }
    func testSQLiteFinalGeometryAppearanceReopenAndHistoryUndo() throws {
        try database { url, store, actions in
            let note = try actions.createNote()
            XCTAssertTrue(note.automaticHeight)
            let item = try XCTUnwrap(store.items(in: note.id).first)
            try actions.text(item.id, in: note.id, "中文历史")
            let day = try HistoryDay("2026-11-06")
            let history = try store.capture(day: day)
            let before = try XCTUnwrap(store.notes().first)
            // Merely presenting intermediate frames has no repository side effects.
            for height in 120...480 { _ = NoteFrame(x: -500, y: -30, height: Double(height)).presenting(collapsed: true) }
            XCTAssertEqual(try store.notes().first, before)
            try actions.finalGeometry(note.id, frame: NoteFrame(x: -500, y: -30, width: 330, height: 550), manuallyResized: true)
            try actions.appearance(note.id, color: .mint, level: .ordinary, collapsed: true)
            var modes = WindowModes(); modes.allTopmost = true
            XCTAssertEqual(modes.effective(.ordinary), .topmost)
            try actions.appearance(note.id, level: .desktop) // choice made during override survives restore
            modes.allTopmost = false
            let saved = try XCTUnwrap(store.notes().first)
            XCTAssertEqual(modes.effective(saved.level), .desktop)
            XCTAssertEqual(saved.placement, .free(displayID: nil, x: -500, y: -30, width: 330, height: 550))
            XCTAssertFalse(saved.automaticHeight); XCTAssertTrue(saved.collapsed)
            try actions.deleteNote(note.id); XCTAssertTrue(try actions.undoDeletion())
            XCTAssertEqual(try store.notes().first, saved)
            XCTAssertEqual(try store.snapshot(day: day), history)
            try store.close()
            let reopened = try Store(url: url); defer { try? reopened.close() }
            XCTAssertEqual(try reopened.notes().first, saved)
            XCTAssertEqual(try reopened.snapshot(day: day), history)
        }
    }
    func testInvalidFinalGeometryIsAtomicAndAutoHeightCanResume() throws {
        try database { _, store, actions in
            let note = try actions.createNote()
            XCTAssertThrowsError(try actions.finalGeometry(note.id, frame: NoteFrame(x: .nan, y: 0), manuallyResized: true))
            XCTAssertEqual(try store.notes().first, note)
            try actions.finalGeometry(note.id, frame: NoteFrame(x: -1, y: -2, width: 900, height: 2), manuallyResized: true)
            XCTAssertEqual(try store.notes().first?.placement, .free(displayID: nil, x: -1, y: -2, width: 400, height: 120))
            try actions.appearance(note.id, automaticHeight: true)
            XCTAssertTrue(try XCTUnwrap(store.notes().first).automaticHeight)
        }
    }
    func testExistingDockPlacementIsNotDetachedByGeometry() throws {
        try database { _, store, actions in
            let note = try store.createNote()
            try actions.finalGeometry(note.id, frame: NoteFrame(x: -200, y: 10), manuallyResized: true)
            XCTAssertEqual(try store.notes().first, note)
        }
    }
}
