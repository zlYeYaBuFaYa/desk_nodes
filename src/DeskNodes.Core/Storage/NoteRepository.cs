using DeskNodes.Core.Domain;
using Microsoft.Data.Sqlite;

namespace DeskNodes.Core.Storage;

/// <summary>Queries use serialized reads; writes use transactions. Times use UTC Unix milliseconds.</summary>
public sealed class NoteRepository(DeskNodesDatabase database)
{
    public Note? GetNote(NoteId id, bool includeDeleted = false) => database.Read(connection =>
    {
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT * FROM notes WHERE id = $id" +
            (includeDeleted ? "" : " AND deleted_at IS NULL") + ";";
        command.Parameters.AddWithValue("$id", id.ToString());
        using var reader = command.ExecuteReader();
        return reader.Read() ? ReadNote(reader) : null;
    });

    /// <summary>Deletion filtering includes the parent note, as with GetItems.</summary>
    public NoteItem? GetItem(ItemId id, bool includeDeleted = false, bool includeArchived = false)
        => database.Read(connection =>
    {
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT i.* FROM items i JOIN notes n ON n.id = i.note_id WHERE i.id = $id" +
            (includeDeleted ? "" : " AND i.deleted_at IS NULL AND n.deleted_at IS NULL") +
            (includeArchived ? "" : " AND i.archived_day IS NULL") + ";";
        command.Parameters.AddWithValue("$id", id.ToString());
        using var reader = command.ExecuteReader();
        return reader.Read() ? ReadItem(reader) : null;
    });

    public IReadOnlyList<Note> GetNotes(bool includeDeleted = false) => database.Read(connection =>
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
        => database.Read(connection =>
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
                updated_at = $updated_at
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

    /// <summary>Records the deletion day at write time so later time-zone/settings changes cannot reassign it.</summary>
    public bool SoftDelete(NoteId id, DateTimeOffset at, HistoryDay day) => database.Transaction(connection =>
    {
        long timestamp = at.ToUnixTimeMilliseconds();
        HistoryDay deletionDay = day;
        int changed = Execute(connection,
            "UPDATE notes SET deleted_at=$at, updated_at=$at WHERE id=$id AND deleted_at IS NULL;", id.ToString(), timestamp, deletionDay);
        if (changed == 0)
            return false;
        Execute(connection, "INSERT INTO pending_deleted_notes(note_id,deleted_at,day) VALUES($id,$at,$day) " +
            "ON CONFLICT(note_id) DO UPDATE SET deleted_at=excluded.deleted_at,day=excluded.day;", id.ToString(), timestamp, deletionDay);
        // Explicit membership disambiguates an earlier single deletion in the same millisecond.
        Execute(connection, "INSERT INTO note_deletion_items(note_id,item_id) SELECT note_id,id FROM items " +
            "WHERE note_id=$id AND deleted_at IS NULL AND archived_day IS NULL;", id.ToString(), timestamp, deletionDay);
        Execute(connection, "INSERT INTO pending_deleted_items(item_id,deleted_at,day) " +
            "SELECT id,$at,$day FROM items WHERE note_id=$id AND deleted_at IS NULL AND archived_day IS NULL " +
            "ON CONFLICT(item_id) DO UPDATE SET deleted_at=excluded.deleted_at,day=excluded.day;", id.ToString(), timestamp, deletionDay);
        Execute(connection, "UPDATE items SET deleted_at=$at, updated_at=$at " +
            "WHERE note_id=$id AND deleted_at IS NULL AND archived_day IS NULL;", id.ToString(), timestamp, deletionDay);
        return true;
    });

    public bool SoftDelete(ItemId id, DateTimeOffset at, HistoryDay day) => database.Transaction(connection =>
    {
        long timestamp = at.ToUnixTimeMilliseconds();
        HistoryDay deletionDay = day;
        int changed = Execute(connection,
            "UPDATE items SET deleted_at=$at, updated_at=$at WHERE id=$id AND deleted_at IS NULL;", id.ToString(), timestamp, deletionDay);
        if (changed == 0)
            return false;
        Execute(connection, "INSERT INTO pending_deleted_items(item_id,deleted_at,day) VALUES($id,$at,$day) " +
            "ON CONFLICT(item_id) DO UPDATE SET deleted_at=excluded.deleted_at,day=excluded.day;", id.ToString(), timestamp, deletionDay);
        return true;
    });

    public bool Restore(NoteId id, DateTimeOffset at) => database.Transaction(connection =>
    {
        using (var check = connection.CreateCommand())
        {
            check.CommandText = "SELECT deleted_at FROM notes WHERE id=$id;";
            check.Parameters.AddWithValue("$id", id.ToString());
            if (check.ExecuteScalar() is null or DBNull)
                return false;
        }
        // Only children from this whole-note deletion return; earlier individual tombstones stay deleted.
        Execute(connection, "DELETE FROM pending_deleted_items WHERE item_id IN " +
            "(SELECT i.id FROM items i JOIN notes n ON n.id=i.note_id WHERE n.id=$id " +
            "AND n.deleted_at IS NOT NULL AND i.id IN (SELECT item_id FROM note_deletion_items WHERE note_id=$id) AND i.archived_day IS NULL);", id.ToString(), at.ToUnixTimeMilliseconds());
        Execute(connection, "UPDATE items SET deleted_at=NULL, updated_at=$at WHERE note_id=$id " +
            "AND archived_day IS NULL AND id IN (SELECT item_id FROM note_deletion_items WHERE note_id=$id);", id.ToString(), at.ToUnixTimeMilliseconds());
        int changed = Execute(connection, "UPDATE notes SET deleted_at=NULL, updated_at=$at " +
            "WHERE id=$id AND deleted_at IS NOT NULL;", id.ToString(), at.ToUnixTimeMilliseconds());
        if (changed != 0)
            Execute(connection, "DELETE FROM note_deletion_items WHERE note_id=$id; DELETE FROM pending_deleted_notes WHERE note_id=$id;", id.ToString(), at.ToUnixTimeMilliseconds());
        return changed != 0;
    });

    public bool Restore(ItemId id, DateTimeOffset at) => database.Transaction(connection =>
    {
        var item = GetItem(id, includeDeleted: true, includeArchived: true);
        if (item is null || item.DeletedAt is null || item.ArchivedDay is not null || GetNote(item.NoteId) is null)
            return false;
        long order = NextOrder(connection, "items", "note_id=$parent AND deleted_at IS NULL AND archived_day IS NULL", item.NoteId.ToString());
        using var command = connection.CreateCommand();
        command.CommandText = "UPDATE items SET deleted_at=NULL, updated_at=$at, sort_order=$order WHERE id=$id;";
        command.Parameters.AddWithValue("$at", at.ToUnixTimeMilliseconds());
        command.Parameters.AddWithValue("$order", order);
        command.Parameters.AddWithValue("$id", id.ToString());
        int changed = command.ExecuteNonQuery();
        if (changed != 0)
            Execute(connection, "DELETE FROM pending_deleted_items WHERE item_id=$id;", id.ToString(), at.ToUnixTimeMilliseconds());
        return changed != 0;
    });

    // Called inside the same outer transaction as the append. Include note tombstones in its ordering.
    internal long NextNoteOrder() => database.Transaction(connection => NextOrder(connection, "notes", "1=1"));

    private static long NextOrder(SqliteConnection connection, string table, string filter, string? parent = null)
    {
        using var command = connection.CreateCommand();
        command.CommandText = $"SELECT COALESCE(MAX(sort_order),-1) FROM {table} WHERE {filter};";
        command.Parameters.AddWithValue("$parent", parent ?? (object)DBNull.Value);
        long maximum = Convert.ToInt64(command.ExecuteScalar(), System.Globalization.CultureInfo.InvariantCulture);
        if (maximum != long.MaxValue)
            return checked(maximum + 1);
        command.CommandText = $"SELECT id FROM {table} WHERE {filter} ORDER BY sort_order,id;";
        var rows = new List<string>();
        using (var reader = command.ExecuteReader())
            while (reader.Read())
                rows.Add(reader.GetString(0));
        for (int index = 0; index < rows.Count; index++)
        {
            using var update = connection.CreateCommand();
            update.CommandText = $"UPDATE {table} SET sort_order=$order WHERE id=$id;";
            update.Parameters.AddWithValue("$order", index);
            update.Parameters.AddWithValue("$id", rows[index]);
            update.ExecuteNonQuery();
        }
        return rows.Count;
    }

    private static int Execute(SqliteConnection connection, string sql, string id, long timestamp, HistoryDay? day = null)
    {
        using var command = connection.CreateCommand();
        command.CommandText = sql;
        command.Parameters.AddWithValue("$id", id);
        command.Parameters.AddWithValue("$at", timestamp);
        command.Parameters.AddWithValue("$day", day?.ToString() ?? (object)DBNull.Value);
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

    internal static Note ReadNote(SqliteDataReader reader) => new(
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

    internal static NoteItem ReadItem(SqliteDataReader reader) => new(
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
