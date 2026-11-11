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
    func testDockDetachKeepsMarkedEditorIdentityAndManualState() throws {
        _ = NSApplication.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try Store(url: url); defer { try? store.close() }
        let actions = NoteActions(store: store), panel = NotePanel(origin: .zero)
        defer { panel.close() }
        let note = try actions.createNote()
        try actions.finalGeometry(note.id, frame: NoteFrame(x: -500, y: -80, width: 320, height: 550), manuallyResized: true)
        let card = NoteCardView(note: note, actions: actions, changed: {}, undoDelete: { false }, failure: { XCTFail("\($0)") })
        panel.contentView = card
        func editors(_ view: NSView) -> [NoteTextView] {
            (view as? NoteTextView).map { [$0] } ?? view.subviews.flatMap(editors)
        }
        let editor = try XCTUnwrap(editors(card).first)
        editor.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let marked = editor.markedRange(), selection = editor.selectedRange(), text = editor.string
        for edge in [DockEdge.top, .left, .right] {
            try actions.dock(note.id, edge: edge, displayID: nil, index: 0)
            card.refresh(try XCTUnwrap(store.notes().first))
            panel.docked = true
            panel.present(NoteFrame(x: 8, y: 300, width: edge == .top ? 220 : 240, height: 260), collapsed: false, animate: false)
            card.layoutSubtreeIfNeeded()
            try actions.detach(note.id)
            let restored = try XCTUnwrap(store.notes().first)
            XCTAssertFalse(restored.automaticHeight)
            XCTAssertEqual(restored.placement.freeFrame, NoteFrame(x: -500, y: -80, width: 320, height: 550))
            card.refresh(restored); panel.docked = false
            panel.present(restored.placement.freeFrame!, collapsed: false, animate: false)
            XCTAssertTrue(editors(card).contains { $0 === editor })
            XCTAssertEqual(editor.markedRange(), marked); XCTAssertEqual(editor.selectedRange(), selection)
            XCTAssertEqual(editor.string, text)
        }
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
        XCTAssertEqual(panel.level, .normal)
        panel.resignKey()
        XCTAssertEqual(panel.level.rawValue, Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.choice = .ordinary; panel.modes.allTopmost = true; panel.applyLevel()
        XCTAssertEqual(panel.level, .floating)
        panel.modes.allTopmost = false; panel.applyLevel()
        XCTAssertEqual(panel.level, .normal)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenNone))
        XCTAssertFalse(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        // Only an effectively topmost note joins another app's fullscreen space.
        panel.modes.allTopmost = true; panel.applyLevel()
        XCTAssertEqual(panel.collectionBehavior, [.canJoinAllSpaces, .fullScreenAuxiliary])
        panel.modes.allTopmost = false; panel.choice = .topmost; panel.applyLevel()
        XCTAssertEqual(panel.collectionBehavior, [.canJoinAllSpaces, .fullScreenAuxiliary])
        panel.choice = .ordinary; panel.applyLevel()
        XCTAssertEqual(panel.collectionBehavior, [.canJoinAllSpaces, .fullScreenNone])
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
    @MainActor
    func testRolloverDefersMarkedCompletedRowThenFlushesAndKeepsUnfinishedEditor() throws {
        _ = NSApplication.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        var now = ISO8601DateFormatter().date(from: "2026-11-06T03:59:59Z")!
        let store = try Store(url: url, clock: { now }); defer { try? store.close() }
        let actions = NoteActions(store: store, clock: { now })
        let calendar = try BusinessCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        let note = try actions.createNote()
        let done = try XCTUnwrap(store.items(in: note.id).first)
        try actions.text(done.id, in: note.id, "完成")
        try actions.toggle(done.id, in: note.id)
        let todo = try actions.add(in: note.id)
        try actions.text(todo.id, in: note.id, "继续")
        let panel = NotePanel(origin: .zero); defer { panel.close() }
        let card = NoteCardView(note: note, actions: actions, changed: {}, undoDelete: { false }, failure: { XCTFail("\($0)") })
        panel.contentView = card
        func editors(_ view: NSView) -> [NoteTextView] {
            (view as? NoteTextView).map { [$0] } ?? view.subviews.flatMap(editors)
        }
        let completed = try XCTUnwrap(editors(card).first { $0.string == "完成" })
        let unfinished = try XCTUnwrap(editors(card).first { $0.string == "继续" })
        unfinished.setSelectedRange(NSRange(location: 1, length: 0))
        completed.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let text = completed.string, marked = completed.markedRange(), selected = completed.selectedRange()
        try store.rollover(using: calendar)
        now.addTimeInterval(1)
        func prepare() throws -> Bool {
            guard !card.hasMarkedComposition else { return false }
            try card.flushRolloverEdits(); return true
        }
        XCTAssertEqual(try store.rollover(using: calendar, prepareEditing: prepare), .deferredEditing)
        XCTAssertTrue(editors(card).contains { $0 === completed })
        XCTAssertEqual(completed.string, text); XCTAssertEqual(completed.markedRange(), marked)
        XCTAssertEqual(completed.selectedRange(), selected)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(completed)
        completed.unmarkText()
        // Simulate committed editor content not yet delivered to the delegate.
        completed.string = "完成中文"
        guard case let .advanced(snapshot) = try store.rollover(using: calendar, prepareEditing: prepare) else { return XCTFail("rollover") }
        XCTAssertEqual(snapshot.notes[0].items.first { $0.id == done.id }?.text, "完成中文")
        card.refresh(try XCTUnwrap(store.notes().first))
        XCTAssertFalse(editors(card).contains { $0 === completed })
        XCTAssertTrue(editors(card).contains { $0 === unfinished })
        XCTAssertEqual(unfinished.selectedRange(), NSRange(location: 1, length: 0))
        XCTAssertEqual(try store.items(in: note.id).map(\.id), [todo.id])
    }

    @MainActor
    func testRevealAloneHasFullscreenAuxiliaryPolicy() {
        _ = NSApplication.shared
        let reveal = RevealPanel(), ordinary = NotePanel(origin: .zero)
        defer { reveal.close(); ordinary.close() }
        XCTAssertTrue(reveal.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(reveal.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(reveal.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertFalse(reveal.collectionBehavior.contains(.fullScreenNone))
        XCTAssertFalse(ordinary.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(ordinary.collectionBehavior.contains(.fullScreenNone))
        XCTAssertTrue(reveal.canBecomeKey); XCTAssertFalse(reveal.canBecomeMain)
    }

    @MainActor
    func testTwoSurfacesSynchronizeWithoutPassiveFlushOrMarkedReplacement() throws {
        _ = NSApplication.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try Store(url: url); defer { try? store.close() }
        let actions = NoteActions(store: store), note = try actions.createNote()
        let item = try XCTUnwrap(store.items(in: note.id).first)
        try actions.text(item.id, in: note.id, "first")
        let ordinary = NotePanel(origin: .zero), reveal = RevealPanel()
        defer { ordinary.close(); reveal.close() }
        let a = NoteCardView(note: note, actions: actions, changed: {}, undoDelete: { false }, failure: { XCTFail("\($0)") })
        let b = NoteCardView(note: note, actions: actions, changed: {}, undoDelete: { false }, failure: { XCTFail("\($0)") }, reveal: true)
        ordinary.contentView = a; reveal.contentView = b
        func editors(_ view: NSView) -> [NoteTextView] {
            (view as? NoteTextView).map { [$0] } ?? view.subviews.flatMap(editors)
        }
        let first = try XCTUnwrap(editors(a).first), second = try XCTUnwrap(editors(b).first)
        ordinary.makeKeyAndOrderFront(nil); ordinary.makeFirstResponder(first)
        reveal.makeKeyAndOrderFront(nil); reveal.makeFirstResponder(second)
        second.string = "new 中文"
        try b.flushRolloverEdits()
        // An inactive window retains firstResponder: it still must not flush.
        first.string = "stale"
        try a.flushRolloverEdits()
        XCTAssertEqual(try store.items(in: note.id).first?.text, "new 中文")
        a.refresh(try XCTUnwrap(store.notes().first))
        XCTAssertEqual(first.string, "new 中文")
        second.setSelectedRange(NSRange(location: 2, length: 0))
        second.setMarkedText("拼音", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let text = second.string, range = second.markedRange(), selection = second.selectedRange()
        try actions.toggle(item.id, in: note.id)
        b.refresh(try XCTUnwrap(store.notes().first))
        XCTAssertEqual(second.string, text); XCTAssertEqual(second.markedRange(), range)
        XCTAssertEqual(second.selectedRange(), selection)
        XCTAssertTrue(b.hasMarkedComposition)
        XCTAssertFalse(first.undoManager === second.undoManager)
    }

    @MainActor
    func testRevealTitleFieldCompositionIsIncludedInGate() throws {
        _ = NSApplication.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try Store(url: url); defer { try? store.close() }
        let actions = NoteActions(store: store), note = try actions.createNote()
        let panel = RevealPanel(); defer { panel.close() }
        let card = NoteCardView(note: note, actions: actions, changed: {}, undoDelete: { false }, failure: { XCTFail("\($0)") }, reveal: true)
        panel.contentView = card
        let field = try XCTUnwrap(card.subviews.compactMap { $0 as? NoteTitleField }.first)
        panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(field)
        let editor = try XCTUnwrap(field.currentEditor() as? NoteTextView)
        XCTAssertTrue(editor === field.ownedEditor)
        editor.setMarkedText("标题拼音", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(card.hasMarkedComposition)
        let marked = editor.markedRange(), selection = editor.selectedRange(), text = editor.string
        card.refresh(try XCTUnwrap(store.notes().first))
        XCTAssertEqual(editor.string, text); XCTAssertEqual(editor.markedRange(), marked)
        XCTAssertEqual(editor.selectedRange(), selection)
        editor.unmarkText(); editor.string = "已提交标题"
        try card.flushRolloverEdits()
        XCTAssertEqual(try store.notes().first?.title, "已提交标题")
    }

}
