import Foundation
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
/// A single latest deletion is recoverable for strictly less than five seconds.
public final class NoteActions {
    public let store: Store
    private let clock: () -> Date
    private enum Deleted { case item(Item), note(Note, [Item]) }
    public private(set) var prefersDeletionUndo = false
    private var pending: (Deleted, Date)?
    public init(store: Store, clock: @escaping () -> Date = Date.init) {
        self.store = store; self.clock = clock
    }
    public var canUndoDeletion: Bool {
        guard let pending else { return false }
        let elapsed = clock().timeIntervalSince(pending.1)
        return elapsed.isFinite && elapsed >= 0 && elapsed < 5
    }
    public func expireDeletion() { if !canUndoDeletion { pending = nil } }
    @discardableResult public func createNote() throws -> Note {
        try store.transaction { store in
            let retained = try store.notes(includeDeleted: true)
            let maximum = retained.map(\.order).max() ?? -1
            guard maximum < Int.max else { throw StoreError.invalid("note order exhausted") }
            let note = try store.createNote(order: maximum + 1)
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
        var item = try find(id, in: note); item.completed.toggle(); try store.update(item)
    }
    @discardableResult public func add(in note: NoteID, after id: ItemID? = nil) throws -> Item {
        try store.transaction { store in
            var rows = try store.items(in: note)
            let index: Int
            if let id {
                guard let found = rows.firstIndex(where: { $0.id == id }) else { throw StoreError.notFound }
                index = found + 1
            } else { index = rows.count }
            let item = try store.createItem(in: note, order: rows.count)
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
        pending = (.item(original), now)
        prefersDeletionUndo = true
    }
    public func deleteNote(_ id: NoteID) throws {
        let now = try deletionTime()
        let original = try store.transaction { store -> (Note, [Item]) in
            guard let note = try store.notes().first(where: { $0.id == id }) else { throw StoreError.notFound }
            let items = try store.items(in: id, includeDeleted: true)
            try store.deleteNote(id); return (note, items)
        }
        pending = (.note(original.0, original.1), now)
        prefersDeletionUndo = true
    }
    @discardableResult public func undoDeletion() throws -> Bool {
        guard canUndoDeletion, let pending else { self.pending = nil; return false }
        switch pending.0 {
        case .item(let item): try store.restoreItem(item)
        case .note(let note, let items): try store.restoreNote(note, items: items)
        }
        self.pending = nil
        return true
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
