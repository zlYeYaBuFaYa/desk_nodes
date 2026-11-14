import Foundation

/// User deletions still inside the recovery period. Sealed history is never touched:
/// a restore only clears the live tombstone, exactly like a toast undo.
public struct RecentlyDeleted: Equatable, Sendable {
    public struct DeletedNote: Equatable, Sendable {
        public let note: Note
        /// Rows removed together with the note (same deletion instant), non-blank only.
        public let items: [Item]
    }
    public struct DeletedItem: Equatable, Sendable {
        public let item: Item
        /// The live note the row will return to.
        public let note: Note
    }
    public static let retentionDays = 30
    public var notes: [DeletedNote] = []
    public var items: [DeletedItem] = []
    public var isEmpty: Bool { notes.isEmpty && items.isEmpty }
    public init(notes: [DeletedNote] = [], items: [DeletedItem] = []) { self.notes = notes; self.items = items }
}

extension Store {
    public func recentlyDeleted(now: Date) throws -> RecentlyDeleted {
        try locked {
            let cutoff = now.addingTimeInterval(-Double(RecentlyDeleted.retentionDays) * 86_400)
            let all = try notes(includeDeleted: true)
            var result = RecentlyDeleted()
            for note in all {
                let rows = try items(in: note.id, includeDeleted: true).filter {
                    $0.archivedDay == nil && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                if let deleted = note.deletedAt {
                    guard deleted >= cutoff else { continue }
                    result.notes.append(.init(note: note, items: rows.filter { $0.deletedAt == deleted }))
                } else {
                    for row in rows { if let at = row.deletedAt, at >= cutoff { result.items.append(.init(item: row, note: note)) } }
                }
            }
            result.notes.sort { ($0.note.deletedAt!, $0.note.id.rawValue.uuidString) > ($1.note.deletedAt!, $1.note.id.rawValue.uuidString) }
            result.items.sort { ($0.item.deletedAt!, $0.item.id.rawValue.uuidString) > ($1.item.deletedAt!, $1.item.id.rawValue.uuidString) }
            return result
        }
    }

    /// How many entries `recentlyDeleted(now:)` lists, counted in SQL without loading them:
    /// deleted notes, plus non-blank, unarchived rows deleted from live notes. Blank means
    /// only the whitespace Swift trims in practice (ASCII, NBSP and the ideographic space).
    public func recentlyDeletedCount(now: Date) throws -> Int {
        try locked {
            let cutoff = SQLValue.date(now.addingTimeInterval(-Double(RecentlyDeleted.retentionDays) * 86_400))
            let blank = "' ' || char(9, 10, 11, 12, 13, 160, 12288)"
            let rows = try db.query("""
                SELECT (SELECT COUNT(*) FROM notes WHERE deleted IS NOT NULL AND deleted>=?)
                     + (SELECT COUNT(*) FROM items JOIN notes ON notes.id=items.note_id
                        WHERE notes.deleted IS NULL AND items.deleted IS NOT NULL AND items.deleted>=?
                          AND trim(items.text, \(blank)) <> ''
                          AND NOT EXISTS (SELECT 1 FROM item_archives WHERE item_id=items.id))
                """, [cutoff, cutoff])
            return rows.first?[0].flatMap { Int($0) } ?? 0
        }
    }

    /// Brings a deleted note back with the rows deleted together with it. Rows deleted
    /// individually before the note stay deleted (they remain listed separately).
    public func restoreDeletedNote(_ id: NoteID) throws {
        try transaction { _ in
            let key = SQLValue.text(id.rawValue.uuidString)
            guard let row = try db.query("SELECT deleted FROM notes WHERE id=? AND deleted IS NOT NULL", [key]).first,
                  let deleted = row[0].flatMap(Double.init) else { throw StoreError.notFound }
            let now = try timestamp()
            let together = "note_id=? AND deleted=? AND NOT EXISTS (SELECT 1 FROM item_archives WHERE item_id=items.id)"
            try db.run("DELETE FROM pending_deleted_items WHERE item_id IN (SELECT id FROM items WHERE \(together))", [key, .number(deleted)])
            try db.run("UPDATE items SET deleted=NULL,updated=? WHERE \(together)", [.date(now), key, .number(deleted)])
            try db.run("DELETE FROM pending_deleted_notes WHERE note_id=?", [key])
            try db.run("UPDATE notes SET deleted=NULL,updated=? WHERE id=?", [.date(now), key])
            if try items(in: id).isEmpty { try createItem(in: id) } // always something to type into
        }
    }

    /// Returns a deleted row to the end of its (live) note.
    public func restoreDeletedItem(_ id: ItemID) throws {
        try transaction { _ in
            let key = SQLValue.text(id.rawValue.uuidString)
            guard let row = try db.query("SELECT note_id FROM items WHERE id=? AND deleted IS NOT NULL AND NOT EXISTS (SELECT 1 FROM item_archives WHERE item_id=items.id)", [key]).first,
                  let note = row[0], let noteID = UUID(uuidString: note) else { throw StoreError.notFound }
            guard try notes().contains(where: { $0.id.rawValue == noteID }) else {
                throw StoreError.invalid("所属便签已删除，请先恢复便签")
            }
            let last = try db.query("SELECT MAX(position) FROM items WHERE note_id=? AND deleted IS NULL", [.text(note)]).first?[0].flatMap { Int($0) } ?? -1
            let now = try timestamp()
            try db.run("DELETE FROM pending_deleted_items WHERE item_id=?", [key])
            try db.run("UPDATE items SET deleted=NULL,position=?,updated=? WHERE id=?", [.integer(Int64(last + 1)), .date(now), key])
        }
    }
}
