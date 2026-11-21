using DeskNodes.Core.Domain;
using DeskNodes.Core.Services;
using DeskNodes.Core.Storage;
using static DeskNodes.Core.Tests.TestData;

namespace DeskNodes.Core.Tests;

public sealed class RolloverTests
{
    [Fact]
    public void InitializationAndSameDayCheckDoNotCreateHistory()
    {
        using var fixture = new Fixture();
        fixture.Barrier.Callback = () => throw new InvalidOperationException("Initialization must not commit.");
        Assert.Equal(RolloverStatus.Initialized, fixture.Service.CheckAndAdvance().Status);
        Assert.Equal(RolloverStatus.NoChange, fixture.Service.CheckAndAdvance().Status);
        Assert.Equal(0L, fixture.Query("SELECT count(*) FROM snapshots;"));
        Assert.Equal("2026-11-15", fixture.Query("SELECT active_day FROM checkpoint;"));
        Assert.Equal("2026-11-15", fixture.Query("SELECT high_water FROM checkpoint;"));
        Assert.False(Directory.Exists(Path.Combine(fixture.Directory.DirectoryPath, "Backups")));
    }

    [Theory]
    [InlineData(1)]
    [InlineData(12)]
    public void OnlyObservedDaySealedWithFrozenStateAndDeletedMembers(int gap)
    {
        using var fixture = new Fixture();
        fixture.Service.CheckAndAdvance();
        var repository = new NoteRepository(fixture.Database);
        var note = Note();
        var deletedNote = Note(1);
        repository.Insert(note);
        repository.Insert(deletedNote);
        var unfinished = Item(note.Id);
        repository.Insert(unfinished);
        repository.Insert(Item(note.Id, 1, completed: true));
        repository.Insert(Item(note.Id, 2, struck: true));
        var deletedItem = Item(note.Id, 3, completed: true);
        repository.Insert(deletedItem);
        repository.Insert(Item(deletedNote.Id));
        var active = HistoryDay.Parse("2026-11-15");
        repository.SoftDelete(deletedItem.Id, Now, active);
        repository.SoftDelete(deletedNote.Id, Now, active);
        Assert.Equal("2026-11-15", fixture.Query("SELECT day FROM pending_deleted_notes;"));
        fixture.Clock.UtcNow = Now.AddDays(gap);
        RolloverResult result = fixture.Service.CheckAndAdvance();
        Assert.Equal(RolloverStatus.Sealed, result.Status);
        Assert.Equal(active, result.Day);
        Assert.Equal(1, result.CarriedCount);
        Assert.Equal(3, result.ArchivedCount);
        Assert.Equal(1L, fixture.Query("SELECT count(*) FROM snapshots;"));
        Assert.Equal(2L, fixture.Query("SELECT count(*) FROM snapshot_notes;"));
        Assert.Equal(5L, fixture.Query("SELECT count(*) FROM snapshot_items;"));
        Assert.Equal(2L, fixture.Query("SELECT count(*) FROM snapshot_items WHERE deleted=1;"));
        Assert.Equal(1L, fixture.Query("SELECT count(*) FROM snapshot_notes WHERE deleted=1;"));
        string next = new HistoryDay(active.Value.AddDays(gap)).ToString();
        Assert.Equal(next, fixture.Query("SELECT carried_to FROM snapshot_items WHERE carried_to IS NOT NULL;"));
        Assert.Equal(next, fixture.Query("SELECT active_day FROM checkpoint;"));
        Assert.Equal(0L, fixture.Query("SELECT count(*) FROM pending_deleted_items;"));
        Assert.Equal(0L, fixture.Query("SELECT count(*) FROM pending_deleted_notes;"));
        Assert.Equal(unfinished, Assert.Single(repository.GetItems(note.Id)));
        fixture.Database.Transaction(c => Execute(c, "UPDATE items SET text='changed',completed=1 WHERE archived_day IS NULL; UPDATE notes SET title='changed';"));
        Assert.Equal(unfinished.Text, fixture.Query("SELECT text FROM snapshot_items WHERE carried_to IS NOT NULL;"));
        Assert.Equal(note.Title, fixture.Query("SELECT title FROM snapshot_notes WHERE deleted=0;"));
        // Statistics are based on frozen occurrences, including deleted completed members and excluding struck ones.
        Assert.Equal(2L, fixture.Query("SELECT count(*) FROM snapshot_items WHERE completed=1;"));
        Assert.Equal(4L, fixture.Query("SELECT count(*) FROM snapshot_items WHERE struck=0;"));
        Assert.Equal(RolloverStatus.NoChange, fixture.Service.CheckAndAdvance().Status);
        Assert.Single(Directory.GetFiles(Path.Combine(fixture.Directory.DirectoryPath, "Backups")));
    }

    [Fact]
    public void ClockRegressionPreservesCheckpointAndDoesNotCommit()
    {
        using var fixture = new Fixture();
        fixture.Service.CheckAndAdvance();
        fixture.Clock.UtcNow = Now.AddDays(-1);
        fixture.Barrier.Callback = () => throw new InvalidOperationException();
        Assert.Equal(RolloverStatus.ClockRegressed, fixture.Service.CheckAndAdvance().Status);
        Assert.Equal("2026-11-15", fixture.Query("SELECT active_day FROM checkpoint;"));
        Assert.Equal(0L, fixture.Query("SELECT count(*) FROM snapshots;"));
        Assert.Equal(RolloverStatus.ClockRegressed, fixture.Service.CheckAndAdvance().Status);
        Assert.Single(fixture.Log.Warnings);
        fixture.Clock.UtcNow = Now;
        Assert.Equal(RolloverStatus.NoChange, fixture.Service.CheckAndAdvance().Status);
        fixture.Clock.UtcNow = Now.AddDays(-2);
        Assert.Equal(RolloverStatus.ClockRegressed, fixture.Service.CheckAndAdvance().Status);
        Assert.Equal(2, fixture.Log.Warnings.Count);
    }

    [Theory]
    [InlineData(CommitResult.Composing, RolloverStatus.Deferred)]
    [InlineData(CommitResult.Failed, RolloverStatus.Failed)]
    public void RejectedCommitRollsBackAnyBarrierWrites(CommitResult commit, RolloverStatus expected)
    {
        using var fixture = new Fixture();
        Assert.Equal(RolloverStatus.Initialized, fixture.Service.CheckAndAdvance().Status);
        fixture.Clock.UtcNow = Now.AddDays(1);
        fixture.Barrier.Callback = () =>
        {
            new NoteRepository(fixture.Database).Insert(Note());
            return commit;
        };
        Assert.Equal(expected, fixture.Service.CheckAndAdvance().Status);
        Assert.Equal(0L, fixture.Query("SELECT count(*) FROM notes;"));
        Assert.Equal(0L, fixture.Query("SELECT count(*) FROM snapshots;"));
        Assert.Equal("2026-11-15", fixture.Query("SELECT active_day FROM checkpoint;"));
        Assert.Equal(commit == CommitResult.Failed ? 1 : 0, fixture.Log.Warnings.Count);
        fixture.Barrier.Callback = () => CommitResult.Committed;
        Assert.Equal(RolloverStatus.Sealed, fixture.Service.CheckAndAdvance().Status);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void FailureRollsBackEditsMembersArchivePendingAndCheckpoint(bool atCheckpoint)
    {
        using var fixture = new Fixture();
        fixture.Service.CheckAndAdvance();
        var repository = new NoteRepository(fixture.Database);
        var note = Note();
        repository.Insert(note);
        repository.Insert(Item(note.Id, completed: true));
        var deleted = Item(note.Id, 1);
        repository.Insert(deleted);
        repository.SoftDelete(deleted.Id, Now, HistoryDay.Parse("2026-11-15"));
        fixture.Database.Transaction(c => Execute(c, atCheckpoint
            ? "CREATE TRIGGER fail_rollover BEFORE UPDATE ON checkpoint BEGIN SELECT RAISE(ABORT,'injected'); END;"
            : "CREATE TRIGGER fail_rollover BEFORE INSERT ON snapshots BEGIN SELECT RAISE(ABORT,'injected'); END;"));
        fixture.Barrier.Callback = () =>
        {
            fixture.Database.Transaction(c => Execute(c, "UPDATE notes SET title='edited';"));
            return CommitResult.Committed;
        };
        fixture.Clock.UtcNow = Now.AddDays(1);
        Assert.Equal(RolloverStatus.Failed, fixture.Service.CheckAndAdvance().Status);
        Assert.Equal(note.Title, Assert.Single(repository.GetNotes()).Title);
        Assert.Equal(0L, fixture.Query("SELECT count(*) FROM snapshot_items;"));
        Assert.Equal(0L, fixture.Query("SELECT count(*) FROM snapshot_notes;"));
        Assert.Equal(0L, fixture.Query("SELECT count(*) FROM items WHERE archived_day IS NOT NULL;"));
        Assert.Equal(1L, fixture.Query("SELECT count(*) FROM pending_deleted_items;"));
        Assert.Equal("2026-11-15", fixture.Query("SELECT active_day FROM checkpoint;"));
        Assert.Single(fixture.Log.Errors);
        fixture.Database.Transaction(c => Execute(c, "DROP TRIGGER fail_rollover;"));
        Assert.Equal(RolloverStatus.Sealed, fixture.Service.CheckAndAdvance().Status);
        Assert.Equal("edited", fixture.Query("SELECT title FROM snapshot_notes;"));
    }

    [Fact]
    public void ExistingSnapshotIsNeverChangedOrSupplemented()
    {
        using var fixture = new Fixture();
        SealSnapshot(fixture.Database);
        fixture.Clock.UtcNow = Now.AddDays(-1);
        fixture.Service.CheckAndAdvance();
        new NoteRepository(fixture.Database).Insert(Note(10));
        fixture.Clock.UtcNow = Now;
        Assert.Equal(RolloverStatus.Sealed, fixture.Service.CheckAndAdvance().Status);
        Assert.Equal(1L, fixture.Query("SELECT count(*) FROM snapshot_notes;"));
        Assert.Equal(1000L, fixture.Query("SELECT sealed_at FROM snapshots;"));
        Assert.Equal("2026-11-15", fixture.Query("SELECT high_water FROM checkpoint;"));
    }

    [Fact]
    public void PendingDeletionFromAnotherDayIsNotIncludedOrCleared()
    {
        using var fixture = new Fixture();
        fixture.Service.CheckAndAdvance();
        var repository = new NoteRepository(fixture.Database);
        var note = Note(); repository.Insert(note);
        repository.Insert(Item(note.Id));
        fixture.Clock.UtcNow = Now.AddDays(1);
        var deletionDay = new BusinessDayCalculator().GetDay(fixture.Clock.UtcNow, fixture.Clock.TimeZone);
        repository.SoftDelete(note.Id, fixture.Clock.UtcNow, deletionDay);
        fixture.Clock.UtcNow = Now.AddDays(1);
        fixture.Service.CheckAndAdvance();
        Assert.Equal(0L, fixture.Query("SELECT count(*) FROM snapshot_notes;"));
        Assert.Equal(1L, fixture.Query("SELECT count(*) FROM pending_deleted_notes;"));
        Assert.Equal(1L, fixture.Query("SELECT count(*) FROM pending_deleted_items;"));
        fixture.Clock.UtcNow = Now.AddDays(2);
        fixture.Service.CheckAndAdvance();
        Assert.Equal(1L, fixture.Query("SELECT count(*) FROM snapshot_notes WHERE day='2026-11-16' AND deleted=1;"));
        Assert.Equal(0L, fixture.Query("SELECT count(*) FROM pending_deleted_notes;"));
    }

    [Fact]
    public void MultiDayAdvanceIncludesOlderPendingAndDiscardsUnobservedDays()
    {
        using var fixture = new Fixture();
        fixture.Service.CheckAndAdvance();
        var repository = new NoteRepository(fixture.Database);
        foreach (string day in new[] { "2026-11-14", "2026-11-16", "2026-11-17" })
        {
            var note = Note();
            repository.Insert(note);
            repository.Insert(Item(note.Id));
            repository.SoftDelete(note.Id, Now, HistoryDay.Parse(day));
        }
        fixture.Clock.UtcNow = Now.AddDays(2);
        Assert.Equal(RolloverStatus.Sealed, fixture.Service.CheckAndAdvance().Status);
        Assert.Equal(1L, fixture.Query("SELECT count(*) FROM snapshots;"));
        Assert.Equal("2026-11-15", fixture.Query("SELECT day FROM snapshots;"));
        Assert.Equal(1L, fixture.Query("SELECT count(*) FROM snapshot_notes WHERE deleted=1;"));
        Assert.Equal(1L, fixture.Query("SELECT count(*) FROM snapshot_items WHERE deleted=1;"));
        Assert.Equal("2026-11-17", fixture.Query("SELECT day FROM pending_deleted_notes;"));
        Assert.Equal("2026-11-17", fixture.Query("SELECT day FROM pending_deleted_items;"));
        Assert.Equal(1L, fixture.Query("SELECT count(*) FROM pending_deleted_notes;"));
        Assert.Equal(1L, fixture.Query("SELECT count(*) FROM pending_deleted_items;"));
        fixture.Clock.UtcNow = Now.AddDays(3);
        Assert.Equal(RolloverStatus.Sealed, fixture.Service.CheckAndAdvance().Status);
        Assert.Equal(0L, fixture.Query("SELECT count(*) FROM pending_deleted_notes;"));
        Assert.Equal(0L, fixture.Query("SELECT count(*) FROM pending_deleted_items;"));
        Assert.Equal(2L, fixture.Query("SELECT count(*) FROM snapshot_items;"));
    }

    internal sealed class Fixture : IDisposable
    {
        public TestDirectory Directory { get; } = new();
        public DeskNodesDatabase Database { get; }
        public FakeClock Clock { get; } = new();
        public Barrier Barrier { get; } = new();
        public MemoryLog Log { get; } = new();
        public AutomaticBackupService Backup { get; }
        public DayRolloverService Service { get; }
        public Fixture()
        {
            Database = Directory.Open();
            Backup = new(Database, Directory.DirectoryPath, Log);
            Service = new(Database, Clock, Barrier, Backup, Log);
        }
        public object? Query(string sql) => Database.Read(c => Scalar(c, sql));
        public void Dispose() { Database.Dispose(); Directory.Dispose(); }
    }

    internal sealed class FakeClock : IClock
    {
        public DateTimeOffset UtcNow { get; set; } = Now;
        public TimeZoneInfo TimeZone { get; set; } = TimeZoneInfo.Utc;
    }
    internal sealed class Barrier : ICommitBarrier
    {
        public Func<CommitResult> Callback { get; set; } = () => CommitResult.Committed;
        public CommitResult TryCommitPending() => Callback();
    }
    internal sealed class MemoryLog : IDeskNodesLog
    {
        public List<string> Warnings { get; } = [];
        public List<Exception> Errors { get; } = [];
        public void Info(string message) { }
        public void Warn(string message) => Warnings.Add(message);
        public void Error(string message, Exception exception) => Errors.Add(exception);
    }
}
