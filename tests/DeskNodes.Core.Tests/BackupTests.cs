using DeskNodes.Core.Domain;
using DeskNodes.Core.Services;
using DeskNodes.Core.Storage;
using Microsoft.Data.Sqlite;
using static DeskNodes.Core.Tests.TestData;

namespace DeskNodes.Core.Tests;

public sealed class BackupTests
{
    [Fact]
    public void VacuumCopyContainsCommittedWalDataAndSameDayIsNotOverwritten()
    {
        using var fixture = new RolloverTests.Fixture();
        var repository = new NoteRepository(fixture.Database);
        var note = Note(); repository.Insert(note);
        var day = HistoryDay.Parse("2026-11-15");
        fixture.Backup.Create(day);
        string path = Path.Combine(fixture.Directory.DirectoryPath, "Backups", $"DeskNodes-{day}.sqlite3");
        byte[] original = File.ReadAllBytes(path);
        repository.Insert(Item(note.Id));
        fixture.Backup.Create(day);
        Assert.Equal(original, File.ReadAllBytes(path));
        using var copy = DeskNodesDatabase.Open(path);
        Assert.Equal(note, Assert.Single(new NoteRepository(copy).GetNotes()));
        Assert.Empty(new NoteRepository(copy).GetItems(note.Id));
        Assert.Equal("ok", copy.Read(c => Scalar(c, "PRAGMA integrity_check;")));
        Assert.Empty(Directory.GetFiles(Path.GetDirectoryName(path)!, ".partial-*"));
        Assert.Empty(fixture.Log.Errors);
    }

    [Fact]
    public void KeepsSevenNewestValidDatesAndIgnoresPartialAndMalformedNames()
    {
        using var fixture = new RolloverTests.Fixture();
        string directory = Path.Combine(fixture.Directory.DirectoryPath, "Backups");
        Directory.CreateDirectory(directory);
        string[] ignored = [".partial-old.sqlite3", "DeskNodes-2026-02-30.sqlite3", "other.sqlite3", "DeskNodes-2026-1-01.sqlite3"];
        foreach (string name in ignored) File.WriteAllText(Path.Combine(directory, name), "retained");
        for (int index = 0; index < 10; index++)
            fixture.Backup.Create(new(new DateOnly(2026, 11, 1).AddDays(index)));
        foreach (string name in ignored) Assert.True(File.Exists(Path.Combine(directory, name)));
        Assert.Equal(11, Directory.GetFiles(directory).Length);
        Assert.False(File.Exists(Path.Combine(directory, "DeskNodes-2026-11-03.sqlite3")));
        Assert.True(File.Exists(Path.Combine(directory, "DeskNodes-2026-11-04.sqlite3")));
        // An older date created later cannot evict any newer copy.
        fixture.Backup.Create(HistoryDay.Parse("2026-10-31"));
        Assert.Equal(11, Directory.GetFiles(directory).Length);
        Assert.False(File.Exists(Path.Combine(directory, "DeskNodes-2026-10-31.sqlite3")));
        Assert.Empty(fixture.Log.Errors);
    }

    [Fact]
    public void BackupFailureOnlyLogsAndRolloverStaysCommitted()
    {
        using var fixture = new RolloverTests.Fixture();
        File.WriteAllText(Path.Combine(fixture.Directory.DirectoryPath, "Backups"), "blocks directory creation");
        fixture.Service.CheckAndAdvance();
        fixture.Clock.UtcNow = Now.AddDays(1);
        Assert.Equal(RolloverStatus.Sealed, fixture.Service.CheckAndAdvance().Status);
        Assert.Single(fixture.Log.Errors);
        Assert.Equal(1L, fixture.Query("SELECT count(*) FROM snapshots;"));
        Assert.Equal("2026-11-16", fixture.Query("SELECT active_day FROM checkpoint;"));
    }

    [Fact]
    public void VacuumFailureDoesNotPublishCopy()
    {
        using var fixture = new RolloverTests.Fixture();
        // SQLite explicitly rejects VACUUM within a transaction.
        fixture.Database.Transaction(_ => fixture.Backup.Create(HistoryDay.Parse("2026-11-15")));
        Assert.Single(fixture.Log.Errors);
        Assert.Empty(Directory.GetFiles(Path.Combine(fixture.Directory.DirectoryPath, "Backups")));
    }

    [Fact]
    public void QueriesDoNotAcquireWriteLock()
    {
        using var fixture = new RolloverTests.Fixture();
        var repository = new NoteRepository(fixture.Database);
        var note = Note(); repository.Insert(note);
        repository.Insert(Item(note.Id));
        using var other = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = fixture.Directory.DatabasePath, Pooling = false
        }.ToString());
        other.Open();
        Execute(other, "BEGIN IMMEDIATE;");
        try
        {
            Assert.Single(repository.GetNotes());
            Assert.Single(repository.GetItems(note.Id));
        }
        finally { Execute(other, "ROLLBACK;"); }
    }
}
