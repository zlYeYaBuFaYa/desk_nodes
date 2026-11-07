import Foundation

internal enum Schema {
    static let version = 7
    // Application ID 'DSKN': reject unrelated databases, even if user_version coincides.
    static let applicationID = 0x44534B4E
    static func migrate(_ db: SQLite) throws {
        try db.run("PRAGMA foreign_keys = ON")
        try db.run("BEGIN EXCLUSIVE")
        do {
            let version = Int(try db.query("PRAGMA user_version")[0][0]!)!
            let identity = Int(try db.query("PRAGMA application_id")[0][0]!)!
            guard version <= Self.version else { throw StoreError.unsupportedSchema(version) }
            let tables = try db.query("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
            guard (version == 0 && identity == 0 && tables.isEmpty) || identity == applicationID else {
                throw StoreError.invalid("not a native DeskNodes database")
            }
            if version == 0 {
                for sql in initial { try db.run(sql) }
                try db.run("PRAGMA application_id = \(applicationID)")
                try db.run("PRAGMA user_version = 1")
            }
            if version < 2 {
                // v1 is the native live-row foundation, never a Tauri migration.
                for sql in history { try db.run(sql) }
                try db.run("PRAGMA user_version = 2")
            }
            if version < 3 {
                try db.run("ALTER TABLE notes ADD COLUMN automatic_height INTEGER NOT NULL DEFAULT 1 CHECK(automatic_height IN (0,1))")
                try db.run("PRAGMA user_version = 3")
            }
            if version < 4 {
                try db.run("ALTER TABLE notes ADD COLUMN free_restore TEXT")
                try db.run("PRAGMA user_version = 4")
            }
            if version < 5 {
                for sql in rollover { try db.run(sql) }
                try db.run("PRAGMA user_version = 5")
            }
            if version < 6 {
                try db.run("ALTER TABLE settings ADD COLUMN edge_preference TEXT NOT NULL DEFAULT 'automatic' CHECK(edge_preference IN ('automatic','left','right'))")
                try db.run("PRAGMA user_version = 6")
            }
            if version < 7 {
                try db.run("CREATE TABLE native_preferences (id INTEGER PRIMARY KEY CHECK(id=1), payload TEXT NOT NULL)")
                let defaults = String(decoding: try JSONEncoder().encode(NativePreferences()), as: UTF8.self)
                try db.run("INSERT INTO native_preferences VALUES (1,?)", [.text(defaults)])
                try db.run("PRAGMA user_version = 7")
            }
            guard try db.query("PRAGMA foreign_key_check").isEmpty else {
                throw StoreError.corrupt("foreign keys")
            }
            try db.run("COMMIT")
        } catch {
            try? db.run("ROLLBACK")
            throw error
        }
    }
    static let rollover = [
        "CREATE TABLE rollover_state (id INTEGER PRIMARY KEY CHECK(id=1), active_day TEXT NOT NULL, high_water REAL NOT NULL)",
        "CREATE TABLE item_archives (item_id TEXT PRIMARY KEY REFERENCES items(id), day TEXT NOT NULL REFERENCES days(day), FOREIGN KEY(day,item_id) REFERENCES snapshot_items(day,item_id))",
        "CREATE TABLE pending_deleted_notes (note_id TEXT PRIMARY KEY REFERENCES notes(id))",
        "CREATE TABLE pending_deleted_items (item_id TEXT PRIMARY KEY REFERENCES items(id))",
        // Existing tombstones enter daily membership only if no prior snapshot recorded deletion.
        "INSERT INTO pending_deleted_notes SELECT id FROM notes WHERE deleted IS NOT NULL AND NOT EXISTS (SELECT 1 FROM snapshot_notes WHERE note_id=notes.id AND deleted IS NOT NULL)",
        "INSERT INTO pending_deleted_items SELECT id FROM items WHERE deleted IS NOT NULL AND NOT EXISTS (SELECT 1 FROM snapshot_items WHERE item_id=items.id AND deleted IS NOT NULL)",
        "CREATE TRIGGER immutable_archive_update BEFORE UPDATE ON item_archives BEGIN SELECT RAISE(ABORT, 'immutable archive'); END",
        "CREATE TRIGGER immutable_archive_delete BEFORE DELETE ON item_archives BEGIN SELECT RAISE(ABORT, 'immutable archive'); END"
    ]
    static let initial = [
        """
        CREATE TABLE notes (
          id TEXT PRIMARY KEY NOT NULL, title TEXT,
          color TEXT NOT NULL CHECK(color IN ('paper','lemon','apricot','cherry','lavender','mist','mint','graphite')),
          placement TEXT NOT NULL,
          level TEXT NOT NULL CHECK(level IN ('desktop','ordinary','topmost')),
          position INTEGER NOT NULL CHECK(position >= 0), collapsed INTEGER NOT NULL CHECK(collapsed IN (0,1)),
          created REAL NOT NULL, updated REAL NOT NULL, deleted REAL)
        """,
        """
        CREATE TABLE items (
          id TEXT PRIMARY KEY NOT NULL, note_id TEXT NOT NULL REFERENCES notes(id), text TEXT NOT NULL,
          completed INTEGER NOT NULL CHECK(completed IN (0,1)), position INTEGER NOT NULL CHECK(position >= 0),
          created REAL NOT NULL, updated REAL NOT NULL, deleted REAL)
        """,
        "CREATE INDEX items_note_order ON items(note_id, position, id)",
        """
        CREATE TABLE settings (
          id TEXT PRIMARY KEY CHECK(id = 'native-settings'), hour INTEGER NOT NULL CHECK(hour BETWEEN 0 AND 23),
          minute INTEGER NOT NULL CHECK(minute BETWEEN 0 AND 59),
          dock_edge TEXT NOT NULL CHECK(dock_edge IN ('top','left','right')), display_id TEXT)
        """,
        "INSERT INTO settings VALUES ('native-settings',4,0,'top',NULL)"
    ]
    static let history = [
        "CREATE TABLE days (day TEXT PRIMARY KEY NOT NULL, captured REAL NOT NULL)",
        """
        CREATE TABLE snapshot_notes (
          day TEXT NOT NULL REFERENCES days(day), note_id TEXT NOT NULL REFERENCES notes(id),
          title TEXT, color TEXT NOT NULL, position INTEGER NOT NULL, deleted REAL,
          PRIMARY KEY(day,note_id))
        """,
        """
        CREATE TABLE snapshot_items (
          day TEXT NOT NULL, note_id TEXT NOT NULL, item_id TEXT NOT NULL REFERENCES items(id),
          text TEXT NOT NULL, completed INTEGER NOT NULL CHECK(completed IN (0,1)), position INTEGER NOT NULL,
          deleted REAL, carried_to TEXT,
          PRIMARY KEY(day,item_id), FOREIGN KEY(day,note_id) REFERENCES snapshot_notes(day,note_id),
          CHECK(carried_to IS NULL OR (completed = 0 AND deleted IS NULL AND carried_to > day)))
        """
    ] + ["days", "snapshot_notes", "snapshot_items"].flatMap { table in
        ["UPDATE", "DELETE"].map { operation in
            "CREATE TRIGGER immutable_\(table)_\(operation.lowercased()) BEFORE \(operation) ON \(table) BEGIN SELECT RAISE(ABORT, 'immutable history'); END"
        }
    } + [
        // Once a day header commits, new child rows cannot be appended. During capture,
        // children precede the deferred header; foreign key checking occurs at COMMIT.
        "CREATE TRIGGER sealed_notes BEFORE INSERT ON snapshot_notes WHEN EXISTS(SELECT 1 FROM days WHERE day=NEW.day) BEGIN SELECT RAISE(ABORT, 'sealed history'); END",
        "CREATE TRIGGER sealed_items BEFORE INSERT ON snapshot_items WHEN EXISTS(SELECT 1 FROM days WHERE day=NEW.day) BEGIN SELECT RAISE(ABORT, 'sealed history'); END"
    ]
}
