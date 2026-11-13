import Foundation
import DeskNodesCore
import DeskNodesPersistence

public enum EditingCommand: Equatable { case native, addRow, deleteRow }
public enum EditingPolicy {
    public static func command(returnKey: Bool, backspace: Bool, marked: Bool, empty: Bool) -> EditingCommand {
        if marked { return .native }
        if returnKey { return .addRow }
        if backspace && empty { return .deleteRow }
        return .native
    }
}

/// Synchronous presentation actions. No AppKit, scheduling, production path, or history writes.
/// Every deletion is recoverable for strictly less than five seconds; undo restores newest first.
public final class NoteActions {
    public let store: Store
    private let clock: () -> Date
    /// `notes` is one batch deletion: it is undone, and counted, as a single entry.
    private enum Deleted { case item(Item), note(Note, [Item]), notes([(Note, [Item])]) }
    public private(set) var prefersDeletionUndo = false
    private var pending: [(Deleted, Date)] = []
    public init(store: Store, clock: @escaping () -> Date = Date.init) {
        self.store = store; self.clock = clock
    }
    private func recoverable(_ deletedAt: Date) -> Bool {
        let elapsed = clock().timeIntervalSince(deletedAt)
        return elapsed.isFinite && elapsed >= 0 && elapsed < 5
    }
    public var canUndoDeletion: Bool { pending.contains { recoverable($0.1) } }
    /// Deletions still inside their window, newest last (for the toast count).
    public var recoverableDeletionCount: Int { pending.filter { recoverable($0.1) }.count }
    /// Notes in the newest recoverable deletion; 0 when it was an item (for the toast wording).
    public var latestDeletedNoteCount: Int {
        guard let latest = pending.last(where: { recoverable($0.1) }) else { return 0 }
        switch latest.0 {
        case .item: return 0
        case .note: return 1
        case .notes(let notes): return notes.count
        }
    }
    public func invalidateUndoAfterImport() { pending = []; prefersDeletionUndo = false }
    public func expireDeletion() { pending.removeAll { !recoverable($0.1) } }
    /// Typing makes Command-Z mean text undo again, before the debounced save lands.
    public func noteTyping() { prefersDeletionUndo = false }
    /// `automaticHeight: false` keeps the frame's height instead of following the content.
    @discardableResult public func createNote(frame: NoteFrame? = nil, displayID: String? = nil, automaticHeight: Bool = true) throws -> Note {
        try store.transaction { store in
            let retained = try store.notes(includeDeleted: true)
            let maximum = retained.map(\.order).max() ?? -1
            guard maximum < Int.max else { throw StoreError.invalid("note order exhausted") }
            let frame = try (frame ?? NoteFrame(x: 100, y: 100)).bounded()
            let color = NotePalette.next(inUse: retained.filter { $0.deletedAt == nil }.map(\.color),
                                         latest: retained.max { ($0.createdAt, $0.order) < ($1.createdAt, $1.order) }?.color)
            var note = try store.createNote(color: color, placement: .free(frame, displayID: displayID), order: maximum + 1)
            if !automaticHeight { note.automaticHeight = false; try store.update(note) }
            try store.createItem(in: note.id)
            return note
        }
    }
    public func title(_ id: NoteID, _ title: String) throws {
        guard var note = try store.notes().first(where: { $0.id == id }) else { throw StoreError.notFound }
        note.title = title.isEmpty ? nil : title
        try store.update(note)
        prefersDeletionUndo = false
    }
    public func text(_ id: ItemID, in note: NoteID, _ text: String) throws {
        var item = try find(id, in: note); item.text = text; try store.update(item)
        prefersDeletionUndo = false
    }
    public func toggle(_ id: ItemID, in note: NoteID) throws {
        var item = try find(id, in: note); item.completed.toggle(); item.struck = false; try store.update(item)
    }
    /// Strikes out (or restores) an item that will not be done. It stays in the note,
    /// leaves the progress count, and is archived at rollover like a completed one.
    public func strike(_ id: ItemID, in note: NoteID) throws {
        var item = try find(id, in: note); item.struck.toggle(); item.completed = false; try store.update(item)
    }
    @discardableResult public func add(in note: NoteID, after id: ItemID? = nil, text: String = "") throws -> Item {
        try store.transaction { store in
            var rows = try store.items(in: note)
            let index: Int
            if let id {
                guard let found = rows.firstIndex(where: { $0.id == id }) else { throw StoreError.notFound }
                index = found + 1
            } else { index = rows.count }
            let item = try store.createItem(in: note, text: text, order: rows.count)
            rows.insert(item, at: index)
            try reorder(note, ids: rows.map(\.id))
            return try find(item.id, in: note)
        }
    }
    public func reorder(_ note: NoteID, ids: [ItemID]) throws {
        try store.transaction { store in
            let rows = try store.items(in: note)
            guard Set(ids).count == ids.count, Set(ids) == Set(rows.map(\.id)) else {
                throw StoreError.invalid("same-note permutation required")
            }
            for (index, id) in ids.enumerated() {
                var row = rows.first(where: { $0.id == id })!
                row.order = index; try store.update(row)
            }
        }
    }
    public func deleteItem(_ id: ItemID, in note: NoteID) throws {
        let now = try deletionTime()
        let original = try store.transaction { store -> Item in
            let item = try find(id, in: note); try store.deleteItem(id); return item
        }
        pending.append((.item(original), now))
        prefersDeletionUndo = true
    }
    /// Removing a row that never held text is an editing gesture, not a deletion:
    /// no toast, no undo entry and no history tombstone.
    public func discardBlankItem(_ id: ItemID, in note: NoteID) throws {
        _ = try find(id, in: note)
        try store.discardBlankItem(id)
    }
    /// Drops blank rows left behind by Return, but always keeps one row to type into.
    public func pruneBlankItems(in note: NoteID, keeping focused: ItemID? = nil) throws {
        try store.transaction { store in
            var rows = try store.items(in: note)
            for row in rows where row.id != focused && row.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard rows.count > 1 else { break }
                try store.discardBlankItem(row.id)
                rows.removeAll { $0.id == row.id }
            }
        }
    }
    public func deleteNote(_ id: NoteID) throws {
        let now = try deletionTime()
        let original = try store.transaction { store -> (Note, [Item]) in
            guard let note = try store.notes().first(where: { $0.id == id }) else { throw StoreError.notFound }
            let items = try store.items(in: id, includeDeleted: true)
            try store.deleteNote(id); return (note, items)
        }
        pending.append((.note(original.0, original.1), now))
        prefersDeletionUndo = true
    }
    /// Deletes several notes in one transaction; one undo restores all of them.
    public func deleteNotes(_ ids: [NoteID]) throws {
        guard ids.count > 1 else { if let id = ids.first { try deleteNote(id) }; return }
        let now = try deletionTime()
        let originals = try store.transaction { store -> [(Note, [Item])] in
            let notes = try store.notes()
            return try ids.map { id in
                guard let note = notes.first(where: { $0.id == id }) else { throw StoreError.notFound }
                let items = try store.items(in: id, includeDeleted: true)
                try store.deleteNote(id); return (note, items)
            }
        }
        pending.append((.notes(originals), now))
        prefersDeletionUndo = true
    }
    /// Restores the newest deletion still inside its window. A conflicting entry is dropped.
    @discardableResult public func undoDeletion() throws -> Bool {
        expireDeletion()
        guard let latest = pending.popLast() else { return false }
        switch latest.0 {
        case .item(let item): try store.restoreItem(item)
        case .note(let note, let items): try store.restoreNote(note, items: items)
        case .notes(let notes): try store.transaction { store in for (note, items) in notes { try store.restoreNote(note, items: items) } }
        }
        return true
    }
    /// The "最近删除" list as of now (the injected clock).
    public func recentlyDeleted() throws -> RecentlyDeleted { try store.recentlyDeleted(now: clock()) }
    /// Restores from the recently-deleted list; a toast entry for the same deletion is retired
    /// so a later Command-Z cannot fail on an already restored row.
    public func restoreDeletedNote(_ id: NoteID) throws {
        try store.restoreDeletedNote(id)
        pending = pending.compactMap { entry in
            switch entry.0 {
            case .note(let note, _) where note.id == id: return nil
            case .notes(let notes):
                let rest = notes.filter { $0.0.id != id }
                return rest.isEmpty ? nil : (.notes(rest), entry.1)
            default: return entry
            }
        }
    }
    public func restoreDeletedItem(_ id: ItemID) throws {
        try store.restoreDeletedItem(id)
        pending.removeAll { if case .item(let item) = $0.0 { return item.id == id }; return false }
    }
    private func deletionTime() throws -> Date {
        let now = clock()
        guard now.timeIntervalSince1970.isFinite else { throw StoreError.invalid("clock") }
        return now
    }
    private func find(_ id: ItemID, in note: NoteID) throws -> Item {
        guard let item = try store.items(in: note).first(where: { $0.id == id }) else { throw StoreError.notFound }
        return item
    }
}
