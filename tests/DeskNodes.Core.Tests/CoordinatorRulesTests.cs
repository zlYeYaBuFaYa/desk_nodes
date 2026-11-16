using DeskNodes.Core.Domain;
using DeskNodes.Core.Presentation;
using DeskNodes.Core.Services;
using DeskNodes.Core.Storage;

namespace DeskNodes.Core.Tests;

public sealed class CoordinatorRulesTests
{
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void FailedPreferenceSaveRetainsLastSuccessfulValueAndCanRetry(bool denied)
    {
        bool fail = false;
        var initial = new LocalPreferences();
        var state = new PreferencesState(initial, _ =>
        {
            if (fail)
                throw denied ? new UnauthorizedAccessException() : new IOException();
        });
        var saved = initial with { AutoShrink = AutoShrink.Seconds30 };
        Assert.True(state.TrySave(saved, out _));
        fail = true;
        Assert.False(state.TrySave(saved with { Orientation = ToolbarOrientation.Horizontal }, out var error));
        Assert.NotNull(error);
        Assert.Equal(saved, state.Value);
        fail = false;
        Assert.True(state.TrySave(initial, out error));
        Assert.Null(error);
        Assert.Equal(initial, state.Value);
    }

    [Fact]
    public void SameDayRestartCreatesExistingNoteWindowsBeforePresenting()
    {
        using var directory = new TestDirectory();
        using var database = DeskNodesDatabase.Open(Path.Combine(directory.DirectoryPath, "startup.sqlite3"));
        var repository = new NoteRepository(database);
        var note = TestData.Note();
        repository.Insert(note);
        var clock = new TestClock();
        var service = new DayRolloverService(database, clock, new Barrier(),
            new AutomaticBackupService(database, directory.DirectoryPath, new Log()), new Log());
        Assert.Equal(RolloverStatus.Initialized, service.CheckAndAdvance().Status);
        var windows = new HashSet<NoteId>();
        bool advanced = false;
        bool presented = false;
        StartupSequence.Run(() =>
        {
            Assert.Empty(windows);
            advanced = true;
            return service.CheckAndAdvance();
        }, () =>
        {
            Assert.True(advanced);
            windows.UnionWith(repository.GetNotes().Select(n => n.Id));
        }, result =>
        {
            Assert.Equal(RolloverStatus.NoChange, result.Status);
            Assert.Contains(note.Id, windows);
            presented = true;
        });
        Assert.True(presented);
        Assert.Empty(new HistoryQueries(database).RecentSealedDays());
    }

    [Fact]
    public void MonthCacheReusesReadsAndInvalidatesAllMonths()
    {
        int reads = 0;
        var cache = new HistoryMonthCache((year, month) =>
        {
            reads++;
            return new(year, month, new(0, 0), []);
        });
        cache.Invalidate(1);
        var first = cache.Get(2026, 11);
        Assert.Same(first, cache.Get(2026, 11));
        cache.Get(2026, 10);
        Assert.Equal(2, reads);
        cache.Invalidate(1);
        Assert.Same(first, cache.Get(2026, 11));
        cache.Invalidate(2);
        Assert.NotSame(first, cache.Get(2026, 11));
        cache.Get(2026, 10);
        Assert.Equal(4, reads);
    }

    [Fact]
    public void MonthCacheDiscardsReadFromSupersededGeneration()
    {
        HistoryMonthCache cache = null!;
        cache = new((year, month) =>
        {
            cache.Invalidate(2);
            return new(year, month, new(0, 0), []);
        });
        cache.Invalidate(1);
        Assert.Null(cache.Get(2026, 11));
    }

    [Theory]
    [InlineData(-3600)]
    [InlineData(3600)]
    public void WallClockChangesDoNotDelayIdleOrAnimation(int clockJump)
    {
        var time = new ManualTime();
        var timeline = new MonotonicTimeline(time);
        var idle = new ToolbarIdleMachine();
        idle.Update(timeline.Elapsed, new());
        time.Timestamp += 500;
        time.Utc = time.Utc.AddSeconds(clockJump);
        Assert.Equal(TimeSpan.FromMilliseconds(500), timeline.Elapsed);
        Assert.Equal(1, ToolbarRules.Spring(timeline.Elapsed.TotalSeconds));
        time.Timestamp += 14500;
        Assert.Equal(ToolbarIdleAction.StartShrinkToHome, idle.Update(timeline.Elapsed, new()).Action);
    }

    private sealed class ManualTime : TimeProvider
    {
        public long Timestamp { get; set; }
        public DateTimeOffset Utc { get; set; } = DateTimeOffset.UtcNow;
        public override long TimestampFrequency => 1000;
        public override long GetTimestamp() => Timestamp;
        public override DateTimeOffset GetUtcNow() => Utc;
    }
    private sealed class TestClock : IClock
    {
        public DateTimeOffset UtcNow => TestData.Now;
        public TimeZoneInfo TimeZone => TimeZoneInfo.Utc;
    }
    private sealed class Barrier : ICommitBarrier
    {
        public CommitResult TryCommitPending() => CommitResult.Committed;
    }
    private sealed class Log : IDeskNodesLog
    {
        public void Info(string message) { }
        public void Warn(string message) { }
        public void Error(string message, Exception exception) { }
    }
}
