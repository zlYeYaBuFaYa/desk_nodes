import AppKit
import XCTest
import DeskNodesActions
import DeskNodesPersistence
@testable import DeskNodesApp

/// Requires real AppKit/SDK. These tests are not selected by the Linux manifest.
final class FidelityIntegrationTests: XCTestCase {
    @MainActor
    func testDockFooterAddsAndRespectsCompositionGateWithoutReplacingEditors() throws {
        _ = NSApplication.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try Store(url: url), actions = NoteActions(store: store)
        defer { try? store.close() }
        let note = try actions.createNote()
        try actions.dock(note.id, edge: .top, displayID: nil, index: 0)
        let docked = try XCTUnwrap(store.notes().first)
        let panel = NotePanel(origin: .zero); defer { panel.close() }
        let card = NoteCardView(note: docked, actions: actions,
            changed: {},
            undoDelete: { false }, failure: { XCTFail("\($0)") })
        panel.contentView = card
        card.frame = NSRect(x: 0, y: 0, width: 220, height: 260)
        card.layoutSubtreeIfNeeded()
        let button = try XCTUnwrap(card.subviews.compactMap { $0 as? NSButton }.first { $0.title == "＋ 添加事项" })
        XCTAssertFalse(button.isHidden)
        func editors(_ view: NSView) -> [NoteTextView] {
            (view as? NoteTextView).map { [$0] } ?? view.subviews.flatMap(editors)
        }
        let original = try XCTUnwrap(editors(card).first)
        card.canMutate = { false }
        button.performClick(nil)
        XCTAssertEqual(try store.items(in: note.id).count, 1)
        card.canMutate = { true }
        button.performClick(nil)
        XCTAssertEqual(try store.items(in: note.id).count, 2)
        card.refresh(try XCTUnwrap(store.notes().first))
        XCTAssertTrue(editors(card).contains { $0 === original })
        try actions.appearance(note.id, collapsed: true)
        card.refresh(try XCTUnwrap(store.notes().first)); card.layoutSubtreeIfNeeded()
        XCTAssertTrue(button.isHidden)
    }

}
