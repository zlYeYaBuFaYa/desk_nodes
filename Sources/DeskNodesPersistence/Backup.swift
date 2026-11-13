import Foundation

/// Native JSON v1. Explicit fields avoid exposing SQL or the internal placement JSON.
/// Every required collection must be present, even when empty. No Tauri migration.
public struct NativeBackup: Codable, Equatable, Sendable {
    public var format: String
    public var version: Int
    public var schema: Int
    public var notes: [Note]
    public var items: [Item]
    public var history: [DailySnapshot]
    public var settings: BackupSettings
    public var preferences: NativePreferences
    public var checkpoint: BackupCheckpoint?
    public var pendingNotes: [NoteID]
    public var pendingItems: [ItemID]
}
public struct BackupSettings: Codable, Equatable, Sendable {
    public var hour: Int
    public var minute: Int
    public var dockEdge: DockEdge
    public var displayID: String?
    public var edgePreference: EdgePreference
    init(_ settings: Settings) {
        hour = settings.rolloverHour; minute = settings.rolloverMinute
        dockEdge = settings.dockEdge; displayID = settings.displayID; edgePreference = settings.edgePreference
    }
    var value: Settings {
        var value = Settings(); value.rolloverHour = hour; value.rolloverMinute = minute
        value.dockEdge = dockEdge; value.displayID = displayID; value.edgePreference = edgePreference
        return value
    }
}
public struct BackupCheckpoint: Codable, Equatable, Sendable {
    public var activeDay: HistoryDay
    public var highWater: Date
}

/// Owns an isolated, fully validated native database. No source SQL/triggers are accepted.
public final class ValidatedBackup {
    internal let store: Store
    public let contents: NativeBackup
    fileprivate init(store: Store, contents: NativeBackup) { self.store = store; self.contents = contents }
}

extension Store {
    public func exportBackup(prepareEditing: () throws -> Bool = { true }) throws -> Data {
        try transaction { _ in
            guard try prepareEditing() else { throw StoreError.invalid("请先完成输入法组词，再导出备份") }
            let notes = try notes(includeDeleted: true)
            let items = try notes.flatMap { try self.items(in: $0.id, includeDeleted: true) }
            let history = try db.query("SELECT day FROM days ORDER BY day").map { row -> DailySnapshot in
                guard let key = row[0], let snapshot = try snapshot(day: HistoryDay(key)) else { throw StoreError.corrupt("snapshot") }
                return snapshot
            }
            let checkpoint = try rolloverCheckpoint().map { BackupCheckpoint(activeDay: $0.activeDay, highWater: $0.highWater) }
            let pendingNotes: [NoteID] = try db.query("SELECT note_id FROM pending_deleted_notes ORDER BY note_id").map { try backupID($0[0]) }
            let pendingItems: [ItemID] = try db.query("SELECT item_id FROM pending_deleted_items ORDER BY item_id").map { try backupID($0[0]) }
            let result = NativeBackup(format: "local.desknodes.native.backup", version: 1, schema: Schema.version,
                notes: notes, items: items, history: history, settings: BackupSettings(try settings()),
                preferences: try preferences(), checkpoint: checkpoint, pendingNotes: pendingNotes, pendingItems: pendingItems)
            try result.validate()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(result)
        }
    }
    /// Decode/validate before confirmation or touching the destination. The staging DB
    /// enforces all native SQL constraints and seals children by inserting headers last.
    public static func validateBackup(_ data: Data) throws -> ValidatedBackup {
        let value = try JSONDecoder().decode(NativeBackup.self, from: data)
        try value.validate()
        let stage = try Store(staging: ())
        try stage.transaction { _ in
            try stage.db.run("PRAGMA defer_foreign_keys=ON")
            try stage.update(value.settings.value)
            try stage.update(value.preferences)
            for note in value.notes {
                try stage.db.run("INSERT INTO notes (id,title,color,placement,level,position,collapsed,created,updated,deleted,automatic_height,free_restore) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                    [.text(note.id.rawValue.uuidString), stage.text(note.title), .text(note.color.rawValue), .text(try stage.encode(note.placement)), .text(note.level.rawValue), .integer(Int64(note.order)), .integer(note.collapsed ? 1 : 0), .date(note.createdAt), .date(note.updatedAt), .date(note.deletedAt), .integer(note.automaticHeight ? 1 : 0), stage.text(try note.freeRestore.map(stage.encode))])
            }
            for item in value.items {
                try stage.db.run("INSERT INTO items (id,note_id,text,completed,position,created,updated,deleted,struck) VALUES (?,?,?,?,?,?,?,?,?)", [.text(item.id.rawValue.uuidString), .text(item.noteID.rawValue.uuidString), .text(item.text), .integer(item.completed ? 1 : 0), .integer(Int64(item.order)), .date(item.createdAt), .date(item.updatedAt), .date(item.deletedAt), .integer(item.struck ? 1 : 0)])
            }
            for day in value.history {
                for note in day.notes {
                    try stage.db.run("INSERT INTO snapshot_notes VALUES (?,?,?,?,?,?)", [.text(day.day.rawValue), .text(note.id.rawValue.uuidString), stage.text(note.title), .text(note.color.rawValue), .integer(Int64(note.order)), .date(note.deletedAt)])
                    for item in note.items {
                        try stage.db.run("INSERT INTO snapshot_items (day,note_id,item_id,text,completed,position,deleted,carried_to,struck) VALUES (?,?,?,?,?,?,?,?,?)", [.text(day.day.rawValue), .text(note.id.rawValue.uuidString), .text(item.id.rawValue.uuidString), .text(item.text), .integer(item.completed ? 1 : 0), .integer(Int64(item.order)), .date(item.deletedAt), stage.text(item.carriedTo?.rawValue), .integer(item.struck ? 1 : 0)])
                    }
                }
                try stage.db.run("INSERT INTO days VALUES (?,?)", [.text(day.day.rawValue), .date(day.capturedAt)])
            }
            for item in value.items {
                if let day = item.archivedDay { try stage.db.run("INSERT INTO item_archives VALUES (?,?)", [.text(item.id.rawValue.uuidString), .text(day.rawValue)]) }
            }
            if let checkpoint = value.checkpoint {
                try stage.db.run("INSERT INTO rollover_state VALUES (1,?,?)", [.text(checkpoint.activeDay.rawValue), .date(checkpoint.highWater)])
            }
            for id in value.pendingNotes { try stage.db.run("INSERT INTO pending_deleted_notes VALUES (?)", [.text(id.rawValue.uuidString)]) }
            for id in value.pendingItems { try stage.db.run("INSERT INTO pending_deleted_items VALUES (?)", [.text(id.rawValue.uuidString)]) }
            guard try stage.db.query("PRAGMA foreign_key_check").isEmpty,
                  try stage.db.query("PRAGMA integrity_check") == [["ok"]] else { throw StoreError.corrupt("backup integrity") }
        }
        // Read every field through the production decoding path too.
        _ = try stage.exportBackup()
        return ValidatedBackup(store: stage, contents: value)
    }
    /// Explicit confirmation is required even for callers outside the native dialog.
    /// SQLite's backup API holds a destination write transaction and rolls back if
    /// unfinished. The same shared connection survives; no dropped sealing triggers.
    public func replace(with backup: ValidatedBackup, confirmed: Bool,
                        prepareEditing: () throws -> Bool = { true }) throws {
        try replace(with: backup, confirmed: confirmed, prepareEditing: prepareEditing, interruptAfterPage: false)
    }
    internal func replace(with backup: ValidatedBackup, confirmed: Bool,
                          prepareEditing: () throws -> Bool, interruptAfterPage: Bool) throws {
        try locked {
            guard confirmed else { throw StoreError.invalid("import cancelled") }
            guard depth == 0 else { throw StoreError.invalid("import during transaction") }
            guard try prepareEditing() else { throw StoreError.invalid("请先完成输入法组词，再导入备份") }
            try db.replace(from: backup.store.db, interruptAfterPage: interruptAfterPage)
        }
    }
    private func backupID<K>(_ value: String?) throws -> StableID<K> {
        guard let value, let uuid = UUID(uuidString: value) else { throw StoreError.corrupt("backup identity") }
        return StableID(uuid)
    }
}

private extension NativeBackup {
    func validate() throws {
        guard format == "local.desknodes.native.backup", version == 1, (7...Schema.version).contains(schema) else { throw StoreError.invalid("不兼容的原生备份版本") }
        func require(_ condition: Bool, _ message: String) throws { if !condition { throw StoreError.invalid(message) } }
        func date(_ value: Date?) throws { if let value { try require(value.timeIntervalSince1970.isFinite, "timestamp") } }
        func placement(_ value: Placement) throws {
            if case let .free(_, x, y, w, h) = value { try require([x,y,w,h].allSatisfy(\.isFinite) && w > 0 && h > 0, "placement") }
        }
        try require((0...23).contains(settings.hour) && (0...59).contains(settings.minute), "rollover time")
        try preferences.validate()
        try require(Set(notes.map(\.id)).count == notes.count && Set(items.map(\.id)).count == items.count && Set(history.map(\.day)).count == history.count, "duplicate identity")
        let noteMap = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        let itemMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for note in notes {
            try require(note.order >= 0, "note order"); try placement(note.placement)
            if let restore = note.freeRestore { guard case .free = restore else { throw StoreError.invalid("free restore") }; try placement(restore) }
            try date(note.createdAt); try date(note.updatedAt); try date(note.deletedAt)
        }
        for item in items {
            try require(!(item.completed && item.struck), "completed and struck")
            try require(noteMap[item.noteID] != nil && item.order >= 0, "item parent/order")
            try require(noteMap[item.noteID]?.deletedAt == nil || item.deletedAt != nil || item.archivedDay != nil, "live child of deleted note")
            try date(item.createdAt); try date(item.updatedAt); try date(item.deletedAt)
        }
        for snapshot in history {
            try date(snapshot.capturedAt)
            try require(Set(snapshot.notes.map(\.id)).count == snapshot.notes.count, "duplicate snapshot note")
            var seen: Set<ItemID> = []
            for note in snapshot.notes {
                try require(noteMap[note.id] != nil && note.order >= 0, "snapshot note reference/order"); try date(note.deletedAt)
                for item in note.items {
                    try require(seen.insert(item.id).inserted && itemMap[item.id]?.noteID == note.id && item.order >= 0, "snapshot item reference/order")
                    try date(item.deletedAt)
                    if let carry = item.carriedTo { try require(carry > snapshot.day && !item.completed && !item.struck && item.deletedAt == nil && note.deletedAt == nil, "carry") }
                }
            }
        }
        for item in items {
            if let day = item.archivedDay {
                let archived = history.first { $0.day == day }?.notes.first { $0.id == item.noteID }?.items.first { $0.id == item.id }
                try require((item.completed || item.struck) && item.deletedAt == nil && archived?.completed == item.completed && archived?.struck == item.struck && archived?.deletedAt == nil && archived?.text == item.text && archived?.order == item.order, "archive reference/content")
            }
        }
        if let checkpoint {
            try date(checkpoint.highWater)
            try require(history.allSatisfy { $0.day < checkpoint.activeDay }, "checkpoint overlaps sealed history")
        }
        try require(Set(pendingNotes).count == pendingNotes.count && Set(pendingItems).count == pendingItems.count, "duplicate pending membership")
        for id in pendingNotes { try require(noteMap[id]?.deletedAt != nil, "pending note") }
        for id in pendingItems { try require(itemMap[id]?.deletedAt != nil && itemMap[id]?.archivedDay == nil, "pending item") }
    }
}
