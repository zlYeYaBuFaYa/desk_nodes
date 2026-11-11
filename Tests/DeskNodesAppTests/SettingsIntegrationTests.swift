import AppKit
import XCTest
import DeskNodesActions
import DeskNodesPersistence
@testable import DeskNodesApp

final class SettingsIntegrationTests: XCTestCase {
    @MainActor
    func testSettingsReloadNeverSavesOrRegistersAndConflictPreservesPreference() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try Store(url: url), actions = NoteActions(store: store)
        defer { try? store.close() }
        let before = try store.exportBackup()
        var calls = 0
        let model = SettingsPresentation(actions: actions, login: LoginService(), changed: {},
            hotkey: { _, _ in calls += 1; throw StoreError.invalid("occupied") },
            export: { try store.exportBackup() }, importBackup: { _ in XCTFail("not requested") })
        model.reload(); model.reload()
        XCTAssertEqual(calls, 0); XCTAssertEqual(try store.exportBackup(), before)
        model.shortcut = "Command+7"; model.saveHotkey()
        XCTAssertEqual(calls, 1); XCTAssertNotNil(model.message)
        XCTAssertEqual(try store.preferences().hotkey, NativePreferences().hotkey)
        XCTAssertEqual(try store.preferences().loginDecision, .unasked)
    }
    @MainActor
    func testRemovedEditorsCannotRepublishEvenWhenImportedIDsMatch() throws {
        _ = NSApplication.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try Store(url: url), actions = NoteActions(store: store)
        defer { try? store.close() }
        let note = try actions.createNote(), item = try XCTUnwrap(store.items(in: note.id).first)
        let panel = NotePanel(origin: .zero)
        let card = NoteCardView(note: note, actions: actions, changed: {}, undoDelete: { false }, failure: { XCTFail("\($0)") })
        panel.contentView = card
        func editors(_ view: NSView) -> [NoteTextView] {
            (view as? NoteTextView).map { [$0] } ?? view.subviews.flatMap(editors)
        }
        let editor = try XCTUnwrap(editors(card).first)
        editor.undoManager?.registerUndo(withTarget: editor) { $0.string = "stale undo" }
        let backup = try Store.validateBackup(store.exportBackup())
        try store.replace(with: backup, confirmed: true)
        card.prepareForRemoval()
        editor.string = "stale notification"
        card.save(item.id, text: editor.string)
        try card.flushRolloverEdits()
        card.run { try actions.title(note.id, "stale title") }
        XCTAssertEqual(try store.items(in: note.id).first?.text, "")
        XCTAssertNil(try store.notes().first?.title)
        XCTAssertFalse(editor.undoManager?.canUndo ?? true)
        panel.close()
    }
    @MainActor
    func testHistoryReloadAfterReplacementClearsPreviousDataset() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try Store(url: directory.appendingPathComponent("a")), empty = try Store(url: directory.appendingPathComponent("b"))
        defer { try? store.close(); try? empty.close() }
        let day = try HistoryDay("2026-11-06")
        _ = try store.createNote(title: "old history"); try store.capture(day: day)
        let model = HistoryPresentation(store: store, today: day); model.reload()
        XCTAssertNotNil(model.daily)
        try store.replace(with: Store.validateBackup(empty.exportBackup()), confirmed: true)
        model.reload()
        XCTAssertNil(model.daily); XCTAssertTrue(model.snapshots.isEmpty)
    }
}
