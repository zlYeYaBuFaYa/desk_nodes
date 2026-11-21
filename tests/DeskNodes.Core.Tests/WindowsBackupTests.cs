using System.Text.Json.Nodes;
using DeskNodes.Core.Backup;
using DeskNodes.Core.Domain;
using DeskNodes.Core.Storage;
using DeskNodes.Core.Services;
using static DeskNodes.Core.Tests.TestData;

namespace DeskNodes.Core.Tests;

public sealed class WindowsBackupTests
{
    private static string Golden => File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "backup-v1.json"));
    private sealed class Clock : IClock
    {
        public DateTimeOffset UtcNow => Now;
        public TimeZoneInfo TimeZone => TimeZoneInfo.Utc;
    }
    private sealed class CancellingStream(byte[] bytes, CancellationTokenSource cancellation) : MemoryStream(bytes)
    {
        public override ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
        {
            var read = base.ReadAsync(buffer[..Math.Min(buffer.Length, 64)], cancellationToken);
            cancellation.Cancel();
            return read;
        }
    }

    [Fact]
    public void DuplicateJsonPropertiesAreRejected()
    {
        const string needle = "\"format\"";
        int at = Golden.IndexOf(needle, StringComparison.Ordinal);
        string duplicated = Golden.Insert(at, "\"format\": \"desknodes.windows.backup\", ");
        Assert.Throws<System.Text.Json.JsonException>(() => WindowsBackupCodec.Parse(duplicated));
    }

    [Fact]
    public void CancellationDuringReadStopsParsingAndLeavesLiveDatabaseUnchanged()
    {
        using var directory = new TestDirectory();
        using var live = DeskNodesDatabase.Open(Path.Combine(directory.DirectoryPath, "live.sqlite3"));
        var repository = new NoteRepository(live);
        var note = Note();
        repository.Insert(note);
        using var cancellation = new CancellationTokenSource();
        using var stream = new CancellingStream(System.Text.Encoding.UTF8.GetBytes(Golden), cancellation);
        Assert.Throws<OperationCanceledException>(() => WindowsBackupCodec.Parse(stream, cancellation.Token));
        Assert.Equal(note, Assert.Single(repository.GetNotes()));
        Assert.True(stream.Position < stream.Length);
    }

    [Fact]
    public void CancellationAfterDatabaseCreationRemovesAllStagingFilesAndPreservesLiveData()
    {
        using var directory = new TestDirectory();
        using var live = DeskNodesDatabase.Open(Path.Combine(directory.DirectoryPath, "live.sqlite3"));
        var repository = new NoteRepository(live);
        var note = Note();
        repository.Insert(note);
        var backup = WindowsBackupCodec.Parse(Golden);
        string before = WindowsBackupCodec.Serialize(WindowsBackupCodec.Export(live, new Clock()));
        string path = Path.Combine(directory.DirectoryPath, ".import-test.sqlite3");
        using var cancellation = new CancellationTokenSource();
        bool observed = false;
        Assert.Throws<OperationCanceledException>(() => WindowsBackupCodec.Stage(backup, path, cancellation.Token, () =>
        {
            observed = true;
            Assert.True(File.Exists(path));
            cancellation.Cancel();
        }));
        Assert.True(observed);
        Assert.Equal(before, WindowsBackupCodec.Serialize(WindowsBackupCodec.Export(live, new Clock())));
        Assert.Empty(Directory.GetFiles(directory.DirectoryPath, ".import-*"));
        Assert.Equal(note, Assert.Single(repository.GetNotes()));
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void CheckpointMayBeAbsentOnlyWithoutSnapshots(bool hasCheckpoint)
    {
        using var directory = new TestDirectory();
        var root = JsonNode.Parse(Golden)!;
        root["snapshots"] = new JsonArray();
        root["snapshot_notes"] = new JsonArray();
        root["snapshot_items"] = new JsonArray();
        if (!hasCheckpoint)
            root["checkpoint"] = new JsonArray();
        using var stage = WindowsBackupCodec.Stage(WindowsBackupCodec.Parse(root.ToJsonString()),
            Path.Combine(directory.DirectoryPath, "stage.sqlite3"));
        Assert.Equal(0L, stage.Read(c => Scalar(c, "SELECT count(*) FROM snapshots")));
        var checkpoint = WindowsBackupCodec.Export(stage, new Clock()).Checkpoint;
        Assert.Equal(hasCheckpoint ? 1 : 0, checkpoint.Count);
        if (hasCheckpoint)
        {
            Assert.Equal(1L, stage.Read(c => Scalar(c, "SELECT singleton FROM checkpoint")));
            Assert.Equal(WindowsBackupCodec.Parse(Golden).Checkpoint[0], Assert.Single(checkpoint));
        }
    }

    [Fact]
    public void GoldenRoundTripPreservesAllBusinessTablesAndRestoresThroughBackupApi()
    {
        using var directory = new TestDirectory();
        var backup = WindowsBackupCodec.Parse(Golden);
        using var staging = WindowsBackupCodec.Stage(backup, Path.Combine(directory.DirectoryPath, "stage.sqlite3"));
        var actual = WindowsBackupCodec.Export(staging, new Clock());
        Assert.True(JsonNode.DeepEquals(JsonNode.Parse(Golden), JsonNode.Parse(WindowsBackupCodec.Serialize(actual))));
        using var live = directory.Open();
        new NoteRepository(live).Insert(Note());
        live.ReplaceFrom(staging);
        Assert.Equal(WindowsBackupCodec.Serialize(actual), WindowsBackupCodec.Serialize(WindowsBackupCodec.Export(live, new Clock())));
        Assert.Empty(new NoteRepository(live).GetNotes()); // golden current note is a tombstone
        Assert.Equal(1L, live.Read(c => Scalar(c, "SELECT count(*) FROM snapshots")));
        Assert.Equal("ok", live.Read(c => Scalar(c, "PRAGMA integrity_check")));
        Assert.Throws<Microsoft.Data.Sqlite.SqliteException>(() => live.Transaction(c => Execute(c, "DELETE FROM snapshots")));
    }
    [Theory]
    [InlineData("format")]
    [InlineData("version")]
    [InlineData("schema")]
    [InlineData("time")]
    [InlineData("duplicate")]
    [InlineData("uuid")]
    [InlineData("reference")]
    [InlineData("exclusive")]
    [InlineData("archive")]
    [InlineData("carry")]
    [InlineData("deleted")]
    [InlineData("pending")]
    [InlineData("membership")]
    [InlineData("date")]
    [InlineData("hotkeys")]
    [InlineData("settings")]
    [InlineData("checkpoint")]
    [InlineData("geometry")]
    [InlineData("unknown")]
    [InlineData("missing")]
    [InlineData("header_missing")]
    [InlineData("uuid_uppercase")]
    [InlineData("snapshot_id_collision")]
    [InlineData("snapshot_without_checkpoint")]
    [InlineData("snapshot_equal_active")]
    [InlineData("snapshot_after_active")]
    public void InvalidInputNeverChangesLiveDatabase(string invalid)
    {
        using var directory = new TestDirectory();
        using var live = directory.Open();
        new NoteRepository(live).Insert(Note());
        string before = WindowsBackupCodec.Serialize(WindowsBackupCodec.Export(live, new Clock()));
        var root = JsonNode.Parse(Golden)!;
        var note = root["notes"]![0]!;
        var item = root["items"]![0]!;
        switch (invalid)
        {
            case "snapshot_id_collision": root["snapshot_items"]![0]!["item_id"] = root["snapshot_notes"]![0]!["note_id"]!.GetValue<string>(); break;
            case "snapshot_without_checkpoint": root["checkpoint"] = new JsonArray(); break;
            case "snapshot_equal_active": root["checkpoint"]![0]!["active_day"] = "2026-11-14"; break;
            case "snapshot_after_active": root["checkpoint"]![0]!["active_day"] = "2026-11-13"; break;
            case "format": root["format"] = "mac.backup"; break;
            case "version": root["version"] = 2; break;
            case "schema": root["schema"] = 2; break;
            case "time": root["exportedAt"] = "2026-11-15T12:30:00+01:00"; break;
            case "duplicate": root["notes"]!.AsArray().Add(note.DeepClone()); break;
            case "uuid": note["id"] = "bad"; break;
            case "reference": item["note_id"] = Guid.NewGuid().ToString(); break;
            case "exclusive": item["completed"] = true; item["struck"] = true; break;
            case "archive": item["archived_day"] = "2026-11-14"; break;
            case "carry": root["snapshot_items"]![0]!["carried_to"] = "2026-11-13"; break;
            case "deleted": root["snapshot_notes"]![0]!["deleted"] = true; break;
            case "pending": root["pending_deleted_items"]![0]!["deleted_at"] = "2026-11-15T12:00:00.000Z"; break;
            case "membership": item["deleted_at"] = null; root["pending_deleted_items"] = new JsonArray(); break;
            case "date": root["checkpoint"]![0]!["active_day"] = "2026-02-30"; break;
            case "hotkeys": root["business_preferences"]![0]!["hotkey_float"] = "Ctrl+Alt+N"; break;
            case "settings": root["business_settings"] = new JsonArray(); break;
            case "checkpoint": root["checkpoint"]![0]!["high_water"] = "2026-11-14"; break;
            case "geometry": note["width"] = -1; break;
            case "unknown": root["sql"] = "DROP TABLE notes"; break;
            case "missing": root.AsObject().Remove("items"); break;
            case "header_missing": root.AsObject().Remove("format"); break;
            case "uuid_uppercase": note["id"] = "AAAAAAAA-1111-4111-8111-111111111111"; break;
        }
        string path = Path.Combine(directory.DirectoryPath, "bad.sqlite3");
        if (invalid is "unknown" or "missing" or "header_missing")
            Assert.Throws<System.Text.Json.JsonException>(() => WindowsBackupCodec.Parse(root.ToJsonString()));
        else if (invalid is "format" or "version" or "schema" or "time")
        {
            var error = Assert.Throws<InvalidDataException>(() => WindowsBackupCodec.Parse(root.ToJsonString()));
            Assert.Contains(invalid == "time" ? "ISO-8601 UTC" : "格式或版本", error.Message);
        }
        else
        {
            var parsed = WindowsBackupCodec.Parse(root.ToJsonString());
            Type expected = invalid switch
            {
                "date" => typeof(FormatException),
                "hotkeys" => typeof(ArgumentException),
                "duplicate" or "reference" or "exclusive" or "geometry" or "checkpoint" => typeof(Microsoft.Data.Sqlite.SqliteException),
                _ => typeof(InvalidDataException)
            };
            var error = Assert.Throws(expected, () => WindowsBackupCodec.Stage(parsed, path));
            if (error is Microsoft.Data.Sqlite.SqliteException sqlite)
            {
                Assert.Equal(19, sqlite.SqliteErrorCode); // SQLITE_CONSTRAINT
                Assert.Equal(invalid switch
                {
                    "duplicate" => 1555, // SQLITE_CONSTRAINT_PRIMARYKEY
                    "reference" => 787, // SQLITE_CONSTRAINT_FOREIGNKEY
                    _ => 275 // SQLITE_CONSTRAINT_CHECK
                }, sqlite.SqliteExtendedErrorCode);
            }
            else
            {
                string message = invalid switch
                {
                    "uuid" or "uuid_uppercase" => "小写 GUID",
                    "date" => "YYYY-MM-DD",
                    "hotkeys" => "快捷键不能相同",
                    "settings" => "业务设置不完整",
                    _ => "业务状态不一致"
                };
                Assert.Contains(message, error.Message);
            }
        }
        Assert.Empty(Directory.GetFiles(directory.DirectoryPath, "bad.sqlite3*"));
        Assert.Equal(before, WindowsBackupCodec.Serialize(WindowsBackupCodec.Export(live, new Clock())));
    }
    [Fact]
    public void ReplacementInsideTransactionIsRejectedAndOriginalDataSurvives()
    {
        using var directory = new TestDirectory();
        using var live = directory.Open();
        var note = Note();
        new NoteRepository(live).Insert(note);
        using var stage = WindowsBackupCodec.Stage(WindowsBackupCodec.Parse(Golden), Path.Combine(directory.DirectoryPath, "stage.sqlite3"));
        Assert.Throws<InvalidOperationException>(() => live.Transaction(_ => live.ReplaceFrom(stage)));
        Assert.Equal(note, Assert.Single(new NoteRepository(live).GetNotes()));
    }
    [Fact]
    public void DestinationWriteLockCausesBackupFailureAndPreservesLiveData()
    {
        using var directory = new TestDirectory();
        using var live = directory.Open();
        var note = Note();
        new NoteRepository(live).Insert(note);
        using var stage = WindowsBackupCodec.Stage(WindowsBackupCodec.Parse(Golden), Path.Combine(directory.DirectoryPath, "stage.sqlite3"));
        using var other = new Microsoft.Data.Sqlite.SqliteConnection($"Data Source={directory.DatabasePath};Pooling=False");
        other.Open();
        Execute(other, "BEGIN IMMEDIATE");
        try
        {
            Assert.Throws<Microsoft.Data.Sqlite.SqliteException>(() => live.ReplaceFrom(stage));
            Assert.Equal(note, Assert.Single(new NoteRepository(live).GetNotes()));
        }
        finally
        {
            Execute(other, "ROLLBACK");
        }
    }
    [Fact]
    public void PublishReplacesExistingFileAndFailureKeepsOriginalAndCleansTemporaryFile()
    {
        using var directory = new TestDirectory();
        string target = Path.Combine(directory.DirectoryPath, "backup.json");
        File.WriteAllText(target, "original");
        var backup = WindowsBackupCodec.Parse(Golden);
        WindowsBackupCodec.Publish(target, backup);
        Assert.Equal(WindowsBackupCodec.Serialize(backup), File.ReadAllText(target));
        string before = File.ReadAllText(target);
        // Invalid metadata cannot replace an existing export.
        Assert.ThrowsAny<Exception>(() => WindowsBackupCodec.Publish(target, backup with { ExportedAt = null! }));
        Assert.Equal(before, File.ReadAllText(target));
        Assert.Empty(Directory.GetFiles(directory.DirectoryPath, ".desknodes-*.tmp"));
    }
    [Fact]
    public void PublicationFailureAfterFlushKeepsDestinationAndDeletesTemporaryFile()
    {
        using var directory = new TestDirectory();
        string target = Path.Combine(directory.DirectoryPath, "backup.json");
        Directory.CreateDirectory(target);
        string retained = Path.Combine(target, "original");
        File.WriteAllText(retained, "retained");
        Assert.ThrowsAny<IOException>(() => WindowsBackupCodec.Publish(target, WindowsBackupCodec.Parse(Golden)));
        Assert.Equal("retained", File.ReadAllText(retained));
        Assert.Empty(Directory.GetFiles(directory.DirectoryPath, ".desknodes-*.tmp"));
    }

    [Theory]
    [InlineData("notes", 2147483647L)]
    [InlineData("snapshot_notes", 2147483647L)]
    [InlineData("notes", 2147483648L)]
    [InlineData("snapshot_notes", 2147483648L)]
    [InlineData("notes", long.MaxValue)]
    [InlineData("snapshot_notes", long.MaxValue)]
    public void DockOrderMustFitDomainAndFailurePreservesLiveDatabase(string table, long order)
    {
        using var directory = new TestDirectory();
        using var live = directory.Open();
        var original = Note();
        new NoteRepository(live).Insert(original);
        var root = JsonNode.Parse(Golden)!;
        root[table]![0]!["dock_edge"] = "left";
        root[table]![0]!["dock_order"] = order;
        var backup = WindowsBackupCodec.Parse(root.ToJsonString());
        string path = Path.Combine(directory.DirectoryPath, "stage.sqlite3");
        if (order > int.MaxValue)
        {
            Assert.Throws<InvalidDataException>(() =>
            {
                using var invalid = WindowsBackupCodec.Stage(backup, path);
                live.ReplaceFrom(invalid);
            });
            Assert.Equal(original, Assert.Single(new NoteRepository(live).GetNotes(true)));
            return;
        }
        using var stage = WindowsBackupCodec.Stage(backup, path);
        live.ReplaceFrom(stage);
        var repo = new NoteRepository(live);
        var note = Assert.Single(repo.GetNotes(true));
        Assert.Single(repo.GetItems(note.Id, true, true));
        var frozen = Assert.Single(new HistoryQueries(live).DaySnapshot(HistoryDay.Parse("2026-11-14")).Notes);
        Assert.Single(frozen.Items);
        Assert.Equal(int.MaxValue, table == "notes" ? note.Placement.DockOrder : frozen.Note.Placement.DockOrder);
    }

}
