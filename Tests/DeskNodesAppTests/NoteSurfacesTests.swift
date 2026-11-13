import AppKit
import XCTest
import DeskNodesActions
import DeskNodesPersistence
@testable import DeskNodesApp

final class NoteSurfacesTests: XCTestCase {
    private var url: URL!
    private var store: Store!
    private var actions: NoteActions!
    private var surfaces: NoteSurfaces!
    private var dockCalls: [(changed: Set<NoteID>?, strips: Bool)] = []

    @MainActor override func setUpWithError() throws {
        _ = NSApplication.shared
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        store = try Store(url: url); actions = NoteActions(store: store)
        surfaces = NoteSurfaces(actions: actions, changed: {}, undo: { false }, canMutate: { true }, failure: { XCTFail("\($0)") })
        surfaces.layoutDock = { [unowned self] _, _, changed, strips in dockCalls.append((changed, strips)) }
    }
    @MainActor override func tearDownWithError() throws {
        surfaces.discardAll(); try store.close()
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
    }
    @MainActor private func editors(_ id: NoteID) -> [NoteTextView] {
        func walk(_ view: NSView) -> [NoteTextView] { (view as? NoteTextView).map { [$0] } ?? view.subviews.flatMap(walk) }
        return (surfaces.panels[id].flatMap { $0.contentView }.map(walk) ?? []).filter { !$0.isFieldEditor } // item rows only
    }

    @MainActor func testUnchangedStoreTouchesNothing() throws {
        _ = try actions.createNote(); _ = try actions.createNote()
        XCTAssertEqual(try surfaces.refresh(.all).pass.created.count, 2)
        dockCalls = []
        let pass = try surfaces.refresh().pass
        XCTAssertTrue(pass.touched.isEmpty && pass.removed.isEmpty)
        XCTAssertFalse(pass.stripsLaidOut)
        XCTAssertTrue(dockCalls.isEmpty, "no dock work when nothing changed")
    }

    @MainActor func testEditingOneNoteRefreshesOnlyThatNoteAndKeepsEditors() throws {
        let a = try actions.createNote(), b = try actions.createNote()
        try surfaces.refresh(.all)
        let editorsA = editors(a.id), editorsB = editors(b.id)
        let item = try XCTUnwrap(store.items(in: a.id).first)
        try actions.text(item.id, in: a.id, "新的内容")
        dockCalls = []
        let pass = try surfaces.refresh().pass
        XCTAssertEqual(pass.updated, [a.id])
        XCTAssertEqual(dockCalls.count, 1)
        XCTAssertEqual(dockCalls[0].changed, [a.id]); XCTAssertFalse(dockCalls[0].strips, "free note: strips untouched")
        XCTAssertTrue(zip(editors(a.id), editorsA).allSatisfy { $0 === $1 }, "editors are never replaced")
        XCTAssertTrue(zip(editors(b.id), editorsB).allSatisfy { $0 === $1 })
        XCTAssertEqual(editors(a.id).first?.string, "新的内容")
    }

    @MainActor func testItemChangesAreSeenWithoutTouchingTheNoteRow() throws {
        let note = try actions.createNote()
        try surfaces.refresh(.all)
        let row = try actions.add(in: note.id, text: "第二行")
        XCTAssertEqual(try surfaces.refresh().pass.updated, [note.id])
        try actions.toggle(row.id, in: note.id)
        XCTAssertEqual(try surfaces.refresh().pass.updated, [note.id])
        try actions.discardBlankItem(try XCTUnwrap(store.items(in: note.id).first).id, in: note.id)
        XCTAssertEqual(try surfaces.refresh().pass.updated, [note.id])
        XCTAssertEqual(editors(note.id).map(\.string), ["第二行"])
    }

    @MainActor func testDockedChangesAndRemovalsRelayoutStrips() throws {
        let free = try actions.createNote(), docked = try actions.createNote()
        try actions.dock(docked.id, edge: .top, displayID: nil, index: 0)
        try surfaces.refresh(.all)
        XCTAssertTrue(surfaces.panels[docked.id] != nil)
        try actions.appearance(docked.id, collapsed: true)
        XCTAssertTrue(try surfaces.refresh().pass.stripsLaidOut)
        try actions.appearance(free.id, color: .mint)
        XCTAssertFalse(try surfaces.refresh().pass.stripsLaidOut)
        try actions.deleteNote(docked.id)
        let pass = try surfaces.refresh().pass
        XCTAssertEqual(pass.removed, [docked.id]); XCTAssertTrue(pass.stripsLaidOut)
        XCTAssertNil(surfaces.panels[docked.id])
    }

    @MainActor func testLayoutScopeRelaysStripsWithoutDataChanges() throws {
        _ = try actions.createNote()
        try surfaces.refresh(.all); dockCalls = []
        let pass = try surfaces.refresh(.layout).pass
        XCTAssertTrue(pass.touched.isEmpty)
        XCTAssertEqual(dockCalls.count, 1); XCTAssertTrue(dockCalls[0].strips)
    }

    @MainActor func testUndoAndRestoreAreDetectedByTheDiff() throws {
        let note = try actions.createNote()
        try surfaces.refresh(.all)
        try actions.deleteNote(note.id)
        XCTAssertEqual(try surfaces.refresh().pass.removed, [note.id])
        XCTAssertTrue(try actions.undoDeletion())
        XCTAssertEqual(try surfaces.refresh().pass.created, [note.id])
    }
}
