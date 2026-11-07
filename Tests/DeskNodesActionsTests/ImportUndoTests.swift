import XCTest
import DeskNodesPersistence
@testable import DeskNodesActions

final class ImportUndoTests: XCTestCase {
    func testReplacementInvalidatesSharedDeletionEvenForSameIDs() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try Store(url: url), actions = NoteActions(store: store)
        defer { try? store.close() }
        let note = try actions.createNote()
        try actions.deleteNote(note.id)
        let backup = try Store.validateBackup(store.exportBackup())
        XCTAssertTrue(actions.canUndoDeletion)
        try store.replace(with: backup, confirmed: true)
        actions.invalidateUndoAfterImport()
        XCTAssertFalse(actions.canUndoDeletion); XCTAssertFalse(actions.prefersDeletionUndo)
        XCTAssertFalse(try actions.undoDeletion())
        XCTAssertTrue(try store.notes().isEmpty)
        XCTAssertNotNil(try store.notes(includeDeleted: true).first?.deletedAt)
    }
}
