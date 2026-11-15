using DeskNodes.Core.Domain;
using DeskNodes.Core.Storage;

namespace DeskNodes.Core.Services;

public enum RestoreResult { Restored, NotFoundOrNotDeleted, ParentDeleted, Archived }
public sealed record DeletedEntry(DeletionMember Member, NoteId ParentId, string Title, NoteColor Color,
    DateTimeOffset DeletedAt, string? Text, IReadOnlyList<string> Preview, int RemainingCount);

public sealed class RecentlyDeleted(DeskNodesDatabase database, IClock clock, DeletionUndoQueue undo)
{
    private readonly NoteRepository repository = new(database);
    private static readonly string Whitespace = new(Enumerable.Range(0, char.MaxValue + 1)
        .Select(i => (char)i).Where(char.IsWhiteSpace).ToArray());
    // Inclusive lower boundary: at most 30*86400 elapsed seconds; future tombstones are excluded.
    private const string Candidates = """
        SELECT n.id note_id,NULL item_id,n.deleted_at FROM notes n
        WHERE n.deleted_at BETWEEN $since AND $now
        UNION ALL
        SELECT i.note_id,i.id,i.deleted_at FROM items i JOIN notes n ON n.id=i.note_id
        WHERE i.deleted_at BETWEEN $since AND $now AND i.archived_day IS NULL
        AND length(trim(i.text,$whitespace))>0
        AND NOT EXISTS(SELECT 1 FROM note_deletion_items m WHERE m.item_id=i.id)
        """;

    public int Count() => database.Read(connection =>
    {
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT count(*) FROM (" + Candidates + ");";
        BindTimes(command);
        return Convert.ToInt32(command.ExecuteScalar());
    });

    public IReadOnlyList<DeletedEntry> List() => database.Read(connection =>
    {
        var keys = new List<(NoteId Note, ItemId? Item, DateTimeOffset At)>();
        using (var command = connection.CreateCommand())
        {
            command.CommandText = Candidates + " ORDER BY deleted_at DESC,note_id,item_id;";
            BindTimes(command);
            using var reader = command.ExecuteReader();
            while (reader.Read()) keys.Add((NoteId.Parse(reader.GetString(0)), reader.IsDBNull(1) ? null : ItemId.Parse(reader.GetString(1)), DateTimeOffset.FromUnixTimeMilliseconds(reader.GetInt64(2))));
        }
        return (IReadOnlyList<DeletedEntry>)keys.Select(key =>
        {
            var note = repository.GetNote(key.Note, true) ?? throw new KeyNotFoundException();
            if (key.Item is { } id)
                return new DeletedEntry(new(null, id), note.Id, note.Title, note.Color, key.At,
                    (repository.GetItem(id, true) ?? throw new KeyNotFoundException()).Text, [], 0);
            var childIds = new HashSet<ItemId>();
            using (var children = connection.CreateCommand())
            {
                children.CommandText = "SELECT item_id FROM note_deletion_items WHERE note_id=$id;";
                children.Parameters.AddWithValue("$id", note.Id.ToString());
                using var reader = children.ExecuteReader();
                while (reader.Read()) childIds.Add(ItemId.Parse(reader.GetString(0)));
            }
            var preview = repository.GetItems(key.Note, true).Where(i => childIds.Contains(i.Id) && !string.IsNullOrWhiteSpace(i.Text)).Select(i => i.Text).ToArray();
            return new DeletedEntry(new(note.Id, null), note.Id, note.Title, note.Color, key.At, null, preview.Take(4).ToArray(), Math.Max(0, preview.Length - 4));
        }).ToArray();
    });

    public RestoreResult Restore(NoteId id)
    {
        bool restored = database.Transaction(connection =>
        {
            if (!repository.Restore(id, clock.UtcNow)) return false;
            ServiceSql.Run(connection, "UPDATE notes SET collapsed=0 WHERE id=$id;", ("$id", id.ToString()));
            return true;
        });
        if (!restored) return RestoreResult.NotFoundOrNotDeleted;
        undo.RemoveMember(new(id, null));
        return RestoreResult.Restored;
    }

    public RestoreResult Restore(ItemId id)
    {
        var result = database.Transaction(_ =>
        {
            var item = repository.GetItem(id, true, true);
            if (item?.DeletedAt is null) return RestoreResult.NotFoundOrNotDeleted;
            if (item.ArchivedDay is not null) return RestoreResult.Archived;
            if ((repository.GetNote(item.NoteId, true) ?? throw new KeyNotFoundException()).DeletedAt is not null) return RestoreResult.ParentDeleted;
            return repository.Restore(id, clock.UtcNow) ? RestoreResult.Restored : RestoreResult.NotFoundOrNotDeleted;
        });
        if (result == RestoreResult.Restored) undo.RemoveMember(new(null, id));
        return result;
    }

    private void BindTimes(Microsoft.Data.Sqlite.SqliteCommand command)
    {
        var now = clock.UtcNow;
        command.Parameters.AddWithValue("$whitespace", Whitespace);
        command.Parameters.AddWithValue("$now", now.ToUnixTimeMilliseconds());
        command.Parameters.AddWithValue("$since", now.AddSeconds(-30 * 86400).ToUnixTimeMilliseconds());
    }
}
