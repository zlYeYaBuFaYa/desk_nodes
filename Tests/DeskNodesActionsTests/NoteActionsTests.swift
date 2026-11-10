import XCTest
import Foundation
import DeskNodesPersistence
@testable import DeskNodesActions

final class NoteActionsTests: XCTestCase {
    private var directory: URL!
    private var store: Store!
    private var actions: NoteActions!
    private var now = Date(timeIntervalSince1970: 1000)
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        store = try Store(url: directory.appendingPathComponent("test.sqlite"), clock: { [unowned self] in now })
        actions = NoteActions(store: store, clock: { [unowned self] in now })
    }
    override func tearDownWithError() throws {
        try store.close(); try FileManager.default.removeItem(at: directory)
    }
    func testCRUDBindingAndReopen() throws {
        let note = try actions.createNote()
        XCTAssertNil(note.title)
        let first = try XCTUnwrap(store.items(in: note.id).first)
        try actions.title(note.id, "中文 👩🏽‍💻")
        try actions.text(first.id, in: note.id, "组合e\u{301}\0中文")
        try actions.toggle(first.id, in: note.id)
        let next = try actions.add(in: note.id, after: first.id)
        XCTAssertEqual(try store.items(in: note.id).map(\.id), [first.id, next.id])
        try store.close()
        store = try Store(url: directory.appendingPathComponent("test.sqlite"))
        XCTAssertEqual(try store.notes().first?.title, "中文 👩🏽‍💻")
        XCTAssertEqual(try store.items(in: note.id).first?.text, "组合e\u{301}\0中文")
        XCTAssertEqual(try store.items(in: note.id).first?.completed, true)
    }
    func testOptionalTitleAndInsertPositions() throws {
        let note = try actions.createNote()
        try actions.title(note.id, ""); XCTAssertNil(try store.notes().first?.title)
        let first = try XCTUnwrap(store.items(in: note.id).first)
        let last = try actions.add(in: note.id)
        let middle = try actions.add(in: note.id, after: first.id)
        XCTAssertEqual(try store.items(in: note.id).map(\.id), [first.id, middle.id, last.id])
        XCTAssertEqual(try store.items(in: note.id).map(\.order), [0,1,2])
    }
    func testReorderRejectsCrossNoteDuplicatesAndMissingIDsAtomically() throws {
        let note = try actions.createNote(); let other = try actions.createNote()
        let a = try XCTUnwrap(store.items(in: note.id).first)
        let b = try actions.add(in: note.id)
        let foreign = try XCTUnwrap(store.items(in: other.id).first)
        for ids in [[a.id,a.id], [a.id], [a.id,foreign.id]] {
            XCTAssertThrowsError(try actions.reorder(note.id, ids: ids))
            XCTAssertEqual(try store.items(in: note.id).map(\.id), [a.id,b.id])
        }
        try actions.reorder(note.id, ids: [b.id,a.id])
        XCTAssertEqual(try store.items(in: note.id).map(\.id), [b.id,a.id])
    }
    func testItemUndoExactDataOrderAndHistory() throws {
        let note = try actions.createNote()
        let item = try XCTUnwrap(store.items(in: note.id).first)
        try actions.text(item.id, in: note.id, "保留")
        try actions.toggle(item.id, in: note.id)
        let original = try store.items(in: note.id)
        let day = try HistoryDay("2026-11-06"); let snapshot = try store.capture(day: day)
        now.addTimeInterval(1); try actions.deleteItem(item.id, in: note.id)
        XCTAssertTrue(try store.items(in: note.id).isEmpty)
        now.addTimeInterval(4.999)
        XCTAssertTrue(try actions.undoDeletion())
        XCTAssertEqual(try store.items(in: note.id), original)
        XCTAssertEqual(try store.snapshot(day: day), snapshot)
        XCTAssertFalse(try actions.undoDeletion())
    }
    func testNoteUndoIncludesEarlierTombstonesAndExactMetadata() throws {
        let note = try actions.createNote()
        let old = try actions.add(in: note.id)
        try actions.deleteItem(old.id, in: note.id)
        let originalItems = try store.items(in: note.id, includeDeleted: true)
        let originalNotes = try store.notes()
        now.addTimeInterval(1); try actions.deleteNote(note.id)
        XCTAssertTrue(try store.notes().isEmpty)
        XCTAssertTrue(try actions.undoDeletion())
        XCTAssertEqual(try store.notes(), originalNotes)
        XCTAssertEqual(try store.items(in: note.id, includeDeleted: true), originalItems)
    }
    func testExpiryAtFiveSecondsAndNoResurrection() throws {
        let note = try actions.createNote()
        try actions.deleteNote(note.id)
        now.addTimeInterval(5)
        XCTAssertFalse(actions.canUndoDeletion)
        actions.expireDeletion(); now.addTimeInterval(-1)
        XCTAssertFalse(try actions.undoDeletion())
        XCTAssertTrue(try store.notes().isEmpty)
    }
    func testLatestDeletionOnlyAndFailedActionDoesNotReplaceUndo() throws {
        let a = try actions.createNote(); let b = try actions.createNote()
        try actions.deleteNote(a.id); try actions.deleteNote(b.id)
        XCTAssertThrowsError(try actions.deleteNote(a.id))
        XCTAssertTrue(try actions.undoDeletion())
        XCTAssertEqual(try store.notes().map(\.id), [b.id])
    }
    func testRestoreConflictRollsBackWholeNote() throws {
        let note = try actions.createNote()
        let original = try store.items(in: note.id)
        try store.deleteNote(note.id)
        var invalid = original[0]; invalid.text = "conflict"
        XCTAssertThrowsError(try store.restoreNote(note, items: [invalid]))
        XCTAssertTrue(try store.notes().isEmpty)
        XCTAssertNotNil(try store.items(in: note.id, includeDeleted: true).first?.deletedAt)
        try store.restoreNote(note, items: original)
        XCTAssertEqual(try store.items(in: note.id), original)
        XCTAssertThrowsError(try store.restoreNote(note, items: original))
    }
    func testInvalidClockAndClockReversalFailClosed() throws {
        let note = try actions.createNote(); try actions.deleteNote(note.id)
        now.addTimeInterval(-1); XCTAssertFalse(actions.canUndoDeletion)
        actions.expireDeletion(); now.addTimeInterval(1); XCTAssertFalse(actions.canUndoDeletion)
        now = Date(timeIntervalSince1970: .infinity)
        XCTAssertThrowsError(try actions.deleteNote(note.id))
    }
    func testTextUndoPriorityDoesNotRemoveToastRecovery() throws {
        let note = try actions.createNote()
        let first = try XCTUnwrap(store.items(in: note.id).first)
        let second = try actions.add(in: note.id)
        try actions.deleteItem(second.id, in: note.id)
        XCTAssertTrue(actions.prefersDeletionUndo)
        try actions.text(first.id, in: note.id, "new typing")
        XCTAssertFalse(actions.prefersDeletionUndo)
        XCTAssertTrue(actions.canUndoDeletion)
        XCTAssertTrue(try actions.undoDeletion())
        XCTAssertEqual(try store.items(in: note.id).count, 2)
    }
    func testUndoAfterExpiryCannotTouchSealedHistory() throws {
        let note = try actions.createNote()
        let day = try HistoryDay("2026-11-06")
        let before = try store.capture(day: day)
        try actions.deleteNote(note.id)
        now.addTimeInterval(5)
        XCTAssertFalse(try actions.undoDeletion())
        XCTAssertEqual(try store.snapshot(day: day), before)
        XCTAssertNotNil(try store.notes(includeDeleted: true).first?.deletedAt)
    }
    func testRestoreDoesNotRewriteSnapshotOfDeletedData() throws {
        let note = try actions.createNote()
        try actions.deleteNote(note.id)
        let day = try HistoryDay("2026-11-06")
        let deletedSnapshot = try store.capture(day: day)
        XCTAssertNotNil(deletedSnapshot.notes.first?.deletedAt)
        XCTAssertTrue(try actions.undoDeletion())
        XCTAssertEqual(try store.snapshot(day: day), deletedSnapshot)
    }
    func testNewNotesDoNotReusePendingDeletedOrder() throws {
        let first = try actions.createNote(); let second = try actions.createNote()
        try actions.deleteNote(first.id)
        let third = try actions.createNote()
        XCTAssertGreaterThan(third.order, second.order)
        XCTAssertTrue(try actions.undoDeletion())
        XCTAssertEqual(try store.notes().map(\.id), [first.id, second.id, third.id])
    }
    func testReorderPartialWriteRollsBackOnInvalidClock() throws {
        var calls = 0
        var failAt = Int.max
        let isolated = try Store(url: directory.appendingPathComponent("rollback.sqlite"), clock: {
            calls += 1
            return Date(timeIntervalSince1970: calls == failAt ? .nan : 1000)
        })
        defer { try? isolated.close() }
        let service = NoteActions(store: isolated)
        let note = try service.createNote()
        let second = try service.add(in: note.id)
        let before = try isolated.items(in: note.id)
        failAt = calls + 2
        XCTAssertThrowsError(try service.reorder(note.id, ids: [second.id, before[0].id]))
        XCTAssertEqual(try isolated.items(in: note.id), before)
    }
    func testCompositionCommandMatrix() {
        for empty in [false,true] {
            XCTAssertEqual(EditingPolicy.command(returnKey: true, backspace: false, marked: true, empty: empty), .native)
            XCTAssertEqual(EditingPolicy.command(returnKey: false, backspace: true, marked: true, empty: empty), .native)
            XCTAssertEqual(EditingPolicy.command(returnKey: true, backspace: false, marked: false, empty: empty), .addRow)
            XCTAssertEqual(EditingPolicy.command(returnKey: false, backspace: true, marked: false, empty: empty), empty ? .deleteRow : .native)
        }
        XCTAssertEqual(EditingPolicy.command(returnKey: false, backspace: false, marked: false, empty: true), .native)
    }
}

final class DeletionStackTests: XCTestCase {
    private var directory: URL!
    private var store: Store!
    private var actions: NoteActions!
    private var now = Date(timeIntervalSince1970: 1000)
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        store = try Store(url: directory.appendingPathComponent("test.sqlite"), clock: { [unowned self] in now })
        actions = NoteActions(store: store, clock: { [unowned self] in now })
    }
    override func tearDownWithError() throws { try store.close(); try FileManager.default.removeItem(at: directory) }

    func testEveryDeletionInsideItsWindowIsRecoverableNewestFirst() throws {
        let a = try actions.createNote(), b = try actions.createNote()
        try actions.deleteNote(a.id); now.addTimeInterval(2); try actions.deleteNote(b.id)
        XCTAssertEqual(actions.recoverableDeletionCount, 2)
        XCTAssertTrue(try actions.undoDeletion())
        XCTAssertEqual(try store.notes().map(\.id), [b.id])
        XCTAssertTrue(try actions.undoDeletion())
        XCTAssertEqual(try store.notes().map(\.id), [a.id, b.id])
        XCTAssertFalse(try actions.undoDeletion())
    }
    func testEachDeletionExpiresOnItsOwnClock() throws {
        let a = try actions.createNote(), b = try actions.createNote()
        try actions.deleteNote(a.id); now.addTimeInterval(3); try actions.deleteNote(b.id)
        now.addTimeInterval(2.5) // a: 5.5s, b: 2.5s
        XCTAssertEqual(actions.recoverableDeletionCount, 1)
        XCTAssertTrue(try actions.undoDeletion())
        XCTAssertFalse(try actions.undoDeletion())
        XCTAssertEqual(try store.notes().map(\.id), [b.id])
    }
    func testBlankRowsAreDiscardedSilentlyAndOneRowAlwaysRemains() throws {
        let note = try actions.createNote()
        let first = try XCTUnwrap(store.items(in: note.id).first)
        let second = try actions.add(in: note.id, after: first.id)
        try actions.discardBlankItem(second.id, in: note.id)
        XCTAssertFalse(actions.canUndoDeletion)
        _ = try actions.add(in: note.id); _ = try actions.add(in: note.id)
        try actions.pruneBlankItems(in: note.id)
        let remaining = try store.items(in: note.id)
        XCTAssertEqual(remaining.count, 1)
        let text = try actions.add(in: note.id, after: remaining[0].id, text: "粘贴的行")
        _ = try actions.add(in: note.id)
        try actions.pruneBlankItems(in: note.id)
        XCTAssertEqual(try store.items(in: note.id).map(\.id), [text.id])
    }
    func testCreateNoteAppliesFrameAndDisplayInOneTransaction() throws {
        let note = try actions.createNote(frame: NoteFrame(x: -800, y: 300, width: 900, height: 50), displayID: "屏幕")
        XCTAssertEqual(note.placement, .free(displayID: "屏幕", x: -800, y: 300, width: 400, height: 120))
    }
    func testTypingPrefersTextUndoBeforeTheSaveLands() throws {
        let note = try actions.createNote()
        let item = try actions.add(in: note.id, text: "x")
        try actions.deleteItem(item.id, in: note.id)
        XCTAssertTrue(actions.prefersDeletionUndo)
        actions.noteTyping()
        XCTAssertFalse(actions.prefersDeletionUndo)
        XCTAssertTrue(actions.canUndoDeletion)
    }
}
