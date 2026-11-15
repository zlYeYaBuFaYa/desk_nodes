using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using DeskNodes.Core.Domain;
using DeskNodes.Core.Storage;
using Microsoft.Data.Sqlite;

namespace DeskNodes.Core.Backup;

public static class WindowsBackupCodec
{
    public static JsonSerializerOptions JsonOptions { get; } = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        WriteIndented = true,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow
    };
    static WindowsBackupCodec() => JsonOptions.MakeReadOnly(populateMissingResolver: true);
    private sealed record Table(string Name, string[] Columns, bool Singleton = false);
    private static readonly Table[] Tables =
    [
        new("notes", ["id", "title", "color", "sort_order", "x", "y", "width", "height", "display_device_hint", "dock_edge", "dock_order", "saved_level", "free_x", "free_y", "free_width", "free_height", "automatic_height", "collapsed", "created_at", "updated_at", "deleted_at"]),
        new("items", ["id", "note_id", "text", "completed", "struck", "sort_order", "archived_day", "created_at", "updated_at", "deleted_at"]),
        new("snapshot_notes", ["day", "note_id", "title", "color", "sort_order", "x", "y", "width", "height", "display_device_hint", "dock_edge", "dock_order", "saved_level", "free_x", "free_y", "free_width", "free_height", "automatic_height", "collapsed", "created_at", "updated_at", "deleted_at", "deleted"]),
        new("snapshot_items", ["day", "item_id", "note_id", "text", "completed", "struck", "sort_order", "archived_day", "created_at", "updated_at", "deleted_at", "deleted", "carried_to"]),
        new("snapshots", ["day", "sealed_at"]),
        new("pending_deleted_notes", ["note_id", "deleted_at", "day"]),
        new("pending_deleted_items", ["item_id", "deleted_at", "day"]),
        new("note_deletion_items", ["note_id", "item_id"]),
        new("business_settings", ["rollover_minutes"], true),
        new("business_preferences", ["hotkey_new", "hotkey_float", "login_prompt_answered", "login_intent"], true),
        new("checkpoint", ["active_day", "high_water"], true),
    ];
    private static bool IsTime(string name) => name.EndsWith("_at", StringComparison.Ordinal);
    private static bool IsBoolean(string name) => name is "completed" or "struck" or "deleted" or "automatic_height" or
        "collapsed" or "login_intent" or "login_prompt_answered";
    public static string Serialize(WindowsBackup backup) => JsonSerializer.Serialize(backup, JsonOptions);
    public static WindowsBackup Parse(string json)
    {
        var backup = JsonSerializer.Deserialize<WindowsBackup>(json, JsonOptions) ?? throw new InvalidDataException("备份内容为空。");
        ValidateHeader(backup);
        return backup;
    }
    private static void ValidateHeader(WindowsBackup backup)
    {
        if (backup.Format != "desknodes.windows.backup" || backup.Version != 1 || backup.Schema != 1)
            throw new InvalidDataException("不支持此备份格式或版本。");
        ParseTime(backup.ExportedAt);
    }
    private static long ParseTime(string? value)
    {
        if (value is null || !value.EndsWith('Z') || !DateTimeOffset.TryParseExact(value, "yyyy-MM-dd'T'HH:mm:ss.fff'Z'",
                CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var time))
            throw new InvalidDataException("备份时间须为 ISO-8601 UTC 毫秒格式。");
        return time.ToUnixTimeMilliseconds();
    }
    private static string FormatTime(long value) => DateTimeOffset.FromUnixTimeMilliseconds(value)
        .ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture);
    public static WindowsBackup Export(DeskNodesDatabase database, IClock clock) => database.Read(connection =>
    {
        // A deferred read transaction observes a single WAL snapshot without acquiring a write lock.
        using var transaction = connection.BeginTransaction(deferred: true);
        var payload = new Dictionary<string, object?>
        {
            ["format"] = "desknodes.windows.backup", ["version"] = 1, ["schema"] = 1,
            ["exportedAt"] = FormatTime(clock.UtcNow.ToUnixTimeMilliseconds())
        };
        foreach (var table in Tables)
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            string order = string.Join(',', table.Columns.Where(c => c is "id" or "note_id" or "item_id" or "day"));
            command.CommandText = $"SELECT {string.Join(',', table.Columns)} FROM {table.Name}" +
                (table.Singleton ? "" : $" ORDER BY {order}");
            using var reader = command.ExecuteReader();
            var rows = new List<Dictionary<string, object?>>();
            while (reader.Read())
            {
                var row = new Dictionary<string, object?>();
                for (int i = 0; i < table.Columns.Length; i++)
                {
                    string name = table.Columns[i];
                    row[name] = reader.IsDBNull(i) ? null : IsTime(name) ? FormatTime(reader.GetInt64(i)) :
                        IsBoolean(name) ? reader.GetBoolean(i) : reader.GetValue(i);
                }
                rows.Add(row);
            }
            payload[table.Name] = rows;
        }
        transaction.Commit();
        return Parse(JsonSerializer.Serialize(payload, JsonOptions));
    });

    public static DeskNodesDatabase Stage(WindowsBackup backup, string path)
    {
        ValidateHeader(backup);
        if (File.Exists(path))
            throw new IOException("临时数据库已存在。");
        var database = DeskNodesDatabase.Open(path);
        try
        {
            var payload = JsonSerializer.SerializeToElement(backup, JsonOptions);
            database.Transaction(connection =>
            {
                DeskNodesDatabase.Execute(connection, "DELETE FROM business_settings; DELETE FROM business_preferences;");
                foreach (var table in Tables)
                {
                    var rows = payload.GetProperty(table.Name);
                    if (rows.ValueKind != JsonValueKind.Array || (table.Singleton &&
                        (rows.GetArrayLength() > 1 || table.Name != "checkpoint" && rows.GetArrayLength() != 1)))
                        throw new InvalidDataException("备份业务设置不完整。");
                    foreach (var row in rows.EnumerateArray())
                    {
                        using var command = connection.CreateCommand();
                        command.CommandText = $"INSERT INTO {table.Name} ({(table.Singleton ? "singleton," : "")}{string.Join(',', table.Columns)}) " +
                            $"VALUES ({(table.Singleton ? "1," : "")}{string.Join(',', table.Columns.Select((_, i) => "$p" + i))})";
                        for (int i = 0; i < table.Columns.Length; i++)
                        {
                            string column = table.Columns[i];
                            var value = row.GetProperty(column);
                            command.Parameters.AddWithValue("$p" + i, ToSql(column, value));
                        }
                        command.ExecuteNonQuery();
                    }
                }
                ValidateState(connection);
            });
            var preferences = new BusinessPreferencesStore(database);
            preferences.Save(preferences.Load());
            database.Read(connection =>
            {
                using var command = connection.CreateCommand();
                command.CommandText = "PRAGMA foreign_key_check";
                using (var reader = command.ExecuteReader())
                    if (reader.Read())
                        throw new InvalidDataException("备份引用不完整。");
                command.CommandText = "PRAGMA integrity_check";
                if (!Equals(command.ExecuteScalar(), "ok"))
                    throw new InvalidDataException("备份完整性检查失败。");
                return 0;
            });
            // Re-read through the public protocol path before the caller can replace the live database.
            Export(database, new FixedExportClock(backup.ExportedAt));
            return database;
        }
        catch
        {
            database.Dispose();
            throw;
        }
    }
    private sealed class FixedExportClock(string time) : IClock
    {
        public DateTimeOffset UtcNow => DateTimeOffset.FromUnixTimeMilliseconds(ParseTime(time));
        public TimeZoneInfo TimeZone => TimeZoneInfo.Utc;
    }
    private static object ToSql(string column, JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Null)
            return DBNull.Value;
        if (value.ValueKind == JsonValueKind.String)
        {
            string text = value.GetString()!;
            if (IsTime(column))
                return ParseTime(text);
            if (column is "id" or "note_id" or "item_id")
                if (!Guid.TryParseExact(text, "D", out var id) || id == Guid.Empty || id.ToString("D") != text)
                    throw new InvalidDataException("备份 ID 须为小写 GUID。");
            if (column is "day" or "active_day" or "high_water" or "archived_day" or "carried_to")
                _ = HistoryDay.Parse(text);
            return text;
        }
        if (value.ValueKind is JsonValueKind.True or JsonValueKind.False)
            return value.GetBoolean();
        if (value.TryGetInt64(out long integer))
            return integer;
        double number = value.GetDouble();
        if (!double.IsFinite(number))
            throw new InvalidDataException("备份坐标无效。");
        return number;
    }
    private static void ValidateState(SqliteConnection connection)
    {
        string[] invalidQueries =
        [
            "SELECT 1 FROM notes n JOIN items i ON n.id=i.id",
            "SELECT 1 FROM snapshot_notes n JOIN snapshot_items i ON n.day=i.day AND n.note_id=i.item_id",
            "SELECT 1 FROM snapshots s WHERE NOT EXISTS (SELECT 1 FROM checkpoint c WHERE c.active_day>s.day)",
            "SELECT 1 FROM items WHERE archived_day IS NOT NULL AND NOT (completed OR struck)",
            "SELECT 1 FROM snapshot_notes WHERE deleted != (deleted_at IS NOT NULL)",
            "SELECT 1 FROM snapshot_items WHERE deleted != (deleted_at IS NOT NULL) OR (archived_day IS NOT NULL AND NOT (completed OR struck)) OR (carried_to IS NOT NULL AND (carried_to<=day OR completed OR struck OR deleted OR archived_day IS NOT NULL))",
            "SELECT 1 FROM snapshot_items i JOIN snapshot_notes n ON n.day=i.day AND n.note_id=i.note_id WHERE i.carried_to IS NOT NULL AND n.deleted",
            "SELECT 1 FROM pending_deleted_notes p JOIN notes n ON n.id=p.note_id WHERE n.deleted_at IS NULL OR n.deleted_at!=p.deleted_at",
            "SELECT 1 FROM pending_deleted_items p JOIN items i ON i.id=p.item_id WHERE i.deleted_at IS NULL OR i.deleted_at!=p.deleted_at",
            "SELECT 1 FROM note_deletion_items d JOIN items i ON i.id=d.item_id JOIN notes n ON n.id=d.note_id WHERE i.note_id!=d.note_id OR n.deleted_at IS NULL OR i.deleted_at IS NULL"
        ];
        foreach (string query in invalidQueries)
        {
            using var command = connection.CreateCommand();
            command.CommandText = query;
            if (command.ExecuteScalar() is not null)
                throw new InvalidDataException("备份业务状态不一致。");
        }
    }

    public static void Publish(string path, WindowsBackup backup)
    {
        ValidateHeader(backup);
        string temporary = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(path))!, $".desknodes-{Guid.NewGuid():N}.tmp");
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                JsonSerializer.Serialize(stream, backup, JsonOptions);
                stream.Flush(flushToDisk: true);
            }
            if (File.Exists(path))
                File.Replace(temporary, path, null);
            else
                File.Move(temporary, path);
        }
        finally
        {
            if (File.Exists(temporary))
                File.Delete(temporary);
        }
    }
}
