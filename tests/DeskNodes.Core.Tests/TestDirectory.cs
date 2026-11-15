using DeskNodes.Core.Domain;
using DeskNodes.Core.Storage;
using Microsoft.Data.Sqlite;

namespace DeskNodes.Core.Tests;

internal sealed class TestDirectory : IDisposable
{
    public string DirectoryPath { get; } = Path.Combine(Path.GetTempPath(), "DeskNodes.Tests", Guid.NewGuid().ToString("N"));
    public string DatabasePath => Path.Combine(DirectoryPath, DataDirectory.DatabaseFileName);

    public TestDirectory() => Directory.CreateDirectory(DirectoryPath);
    public DeskNodesDatabase Open() => DeskNodesDatabase.Open(DatabasePath);
    public void Dispose() => Directory.Delete(DirectoryPath, recursive: true);
}

internal static class TestData
{
    public static readonly DateTimeOffset Now = new(2026, 11, 15, 12, 30, 0, TimeSpan.Zero);

    public static Note Note(long order = 0, NoteColor color = NoteColor.Paper) => new(NoteId.New(),
        "标题 ' 中文", color, order, new Placement(new RectD(-120, 10, 288, 240), "DISPLAY1"),
        NoteLevel.Back, null, true, false, Now, Now);

    public static NoteItem Item(NoteId noteId, long order = 0, bool completed = false, bool struck = false,
        HistoryDay? archivedDay = null) => new(ItemId.New(), noteId, "事项 '\n第二行", completed, struck, order,
            archivedDay, Now, Now);

    public static void Execute(SqliteConnection connection, string sql)
    {
        using var command = connection.CreateCommand();
        command.CommandText = sql;
        command.ExecuteNonQuery();
    }

    public static object? Scalar(SqliteConnection connection, string sql)
    {
        using var command = connection.CreateCommand();
        command.CommandText = sql;
        return command.ExecuteScalar();
    }

    public static void SealSnapshot(DeskNodesDatabase database)
    {
        var repository = new NoteRepository(database);
        Note note = Note();
        repository.Insert(note);
        repository.Insert(Item(note.Id, completed: true));
        database.Transaction(connection =>
        {
            Execute(connection, "INSERT INTO snapshot_notes SELECT '2026-11-14', n.*, 0 FROM notes n;");
            Execute(connection, "INSERT INTO snapshot_items SELECT '2026-11-14', i.*, 0, NULL FROM items i;");
            Execute(connection, "INSERT INTO snapshots(day,sealed_at) VALUES ('2026-11-14',1000);");
        });
    }
}
