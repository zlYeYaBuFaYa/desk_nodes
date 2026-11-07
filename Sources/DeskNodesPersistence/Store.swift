import Foundation
import DeskNodesCore

/// Synchronous, serialized repository. Do not suspend or dispatch to another thread inside
/// transaction closures. Nesting uses savepoints; errors roll back just the relevant scope.
public final class Store {
    private let db: SQLite
    private let lock = NSRecursiveLock()
    private let clock: () -> Date
    private var depth = 0
    public init(url: URL, clock: @escaping () -> Date = Date.init) throws {
        self.clock = clock
        db = try SQLite(url: url)
        try Schema.migrate(db)
    }
    public func close() throws {
        try locked {
            guard depth == 0 else { throw StoreError.invalid("close during transaction") }
            try db.close()
        }
    }
    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }
    @discardableResult public func transaction<T>(_ body: (Store) throws -> T) throws -> T {
        try locked {
            let scope = depth
            try db.run(scope == 0 ? "BEGIN IMMEDIATE" : "SAVEPOINT nested_\(scope)")
            depth += 1
            defer { depth -= 1 }
            do {
                let value = try body(self)
                try db.run(scope == 0 ? "COMMIT" : "RELEASE nested_\(scope)")
                return value
            } catch {
                if scope == 0 { try? db.run("ROLLBACK") }
                else {
                    try? db.run("ROLLBACK TO nested_\(scope)")
                    try? db.run("RELEASE nested_\(scope)")
                }
                throw error
            }
        }
    }
    public func notes(includeDeleted: Bool = false) throws -> [Note] {
        try locked {
            try db.query("SELECT id,title,color,placement,level,position,collapsed,created,updated,deleted FROM notes \(includeDeleted ? "" : "WHERE deleted IS NULL") ORDER BY position,id").map(decodeNote)
        }
    }
    public func items(in noteID: NoteID, includeDeleted: Bool = false) throws -> [Item] {
        try locked {
            try db.query("SELECT id,note_id,text,completed,position,created,updated,deleted FROM items WHERE note_id=? \(includeDeleted ? "" : "AND deleted IS NULL") ORDER BY position,id", [.text(noteID.rawValue.uuidString)]).map(decodeItem)
        }
    }
    @discardableResult public func createNote(title: String? = nil, color: NotePalette = .paper,
                         placement: Placement = .dock(edge: .top, displayID: nil),
                         level: WindowLevel = .desktop, order: Int = 0) throws -> Note {
        try transaction { _ in
            try validate(placement, order: order)
            let now = try timestamp()
            let note = Note(id: NoteID(), title: title, color: color, placement: placement,
                            level: level, order: order, collapsed: false, createdAt: now,
                            updatedAt: now, deletedAt: nil)
            try db.run("INSERT INTO notes VALUES (?,?,?,?,?,?,?,?,?,NULL)",
                       [.text(note.id.rawValue.uuidString), text(title), .text(color.rawValue),
                        .text(try encode(placement)), .text(level.rawValue), .integer(Int64(order)),
                        .number(0), .date(now), .date(now)])
            return note
        }
    }
    public func update(_ note: Note) throws {
        try transaction { _ in
            try validate(note.placement, order: note.order)
            guard try notes().contains(where: { $0.id == note.id }) else { throw StoreError.notFound }
            try db.run("UPDATE notes SET title=?,color=?,placement=?,level=?,position=?,collapsed=?,updated=? WHERE id=?",
                       [text(note.title), .text(note.color.rawValue), .text(try encode(note.placement)),
                        .text(note.level.rawValue), .integer(Int64(note.order)), .number(note.collapsed ? 1 : 0),
                        .date(try timestamp()), .text(note.id.rawValue.uuidString)])
        }
    }
    @discardableResult public func createItem(in noteID: NoteID, text: String = "", completed: Bool = false,
                                               order: Int = 0) throws -> Item {
        try transaction { _ in
            guard order >= 0 else { throw StoreError.invalid("order") }
            guard try notes().contains(where: { $0.id == noteID }) else { throw StoreError.notFound }
            let now = try timestamp()
            let item = Item(id: ItemID(), noteID: noteID, text: text, completed: completed,
                            order: order, createdAt: now, updatedAt: now, deletedAt: nil)
            try db.run("INSERT INTO items VALUES (?,?,?,?,?,?,?,NULL)",
                       [.text(item.id.rawValue.uuidString), .text(noteID.rawValue.uuidString), .text(text),
                        .number(completed ? 1 : 0), .integer(Int64(order)), .date(now), .date(now)])
            return item
        }
    }
    public func update(_ item: Item) throws {
        try transaction { _ in
            guard item.order >= 0 else { throw StoreError.invalid("order") }
            guard try notes().contains(where: { $0.id == item.noteID }),
                  try items(in: item.noteID).contains(where: { $0.id == item.id }) else { throw StoreError.notFound }
            try db.run("UPDATE items SET text=?,completed=?,position=?,updated=? WHERE id=? AND note_id=?",
                       [.text(item.text), .number(item.completed ? 1 : 0), .integer(Int64(item.order)),
                        .date(try timestamp()), .text(item.id.rawValue.uuidString), .text(item.noteID.rawValue.uuidString)])
        }
    }
    /// Soft delete freezes final live content. No physical purge or undo timing policy in N2.
    public func deleteItem(_ id: ItemID) throws {
        try transaction { _ in
            let rows = try db.query("SELECT note_id FROM items WHERE id=? AND deleted IS NULL", [.text(id.rawValue.uuidString)])
            guard !rows.isEmpty else { throw StoreError.notFound }
            let now = try timestamp()
            try db.run("UPDATE items SET deleted=?,updated=? WHERE id=?", [.date(now), .date(now), .text(id.rawValue.uuidString)])
        }
    }
    public func deleteNote(_ id: NoteID) throws {
        try transaction { _ in
            guard try notes().contains(where: { $0.id == id }) else { throw StoreError.notFound }
            let now = try timestamp()
            try db.run("UPDATE items SET deleted=?,updated=? WHERE note_id=? AND deleted IS NULL",
                       [.date(now), .date(now), .text(id.rawValue.uuidString)])
            try db.run("UPDATE notes SET deleted=?,updated=? WHERE id=?", [.date(now), .date(now), .text(id.rawValue.uuidString)])
        }
    }
    /// Restore only an existing tombstone, preserving identity and exact pre-delete timestamps.
    /// Callers retain the original records; history tables are never touched.
    public func restoreItem(_ original: Item) throws {
        try transaction { _ in
            guard original.deletedAt == nil,
                  try notes().contains(where: { $0.id == original.noteID }),
                  let retained = try items(in: original.noteID, includeDeleted: true).first(where: { $0.id == original.id }),
                  retained.deletedAt != nil,
                  retained.text == original.text, retained.completed == original.completed,
                  retained.order == original.order, retained.createdAt == original.createdAt else {
                throw StoreError.invalid("restore item conflict")
            }
            try db.run("UPDATE items SET deleted=NULL,updated=? WHERE id=?",
                       [.date(original.updatedAt), .text(original.id.rawValue.uuidString)])
        }
    }
    public func restoreNote(_ original: Note, items originals: [Item]) throws {
        try transaction { _ in
            guard original.deletedAt == nil,
                  var retained = try notes(includeDeleted: true).first(where: { $0.id == original.id }),
                  retained.deletedAt != nil else { throw StoreError.invalid("restore note conflict") }
            retained.deletedAt = nil
            retained.updatedAt = original.updatedAt
            guard retained == original else { throw StoreError.invalid("restore note conflict") }
            let children = try items(in: original.id, includeDeleted: true)
            guard Set(children.map(\.id)) == Set(originals.map(\.id)),
                  Set(originals.map(\.id)).count == originals.count else { throw StoreError.invalid("restore children") }
            try db.run("UPDATE notes SET deleted=NULL,updated=? WHERE id=?",
                       [.date(original.updatedAt), .text(original.id.rawValue.uuidString)])
            for item in originals {
                guard item.noteID == original.id else { throw StoreError.invalid("restore parent") }
                if item.deletedAt == nil { try restoreItem(item) }
                else if children.first(where: { $0.id == item.id }) != item {
                    throw StoreError.invalid("restore retained child conflict")
                }
            }
        }
    }
    public func settings() throws -> Settings {
        try locked {
            let rows = try db.query("SELECT hour,minute,dock_edge,display_id FROM settings WHERE id='native-settings'")
            guard let row = rows.first, let hour = Int(row[0] ?? ""), let minute = Int(row[1] ?? ""),
                  let edge = DockEdge(rawValue: row[2] ?? "") else { throw StoreError.corrupt("settings") }
            var value = Settings()
            value.rolloverHour = hour; value.rolloverMinute = minute
            value.dockEdge = edge; value.displayID = row[3]
            return value
        }
    }
    public func update(_ settings: Settings) throws {
        try transaction { _ in
            guard (0...23).contains(settings.rolloverHour), (0...59).contains(settings.rolloverMinute) else {
                throw StoreError.invalid("rollover time")
            }
            try db.run("UPDATE settings SET hour=?,minute=?,dock_edge=?,display_id=? WHERE id='native-settings'",
                       [.integer(Int64(settings.rolloverHour)), .integer(Int64(settings.rolloverMinute)),
                        .text(settings.dockEdge.rawValue), text(settings.displayID)])
        }
    }
    /// Captures exactly once; retry returns the original, including its original carry decision.
    /// Does not remove completed items, advance a clock, or infer missed days.
    @discardableResult public func capture(day: HistoryDay, carryingUnfinishedTo target: HistoryDay? = nil) throws -> DailySnapshot {
        try transaction { _ in
            if let existing = try snapshot(day: day) { return existing }
            if let target, target <= day { throw StoreError.invalid("carry destination") }
            // Defer FK checks so the immutable day header seals children last.
            try db.run("PRAGMA defer_foreign_keys = ON")
            let now = try timestamp()
            for note in try notes(includeDeleted: true) {
                try db.run("INSERT INTO snapshot_notes VALUES (?,?,?,?,?,?)",
                           [.text(day.rawValue), .text(note.id.rawValue.uuidString), text(note.title),
                            .text(note.color.rawValue), .integer(Int64(note.order)), .date(note.deletedAt)])
                for item in try items(in: note.id, includeDeleted: true) {
                    let carried = !item.completed && item.deletedAt == nil && note.deletedAt == nil ? target : nil
                    try db.run("INSERT INTO snapshot_items VALUES (?,?,?,?,?,?,?,?)",
                               [.text(day.rawValue), .text(note.id.rawValue.uuidString), .text(item.id.rawValue.uuidString),
                                .text(item.text), .number(item.completed ? 1 : 0), .integer(Int64(item.order)),
                                .date(item.deletedAt), text(carried?.rawValue)])
                }
            }
            try db.run("INSERT INTO days VALUES (?,?)", [.text(day.rawValue), .date(now)])
            guard let result = try snapshot(day: day) else { throw StoreError.corrupt("capture") }
            return result
        }
    }
    public func snapshot(day: HistoryDay) throws -> DailySnapshot? {
        try locked {
            guard let header = try db.query("SELECT captured FROM days WHERE day=?", [.text(day.rawValue)]).first else { return nil }
            let notes = try db.query("SELECT note_id,title,color,position,deleted FROM snapshot_notes WHERE day=? ORDER BY position,note_id", [.text(day.rawValue)]).map { row -> SnapshotNote in
                guard let color = NotePalette(rawValue: row[2] ?? "") else { throw StoreError.corrupt("snapshot color") }
                let id: NoteID = try identity(row[0])
                let items = try db.query("SELECT item_id,text,completed,position,deleted,carried_to FROM snapshot_items WHERE day=? AND note_id=? ORDER BY position,item_id", [.text(day.rawValue), .text(id.rawValue.uuidString)]).map { item in
                    SnapshotItem(id: try identity(item[0]), text: item[1] ?? "", completed: item[2] == "1",
                                 order: try integer(item[3]), deletedAt: try date(item[4]),
                                 carriedTo: try item[5].map(HistoryDay.init))
                }
                return SnapshotNote(id: id, title: row[1], color: color, order: try integer(row[3]),
                                    deletedAt: try date(row[4]), items: items)
            }
            guard let captured = try date(header[0]) else { throw StoreError.corrupt("capture time") }
            return DailySnapshot(day: day, capturedAt: captured, notes: notes)
        }
    }
    private func timestamp() throws -> Date {
        let now = clock()
        guard now.timeIntervalSince1970.isFinite else { throw StoreError.invalid("clock") }
        return now
    }
    private func validate(_ placement: Placement, order: Int) throws {
        guard order >= 0 else { throw StoreError.invalid("order") }
        if case let .free(_, x, y, width, height) = placement {
            guard [x,y,width,height].allSatisfy(\.isFinite), width > 0, height > 0 else { throw StoreError.invalid("frame") }
        }
    }
    private func text(_ value: String?) -> SQLValue { value.map(SQLValue.text) ?? .null }
    private func encode(_ placement: Placement) throws -> String {
        String(decoding: try JSONEncoder().encode(placement), as: UTF8.self)
    }
    private func identity<K>(_ value: String?) throws -> StableID<K> {
        guard let value, let uuid = UUID(uuidString: value) else { throw StoreError.corrupt("identity") }
        return StableID(uuid)
    }
    private func integer(_ value: String?) throws -> Int {
        guard let value, let result = Int(value) else { throw StoreError.corrupt("integer") }
        return result
    }
    private func date(_ value: String?) throws -> Date? {
        guard let value else { return nil }
        guard let number = Double(value), number.isFinite else { throw StoreError.corrupt("timestamp") }
        return Date(timeIntervalSince1970: number)
    }
    private func decodeNote(_ row: [String?]) throws -> Note {
        guard let color = NotePalette(rawValue: row[2] ?? ""), let level = WindowLevel(rawValue: row[4] ?? ""),
              let placement = row[3], let created = try date(row[7]), let updated = try date(row[8]) else { throw StoreError.corrupt("note") }
        return Note(id: try identity(row[0]), title: row[1], color: color,
                    placement: try JSONDecoder().decode(Placement.self, from: Data(placement.utf8)),
                    level: level, order: try integer(row[5]), collapsed: row[6] == "1",
                    createdAt: created, updatedAt: updated, deletedAt: try date(row[9]))
    }
    private func decodeItem(_ row: [String?]) throws -> Item {
        guard let created = try date(row[5]), let updated = try date(row[6]) else { throw StoreError.corrupt("item") }
        return Item(id: try identity(row[0]), noteID: try identity(row[1]), text: row[2] ?? "", completed: row[3] == "1",
                    order: try integer(row[4]), createdAt: created, updatedAt: updated, deletedAt: try date(row[7]))
    }
}
