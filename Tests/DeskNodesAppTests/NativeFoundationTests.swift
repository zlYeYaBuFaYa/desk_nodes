import AppKit
import XCTest
import DeskNodesActions
import DeskNodesPersistence
@testable import DeskNodesApp

final class NativeFoundationTests: XCTestCase {
    @MainActor
    func testMarkedTextSurvivesAppearanceChange() {
        _ = NSApplication.shared
        let editor = NoteTextView(text: "确认")
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        editor.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasUncommittedComposition)
        let marked = editor.markedRange()
        let selected = editor.selectedRange()
        let string = editor.string
        editor.appearance = NSAppearance(named: .darkAqua)
        editor.viewDidChangeEffectiveAppearance()
        XCTAssertEqual(editor.markedRange(), marked)
        XCTAssertEqual(editor.selectedRange(), selected)
        XCTAssertEqual(editor.string, string)
        editor.unmarkText()
        XCTAssertFalse(editor.hasUncommittedComposition)
    }

    @MainActor
    func testStructuralCommandsAndNativeSelection() {
        _ = NSApplication.shared
        let editor = NoteTextView(text: "中文")
        var added = 0
        var deleted = 0
        editor.addRow = { added += 1 }
        editor.deleteEmptyRow = { deleted += 1 }
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        editor.doCommand(by: #selector(NSTextView.insertNewline(_:)))
        XCTAssertEqual(added, 1)
        XCTAssertEqual(editor.string, "中文")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 1, length: 0))
        editor.setMarkedText("拼音", selectedRange: NSRange(location: 2, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.doCommand(by: #selector(NSTextView.insertNewline(_:)))
        XCTAssertEqual(added, 1)
        editor.unmarkText()
        editor.string = ""
        editor.doCommand(by: #selector(NSTextView.deleteBackward(_:)))
        XCTAssertEqual(deleted, 1)
    }

    @MainActor
    func testBindingRetainsEditorCompositionAcrossCheckAndReorder() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try Store(url: directory.appendingPathComponent("native-test.sqlite"))
        defer { try? store.close() }
        let actions = NoteActions(store: store)
        let note = try actions.createNote()
        let first = try XCTUnwrap(store.items(in: note.id).first)
        try actions.text(first.id, in: note.id, "确认")
        let second = try actions.add(in: note.id)
        let card = NoteCardView(note: note, actions: actions, changed: {}, undoDelete: { false }, failure: { XCTFail("\($0)") })
        func editors(_ view: NSView) -> [NoteTextView] {
            (view as? NoteTextView).map { [$0] } ?? view.subviews.flatMap(editors)
        }
        let editor = try XCTUnwrap(editors(card).first(where: { $0.string == "确认" }))
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        editor.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        let selected = editor.selectedRange(), marked = editor.markedRange(), text = editor.string
        try actions.toggle(first.id, in: note.id)
        try actions.reorder(note.id, ids: [second.id, first.id])
        try actions.appearance(note.id, color: .mist, level: .topmost, collapsed: true)
        try actions.finalGeometry(note.id, frame: NoteFrame(x: -400, y: -30, width: 300, height: 500), manuallyResized: true)
        card.refresh(try XCTUnwrap(store.notes().first))
        card.frame = NSRect(x: 0, y: 0, width: 300, height: 32)
        card.layoutSubtreeIfNeeded()
        try actions.appearance(note.id, collapsed: false)
        card.refresh(try XCTUnwrap(store.notes().first))
        card.frame.size.height = 500
        card.layoutSubtreeIfNeeded()
        XCTAssertTrue(editors(card).contains(where: { $0 === editor }))
        XCTAssertEqual(editor.string, text)
        XCTAssertEqual(editor.selectedRange(), selected)
        XCTAssertEqual(editor.markedRange(), marked)
    }

    @MainActor
    func testNativeTextUndoWithoutDeletionInterception() throws {
        _ = NSApplication.shared
        let panel = NotePanel(origin: .zero)
        let editor = NoteTextView(text: "原文")
        panel.contentView = editor
        defer { panel.close() }
        var intercepted = 0
        editor.deletionUndo = { intercepted += 1; return false }
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        editor.insertText("中文", replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.breakUndoCoalescing()
        let manager = try XCTUnwrap(editor.undoManager)
        XCTAssertTrue(manager.canUndo)
        manager.undo()
        XCTAssertEqual(editor.string, "原文")
        XCTAssertEqual(intercepted, 0)
        XCTAssertTrue(manager.canRedo)
    }

    @MainActor
    func testNativeLevelPolicyAndCollapsedGeometry() {
        _ = NSApplication.shared
        let panel = NotePanel(origin: .zero)
        defer { panel.close() }
        panel.choice = .desktop; panel.applyLevel()
        XCTAssertEqual(panel.level.rawValue, Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.temporarilyRaised = true; panel.applyLevel()
        XCTAssertEqual(panel.level, .floating)
        panel.resignKey()
        XCTAssertEqual(panel.level.rawValue, Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.choice = .ordinary; panel.modes.allTopmost = true; panel.applyLevel()
        XCTAssertEqual(panel.level, .floating)
        panel.modes.allTopmost = false; panel.applyLevel()
        XCTAssertEqual(panel.level, .normal)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenNone))
        XCTAssertFalse(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        let expanded = NoteFrame(x: -500, y: -30, width: 300, height: 550)
        panel.present(expanded, collapsed: true, animate: false)
        XCTAssertEqual(panel.frame, NSRect(x: -500, y: 488, width: 300, height: 32))
        panel.present(expanded, collapsed: false, animate: false)
        XCTAssertEqual(panel.frame, NSRect(x: -500, y: -30, width: 300, height: 550))
    }

    @MainActor
    func testPreviewPanelCanEditWithoutBecomingMainWindow() {
        _ = NSApplication.shared
        let panel = NotePanel(origin: .zero)
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.contentRect(forFrameRect: panel.frame).size, NSSize(width: 240, height: 260))
        XCTAssertFalse(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        panel.close()
    }
}
