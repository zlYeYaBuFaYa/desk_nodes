using DeskNodes.Core.Domain;
using Microsoft.Data.Sqlite;

namespace DeskNodes.Core.Storage;

/// <summary>All operations run synchronously in the database transaction scope. Times use UTC Unix milliseconds.</summary>
public sealed class NoteRepository(DeskNodesDatabase database)
{
    public IReadOnlyList<Note> GetNotes(bool includeDeleted = false) => database.Transaction(connection =>
    {
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT * FROM notes" + (includeDeleted ? "" : " WHERE deleted_at IS NULL") +
            " ORDER BY sort_order, id;";
        using var reader = command.ExecuteReader();
        var result = new List<Note>();
        while (reader.Read())
            result.Add(ReadNote(reader));
        return (IReadOnlyList<Note>)result;
    });

    public IReadOnlyList<NoteItem> GetItems(NoteId noteId, bool includeDeleted = false, bool includeArchived = false)
        => database.Transaction(connection =>
    {
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT i.* FROM items i JOIN notes n ON n.id = i.note_id WHERE i.note_id = $note_id" +
            (includeDeleted ? "" : " AND i.deleted_at IS NULL AND n.deleted_at IS NULL") +
            (includeArchived ? "" : " AND i.archived_day IS NULL") + " ORDER BY i.sort_order, i.id;";
        command.Parameters.AddWithValue("$note_id", noteId.ToString());
        using var reader = command.ExecuteReader();
        var result = new List<NoteItem>();
        while (reader.Read())
            result.Add(ReadItem(reader));
        return (IReadOnlyList<NoteItem>)result;
    });

    public void Insert(Note value)
    {
        ArgumentNullException.ThrowIfNull(value);
        database.Transaction(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText = """
                INSERT INTO notes (id, title, color, sort_order, x, y, width, height, display_device_hint, dock_edge,
                dock_order, saved_level, free_x, free_y, free_width, free_height, automatic_height, collapsed,
                created_at, updated_at, deleted_at)
                VALUES ($id, $title, $color, $sort_order, $x, $y, $width, $height, $display_device_hint, $dock_edge,
                $dock_order, $saved_level, $free_x, $free_y, $free_width, $free_height, $automatic_height, $collapsed,
                $created_at, $updated_at, $deleted_at);
                """;
            Bind(command, value);
            if (command.ExecuteNonQuery() != 1)
                throw new KeyNotFoundException("记录不存在。");
        });
    }

    public void Update(Note value)
    {
        ArgumentNullException.ThrowIfNull(value);
        database.Transaction(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText = """
                UPDATE notes
                SET title = $title, color = $color, sort_order = $sort_order, x = $x, y = $y, width = $width, height =
                $height, display_device_hint = $display_device_hint, dock_edge = $dock_edge, dock_order = $dock_order,
                saved_level = $saved_level, free_x = $free_x, free_y = $free_y, free_width = $free_width, free_height =
                $free_height, automatic_height = $automatic_height, collapsed = $collapsed, created_at = $created_at,
                updated_at = $updated_at, deleted_at = $deleted_at
                WHERE id = $id;
                """;
            Bind(command, value);
            if (command.ExecuteNonQuery() != 1)
                throw new KeyNotFoundException("记录不存在。");
        });
    }

    public void Insert(NoteItem value)
    {
        ArgumentNullException.ThrowIfNull(value);
        database.Transaction(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText = """
                INSERT INTO items (id, note_id, text, completed, struck, sort_order, archived_day, created_at,
                updated_at, deleted_at)
                VALUES ($id, $note_id, $text, $completed, $struck, $sort_order, $archived_day, $created_at, $updated_at,
                $deleted_at);
                """;
            Bind(command, value);
            if (command.ExecuteNonQuery() != 1)
                throw new KeyNotFoundException("记录不存在。");
        });
    }

    public void Update(NoteItem value)
    {
        ArgumentNullException.ThrowIfNull(value);
        database.Transaction(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText = """
                UPDATE items
                SET note_id = $note_id, text = $text, completed = $completed, struck = $struck, sort_order =
                $sort_order, archived_day = $archived_day, created_at = $created_at, updated_at = $updated_at,
                deleted_at = $deleted_at
                WHERE id = $id;
                """;
            Bind(command, value);
            if (command.ExecuteNonQuery() != 1)
                throw new KeyNotFoundException("记录不存在。");
        });
    }

    public bool SoftDelete(NoteId id, DateTimeOffset at) => database.Transaction(connection =>
    {
        long timestamp = at.ToUnixTimeMilliseconds();
        int changed = Execute(connection,
            "UPDATE notes SET deleted_at=$at, updated_at=$at WHERE id=$id AND deleted_at IS NULL;", id.ToString(), timestamp);
        if (changed == 0)
            return false;
        Execute(connection, "INSERT INTO pending_deleted_notes(note_id,deleted_at) VALUES($id,$at) " +
            "ON CONFLICT(note_id) DO UPDATE SET deleted_at=excluded.deleted_at;", id.ToString(), timestamp);
        Execute(connection, "INSERT INTO pending_deleted_items(item_id,deleted_at) " +
            "SELECT id,$at FROM items WHERE note_id=$id AND deleted_at IS NULL AND archived_day IS NULL " +
            "ON CONFLICT(item_id) DO UPDATE SET deleted_at=excluded.deleted_at;", id.ToString(), timestamp);
        Execute(connection, "UPDATE items SET deleted_at=$at, updated_at=$at " +
            "WHERE note_id=$id AND deleted_at IS NULL AND archived_day IS NULL;", id.ToString(), timestamp);
        return true;
    });

    public bool SoftDelete(ItemId id, DateTimeOffset at) => database.Transaction(connection =>
    {
        long timestamp = at.ToUnixTimeMilliseconds();
        int changed = Execute(connection,
            "UPDATE items SET deleted_at=$at, updated_at=$at WHERE id=$id AND deleted_at IS NULL;", id.ToString(), timestamp);
        if (changed == 0)
            return false;
        Execute(connection, "INSERT INTO pending_deleted_items(item_id,deleted_at) VALUES($id,$at) " +
            "ON CONFLICT(item_id) DO UPDATE SET deleted_at=excluded.deleted_at;", id.ToString(), timestamp);
        return true;
    });

    public bool Restore(NoteId id, DateTimeOffset at) => database.Transaction(connection =>
    {
        // Only children from this whole-note deletion return; earlier individual tombstones stay deleted.
        Execute(connection, "DELETE FROM pending_deleted_items WHERE item_id IN " +
            "(SELECT i.id FROM items i JOIN notes n ON n.id=i.note_id WHERE n.id=$id " +
            "AND n.deleted_at IS NOT NULL AND i.deleted_at=n.deleted_at AND i.archived_day IS NULL);", id.ToString(), at.ToUnixTimeMilliseconds());
        Execute(connection, "UPDATE items SET deleted_at=NULL, updated_at=$at WHERE note_id=$id " +
            "AND archived_day IS NULL AND deleted_at=(SELECT deleted_at FROM notes WHERE id=$id);", id.ToString(), at.ToUnixTimeMilliseconds());
        int changed = Execute(connection, "UPDATE notes SET deleted_at=NULL, updated_at=$at " +
            "WHERE id=$id AND deleted_at IS NOT NULL;", id.ToString(), at.ToUnixTimeMilliseconds());
        if (changed != 0)
            Execute(connection, "DELETE FROM pending_deleted_notes WHERE note_id=$id;", id.ToString(), at.ToUnixTimeMilliseconds());
        return changed != 0;
    });

    public bool Restore(ItemId id, DateTimeOffset at) => database.Transaction(connection =>
    {
        int changed = Execute(connection, "UPDATE items SET deleted_at=NULL, updated_at=$at, " +
            "sort_order=(SELECT COALESCE(MAX(sibling.sort_order),-1)+1 FROM items sibling " +
            "WHERE sibling.note_id=items.note_id AND sibling.deleted_at IS NULL AND sibling.archived_day IS NULL) " +
            "WHERE id=$id AND deleted_at IS NOT NULL AND archived_day IS NULL " +
            "AND EXISTS(SELECT 1 FROM notes WHERE notes.id=items.note_id AND notes.deleted_at IS NULL);",
            id.ToString(), at.ToUnixTimeMilliseconds());
        if (changed != 0)
            Execute(connection, "DELETE FROM pending_deleted_items WHERE item_id=$id;", id.ToString(), at.ToUnixTimeMilliseconds());
        return changed != 0;
    });

    private static int Execute(SqliteConnection connection, string sql, string id, long timestamp)
    {
        using var command = connection.CreateCommand();
        command.CommandText = sql;
        command.Parameters.AddWithValue("$id", id);
        command.Parameters.AddWithValue("$at", timestamp);
        return command.ExecuteNonQuery();
    }

    private static void Bind(SqliteCommand command, Note note)
    {
        Add(command, "$id", note.Id.ToString());
        Add(command, "$title", note.Title);
        Add(command, "$color", note.Color.ToStorageId());
        Add(command, "$sort_order", note.SortOrder);
        Add(command, "$x", note.Placement.Bounds.X);
        Add(command, "$y", note.Placement.Bounds.Y);
        Add(command, "$width", note.Placement.Bounds.Width);
        Add(command, "$height", note.Placement.Bounds.Height);
        Add(command, "$display_device_hint", note.Placement.DisplayDeviceHint);
        Add(command, "$dock_edge", note.Placement.DockEdge switch
        {
            DockEdge.Top => "top", DockEdge.Left => "left", DockEdge.Right => "right",
            null => null, _ => throw new InvalidOperationException("未知停靠边。")
        });
        Add(command, "$dock_order", note.Placement.DockOrder);
        Add(command, "$saved_level", note.SavedLevel switch
        {
            NoteLevel.Back => "back", NoteLevel.Normal => "normal", NoteLevel.Topmost => "topmost",
            _ => throw new InvalidOperationException("未知便签层级。")
        });
        Add(command, "$free_x", note.FreeRestore?.X);
        Add(command, "$free_y", note.FreeRestore?.Y);
        Add(command, "$free_width", note.FreeRestore?.Width);
        Add(command, "$free_height", note.FreeRestore?.Height);
        Add(command, "$automatic_height", note.AutomaticHeight);
        Add(command, "$collapsed", note.Collapsed);
        Add(command, "$created_at", note.CreatedAt.ToUnixTimeMilliseconds());
        Add(command, "$updated_at", note.UpdatedAt.ToUnixTimeMilliseconds());
        Add(command, "$deleted_at", note.DeletedAt?.ToUnixTimeMilliseconds());
    }

    private static void Bind(SqliteCommand command, NoteItem item)
    {
        Add(command, "$id", item.Id.ToString());
        Add(command, "$note_id", item.NoteId.ToString());
        Add(command, "$text", item.Text);
        Add(command, "$completed", item.Completed);
        Add(command, "$struck", item.Struck);
        Add(command, "$sort_order", item.SortOrder);
        Add(command, "$archived_day", item.ArchivedDay?.ToString());
        Add(command, "$created_at", item.CreatedAt.ToUnixTimeMilliseconds());
        Add(command, "$updated_at", item.UpdatedAt.ToUnixTimeMilliseconds());
        Add(command, "$deleted_at", item.DeletedAt?.ToUnixTimeMilliseconds());
    }

    private static void Add(SqliteCommand command, string name, object? value)
        => command.Parameters.AddWithValue(name, value ?? DBNull.Value);

    private static Note ReadNote(SqliteDataReader reader) => new(
        NoteId.Parse(reader.GetString(reader.GetOrdinal("id"))),
        reader.GetString(reader.GetOrdinal("title")),
        NoteColors.ParseStorageId(reader.GetString(reader.GetOrdinal("color"))),
        reader.GetInt64(reader.GetOrdinal("sort_order")),
        new Placement(ReadRect(reader, ""), reader.GetString(reader.GetOrdinal("display_device_hint")),
            OptionalString(reader, "dock_edge") switch
            {
                "top" => DockEdge.Top, "left" => DockEdge.Left, "right" => DockEdge.Right,
                null => null, _ => throw new FormatException("未知停靠边。")
            }, reader.IsDBNull(reader.GetOrdinal("dock_order")) ? null : reader.GetInt32(reader.GetOrdinal("dock_order"))),
        reader.GetString(reader.GetOrdinal("saved_level")) switch
        {
            "back" => NoteLevel.Back, "normal" => NoteLevel.Normal, "topmost" => NoteLevel.Topmost,
            _ => throw new FormatException("未知便签层级。")
        },
        reader.IsDBNull(reader.GetOrdinal("free_x")) ? null : ReadRect(reader, "free_"),
        reader.GetBoolean(reader.GetOrdinal("automatic_height")),
        reader.GetBoolean(reader.GetOrdinal("collapsed")),
        ReadTime(reader, "created_at"), ReadTime(reader, "updated_at"), OptionalTime(reader, "deleted_at"));

    private static NoteItem ReadItem(SqliteDataReader reader) => new(
        ItemId.Parse(reader.GetString(reader.GetOrdinal("id"))),
        NoteId.Parse(reader.GetString(reader.GetOrdinal("note_id"))),
        reader.GetString(reader.GetOrdinal("text")),
        reader.GetBoolean(reader.GetOrdinal("completed")), reader.GetBoolean(reader.GetOrdinal("struck")),
        reader.GetInt64(reader.GetOrdinal("sort_order")),
        OptionalString(reader, "archived_day") is { } day ? HistoryDay.Parse(day) : null,
        ReadTime(reader, "created_at"), ReadTime(reader, "updated_at"), OptionalTime(reader, "deleted_at"));

    private static RectD ReadRect(SqliteDataReader reader, string prefix) => new(
        reader.GetDouble(reader.GetOrdinal(prefix + "x")), reader.GetDouble(reader.GetOrdinal(prefix + "y")),
        reader.GetDouble(reader.GetOrdinal(prefix + "width")), reader.GetDouble(reader.GetOrdinal(prefix + "height")));

    private static DateTimeOffset ReadTime(SqliteDataReader reader, string column)
        => DateTimeOffset.FromUnixTimeMilliseconds(reader.GetInt64(reader.GetOrdinal(column)));

    private static DateTimeOffset? OptionalTime(SqliteDataReader reader, string column)
        => reader.IsDBNull(reader.GetOrdinal(column)) ? null : ReadTime(reader, column);

    private static string? OptionalString(SqliteDataReader reader, string column)
        => reader.IsDBNull(reader.GetOrdinal(column)) ? null : reader.GetString(reader.GetOrdinal(column));
}
