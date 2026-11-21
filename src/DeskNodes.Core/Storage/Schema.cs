namespace DeskNodes.Core.Storage;

internal static class Schema
{
    // Timestamps are Unix milliseconds; checkpoint high_water is the greatest observed business day.
    // Deferred foreign keys allow members before the header, but require the complete snapshot at commit.
    // Triggers protect headers and members, including INSERT OR REPLACE with recursive_triggers disabled.
    public const string Version1 = """
        CREATE TABLE notes (
            id TEXT NOT NULL PRIMARY KEY,
            title TEXT NOT NULL,
            color TEXT NOT NULL CHECK (color IN ('paper','lemon','apricot','cherry','lavender','mist','mint')),
            sort_order INTEGER NOT NULL,
            x REAL NOT NULL, y REAL NOT NULL,
            width REAL NOT NULL CHECK (width >= 0), height REAL NOT NULL CHECK (height >= 0),
            display_device_hint TEXT NOT NULL,
            dock_edge TEXT CHECK (dock_edge IN ('top','left','right')),
            dock_order INTEGER CHECK (dock_order BETWEEN 0 AND 2147483647),
            saved_level TEXT NOT NULL CHECK (saved_level IN ('back','normal','topmost')),
            free_x REAL, free_y REAL, free_width REAL CHECK (free_width >= 0), free_height REAL CHECK (free_height >= 0),
            automatic_height INTEGER NOT NULL CHECK (automatic_height IN (0,1)),
            collapsed INTEGER NOT NULL CHECK (collapsed IN (0,1)),
            created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER,
            CHECK ((dock_edge IS NULL AND dock_order IS NULL) OR (dock_edge IS NOT NULL AND dock_order IS NOT NULL)),
            CHECK ((free_x IS NULL AND free_y IS NULL AND free_width IS NULL AND free_height IS NULL) OR
                   (free_x IS NOT NULL AND free_y IS NOT NULL AND free_width IS NOT NULL AND free_height IS NOT NULL))
        );
        CREATE TABLE items (
            id TEXT NOT NULL PRIMARY KEY,
            note_id TEXT NOT NULL REFERENCES notes(id),
            text TEXT NOT NULL,
            completed INTEGER NOT NULL CHECK (completed IN (0,1)),
            struck INTEGER NOT NULL CHECK (struck IN (0,1)),
            sort_order INTEGER NOT NULL,
            archived_day TEXT CHECK (archived_day IS NULL OR (length(archived_day) = 10
                AND archived_day GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
                AND substr(archived_day,1,4) BETWEEN '0001' AND '9999'
                AND date(archived_day, '+0 days') IS NOT NULL AND date(archived_day, '+0 days') = archived_day)),
            created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER,
            CHECK (NOT (completed AND struck))
        );
        CREATE INDEX notes_active_order ON notes(sort_order, id) WHERE deleted_at IS NULL;
        CREATE INDEX items_note_order ON items(note_id, sort_order, id) WHERE deleted_at IS NULL;
        CREATE TABLE checkpoint (
            singleton INTEGER NOT NULL PRIMARY KEY CHECK (singleton = 1),
            active_day TEXT NOT NULL CHECK (length(active_day) = 10
                AND active_day GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
                AND substr(active_day,1,4) BETWEEN '0001' AND '9999'
                AND date(active_day, '+0 days') IS NOT NULL AND date(active_day, '+0 days') = active_day),
            high_water TEXT NOT NULL CHECK (length(high_water) = 10
                AND high_water GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
                AND substr(high_water,1,4) BETWEEN '0001' AND '9999'
                AND date(high_water, '+0 days') IS NOT NULL AND date(high_water, '+0 days') = high_water),
            CHECK (high_water >= active_day)
        );
        CREATE TABLE business_settings (
            singleton INTEGER NOT NULL PRIMARY KEY CHECK (singleton = 1),
            rollover_minutes INTEGER NOT NULL CHECK (rollover_minutes BETWEEN 0 AND 1439)
        );
        INSERT INTO business_settings VALUES (1, 240);
        CREATE TABLE business_preferences (
            singleton INTEGER NOT NULL PRIMARY KEY CHECK (singleton = 1),
            hotkey_new TEXT NOT NULL,
            hotkey_float TEXT,
            login_prompt_answered INTEGER NOT NULL CHECK (login_prompt_answered IN (0,1)),
            login_intent INTEGER NOT NULL CHECK (login_intent IN (0,1))
        );
        INSERT INTO business_preferences VALUES (1, 'Ctrl+Alt+N', 'Ctrl+Alt+F', 0, 0);
        CREATE TABLE snapshots (
            day TEXT NOT NULL PRIMARY KEY CHECK (length(day) = 10
                AND day GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
                AND substr(day,1,4) BETWEEN '0001' AND '9999'
                AND date(day, '+0 days') IS NOT NULL AND date(day, '+0 days') = day),
            sealed_at INTEGER NOT NULL
        );
        CREATE TABLE snapshot_notes (
            day TEXT NOT NULL REFERENCES snapshots(day) DEFERRABLE INITIALLY DEFERRED,
            note_id TEXT NOT NULL,
            title TEXT NOT NULL,
            color TEXT NOT NULL CHECK (color IN ('paper','lemon','apricot','cherry','lavender','mist','mint')),
            sort_order INTEGER NOT NULL,
            x REAL NOT NULL, y REAL NOT NULL,
            width REAL NOT NULL CHECK (width >= 0), height REAL NOT NULL CHECK (height >= 0),
            display_device_hint TEXT NOT NULL,
            dock_edge TEXT CHECK (dock_edge IN ('top','left','right')),
            dock_order INTEGER CHECK (dock_order BETWEEN 0 AND 2147483647),
            saved_level TEXT NOT NULL CHECK (saved_level IN ('back','normal','topmost')),
            free_x REAL, free_y REAL, free_width REAL CHECK (free_width >= 0), free_height REAL CHECK (free_height >= 0),
            automatic_height INTEGER NOT NULL CHECK (automatic_height IN (0,1)),
            collapsed INTEGER NOT NULL CHECK (collapsed IN (0,1)),
            created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER,
            deleted INTEGER NOT NULL CHECK (deleted IN (0,1)),
            CHECK ((dock_edge IS NULL AND dock_order IS NULL) OR (dock_edge IS NOT NULL AND dock_order IS NOT NULL)),
            CHECK ((free_x IS NULL AND free_y IS NULL AND free_width IS NULL AND free_height IS NULL) OR
                   (free_x IS NOT NULL AND free_y IS NOT NULL AND free_width IS NOT NULL AND free_height IS NOT NULL)),
            PRIMARY KEY (day, note_id)
        );
        CREATE TABLE snapshot_items (
            day TEXT NOT NULL REFERENCES snapshots(day) DEFERRABLE INITIALLY DEFERRED,
            item_id TEXT NOT NULL,
            note_id TEXT NOT NULL,
            text TEXT NOT NULL,
            completed INTEGER NOT NULL CHECK (completed IN (0,1)),
            struck INTEGER NOT NULL CHECK (struck IN (0,1)),
            sort_order INTEGER NOT NULL,
            archived_day TEXT CHECK (archived_day IS NULL OR (length(archived_day) = 10
                AND archived_day GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
                AND substr(archived_day,1,4) BETWEEN '0001' AND '9999'
                AND date(archived_day, '+0 days') IS NOT NULL AND date(archived_day, '+0 days') = archived_day)),
            created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER,
            deleted INTEGER NOT NULL CHECK (deleted IN (0,1)),
            carried_to TEXT CHECK (carried_to IS NULL OR (length(carried_to) = 10
                AND carried_to GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
                AND substr(carried_to,1,4) BETWEEN '0001' AND '9999'
                AND date(carried_to, '+0 days') IS NOT NULL AND date(carried_to, '+0 days') = carried_to)),
            CHECK (NOT (completed AND struck)),
            PRIMARY KEY (day, item_id),
            FOREIGN KEY (day, note_id) REFERENCES snapshot_notes(day, note_id) DEFERRABLE INITIALLY DEFERRED
        );
        CREATE TABLE note_deletion_items (
            note_id TEXT NOT NULL REFERENCES notes(id),
            item_id TEXT NOT NULL PRIMARY KEY REFERENCES items(id)
        );
        CREATE TABLE pending_deleted_notes (
            note_id TEXT NOT NULL PRIMARY KEY REFERENCES notes(id),
            deleted_at INTEGER NOT NULL,
            day TEXT NOT NULL CHECK (length(day) = 10
                AND day GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
                AND substr(day,1,4) BETWEEN '0001' AND '9999'
                AND date(day, '+0 days') IS NOT NULL AND date(day, '+0 days') = day)
        );
        CREATE TABLE pending_deleted_items (
            item_id TEXT NOT NULL PRIMARY KEY REFERENCES items(id),
            deleted_at INTEGER NOT NULL,
            day TEXT NOT NULL CHECK (length(day) = 10
                AND day GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
                AND substr(day,1,4) BETWEEN '0001' AND '9999'
                AND date(day, '+0 days') IS NOT NULL AND date(day, '+0 days') = day)
        );
        CREATE TRIGGER snapshots_no_update BEFORE UPDATE ON snapshots
        BEGIN SELECT RAISE(ABORT, 'Snapshots are immutable'); END;
        CREATE TRIGGER snapshots_no_delete BEFORE DELETE ON snapshots
        BEGIN SELECT RAISE(ABORT, 'Snapshots are immutable'); END;
        CREATE TRIGGER snapshots_no_replace BEFORE INSERT ON snapshots
        WHEN EXISTS (SELECT 1 FROM snapshots WHERE day = NEW.day)
        BEGIN SELECT RAISE(ABORT, 'Snapshots are immutable'); END;
        CREATE TRIGGER snapshot_notes_no_update BEFORE UPDATE ON snapshot_notes
        BEGIN SELECT RAISE(ABORT, 'Snapshots are immutable'); END;
        CREATE TRIGGER snapshot_notes_no_delete BEFORE DELETE ON snapshot_notes
        BEGIN SELECT RAISE(ABORT, 'Snapshots are immutable'); END;
        CREATE TRIGGER snapshot_notes_no_replace BEFORE INSERT ON snapshot_notes
        WHEN EXISTS (SELECT 1 FROM snapshot_notes WHERE day = NEW.day AND note_id = NEW.note_id)
        BEGIN SELECT RAISE(ABORT, 'Snapshots are immutable'); END;
        CREATE TRIGGER snapshot_notes_no_late_insert BEFORE INSERT ON snapshot_notes
        WHEN EXISTS (SELECT 1 FROM snapshots WHERE day = NEW.day)
        BEGIN SELECT RAISE(ABORT, 'Snapshot is already sealed'); END;
        CREATE TRIGGER snapshot_items_no_update BEFORE UPDATE ON snapshot_items
        BEGIN SELECT RAISE(ABORT, 'Snapshots are immutable'); END;
        CREATE TRIGGER snapshot_items_no_delete BEFORE DELETE ON snapshot_items
        BEGIN SELECT RAISE(ABORT, 'Snapshots are immutable'); END;
        CREATE TRIGGER snapshot_items_no_replace BEFORE INSERT ON snapshot_items
        WHEN EXISTS (SELECT 1 FROM snapshot_items WHERE day = NEW.day AND item_id = NEW.item_id)
        BEGIN SELECT RAISE(ABORT, 'Snapshots are immutable'); END;
        CREATE TRIGGER snapshot_items_no_late_insert BEFORE INSERT ON snapshot_items
        WHEN EXISTS (SELECT 1 FROM snapshots WHERE day = NEW.day)
        BEGIN SELECT RAISE(ABORT, 'Snapshot is already sealed'); END;
        """;
}
