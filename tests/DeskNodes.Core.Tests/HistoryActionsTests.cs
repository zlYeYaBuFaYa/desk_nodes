using DeskNodes.Core.Domain;
using DeskNodes.Core.Services;
using DeskNodes.Core.Storage;
using static DeskNodes.Core.Tests.TestData;

namespace DeskNodes.Core.Tests;

public sealed class HistoryActionsTests
{
    private static HistoryDay Day(string value) => HistoryDay.Parse(value);

    private static void Freeze(DeskNodesDatabase db, string day, string? carriedTo = null)
        => db.Transaction(c =>
        {
            ServiceInsert(c, "INSERT INTO snapshot_notes SELECT $day,n.*,n.deleted_at IS NOT NULL FROM notes n;", day);
            ServiceInsert(c, "INSERT INTO snapshot_items SELECT $day,i.*,i.deleted_at IS NOT NULL,$carry FROM items i;", day, carriedTo);
            ServiceInsert(c, "INSERT INTO snapshots VALUES($day,1000);", day);
        });

    private static void ServiceInsert(Microsoft.Data.Sqlite.SqliteConnection c, string sql, string day, string? carry = null)
    {
        using var command = c.CreateCommand();
        command.CommandText = sql;
        command.Parameters.AddWithValue("$day", day);
        command.Parameters.AddWithValue("$carry", carry ?? (object)DBNull.Value);
        command.ExecuteNonQuery();
    }

    [Fact]
    public void RecentDaysAreSealedNonconsecutiveDescendingAndLimited()
    {
        using var dir = new TestDirectory(); using var db = dir.Open();
        var history = new HistoryQueries(db);
        Assert.Empty(history.RecentSealedDays());
        var dates = new[] { "2025-12-31", "2026-01-02", "2026-02-03", "2026-04-05", "2026-06-07", "2026-08-09", "2026-10-11", "2026-11-13", "2026-11-14" };
        foreach (var day in dates) Freeze(db, day);
        Assert.Equal(dates.Reverse().Take(7), history.RecentSealedDays().Select(d => d.Day.ToString()));
        Assert.All(history.RecentSealedDays(), d => Assert.Null(d.Progress.Rate));
        Assert.Empty(history.RecentSealedDays(0));
        Assert.Throws<ArgumentOutOfRangeException>(() => history.RecentSealedDays(-1));
    }

    [Fact]
    public void FrozenDeletedMembersCountStruckDoNotAndMonthAggregatesOccurrences()
    {
        using var dir = new TestDirectory(); using var db = dir.Open();
        var clock = new ActionClock(); var repo = new NoteRepository(db);
        var note = Note(); repo.Insert(note);
        var completed = Item(note.Id, completed: true); repo.Insert(completed);
        var struck = Item(note.Id, 1, struck: true); repo.Insert(struck);
        repo.SoftDelete(completed.Id, Now, Day("2026-11-15"));
        Freeze(db, "2026-11-01");
        var pending = Item(note.Id, 2); repo.Insert(pending);
        repo.Insert(Item(note.Id, 3)); repo.Insert(Item(note.Id, 4));
        Freeze(db, "2026-11-03", "2026-11-15");
        Freeze(db, "2026-10-31");
        var history = new HistoryQueries(db);
        var month = history.MonthStats(2026, 11);
        Assert.Equal(new Progress(2, 5), month.Progress);
        Assert.Equal(.4, month.Progress.Rate);
        Assert.Equal(new Progress(1, 1), month.Days[0].Progress);
        Assert.Equal(new Progress(1, 4), month.Days[1].Progress);
        var snapshot = history.DaySnapshot(Day("2026-11-03"));
        Assert.True(snapshot.HasSnapshot);
        var frozen = Assert.Single(snapshot.Notes);
        Assert.True(frozen.Items.First(i => i.Item.Id == completed.Id).Deleted);
        Assert.True(frozen.Items.First(i => i.Item.Id == struck.Id).Item.Struck);
        Assert.Equal(Day("2026-11-15"), frozen.Items.First(i => i.Item.Id == pending.Id).CarriedTo);
        var actions = new NoteActions(db, clock); actions.EditText(pending.Id, "实时改变");
        new RecentlyDeleted(db, clock, new(db, clock)).Restore(completed.Id);
        Assert.Equal(pending.Text, Assert.Single(history.DaySnapshot(Day("2026-11-03")).Notes).Items.First(i => i.Item.Id == pending.Id).Item.Text);
        Assert.Equal(new Progress(2, 5), history.MonthStats(2026, 11).Progress);
        Assert.False(history.DaySnapshot(Day("2026-11-15")).HasSnapshot);
        Assert.Empty(history.DaySnapshot(Day("2026-11-15")).Notes);
        Assert.Null(history.MonthStats(2027, 1).Progress.Rate);
    }

    [Theory]
    [InlineData(false, null, CalendarShade.None)]
    [InlineData(true, null, CalendarShade.Weak)]
    [InlineData(true, 0d, CalendarShade.Weak)]
    [InlineData(true, .001, CalendarShade.Low)]
    [InlineData(true, .49999, CalendarShade.Low)]
    [InlineData(true, .5, CalendarShade.Mid)]
    [InlineData(true, .99999, CalendarShade.Mid)]
    [InlineData(true, 1d, CalendarShade.Full)]
    public void CalendarShadesFollowExactThresholds(bool snapshot, double? rate, CalendarShade expected)
    {
        Assert.Equal(expected, HistoryQueries.Shade(snapshot, rate));
        double opacity = HistoryQueries.ShadeOpacity(expected);
        Assert.Equal(expected switch { CalendarShade.Low => .18, CalendarShade.Mid => .38, CalendarShade.Full => .62, _ => 0 }, opacity);
    }

    [Theory]
    [InlineData("2026-11-15", "今天")]
    [InlineData("2026-11-14", "昨天")]
    [InlineData("2026-11-13", "周五")]
    [InlineData("2026-11-09", "周一")]
    [InlineData("2026-11-08", "11月8日")]
    [InlineData("2025-11-15", "2025年11月15日")]
    [InlineData("2026-11-16", "11月16日")]
    public void RelativeLabelsUseBusinessDay(string day, string expected)
        => Assert.Equal(expected, HistoryQueries.RelativeLabel(Day(day), Day("2026-11-15")));

    [Fact]
    public void CalendarNavigationCrossesMonthsClampsDaysButAllowsFutureMonthsAndSelection()
    {
        var navigator = new CalendarNavigator(Day("2026-10-31"), Day("2026-11-15"));
        navigator.MoveDay(1); Assert.Equal(Day("2026-11-01"), navigator.SelectedDay);
        navigator.MoveWeek(-1); Assert.Equal(Day("2026-10-25"), navigator.SelectedDay);
        navigator.MoveMonth(1); Assert.Equal(Day("2026-11-01"), navigator.SelectedDay);
        var grid = navigator.MonthGrid();
        Assert.Equal(42, grid.Count); Assert.Equal(Day("2026-10-26"), grid[0]);
        Assert.All(Enumerable.Range(0, 6), row => Assert.Equal(DayOfWeek.Monday, grid[row * 7]!.Value.Value.DayOfWeek));
        navigator.Today(); Assert.True(navigator.IsTodayDisabled);
        navigator.MoveDay(1); Assert.True(navigator.IsTodayDisabled);
        navigator.MoveWeek(1); Assert.True(navigator.IsTodayDisabled);
        navigator.MoveMonth(1); Assert.Equal(Day("2026-12-01"), navigator.SelectedDay);
        navigator.MoveDay(-1); Assert.Equal(Day("2026-11-15"), navigator.SelectedDay);
        navigator.Select(Day("2026-11-30")); Assert.False(navigator.IsTodayDisabled);
        navigator.ReloadToday(Day("2026-12-01")); navigator.Today(); Assert.True(navigator.IsTodayDisabled);
        navigator.Select(Day("2021-02-01")); Assert.Equal(28, navigator.MonthGrid(false).Count);
        navigator.Select(new(DateOnly.MinValue)); navigator.MoveDay(-1); navigator.MoveMonth(-1);
        Assert.Equal(DateOnly.MinValue, navigator.SelectedDay.Value);
        Assert.Throws<ArgumentOutOfRangeException>(() => navigator.MoveWeek(0));
    }

    [Fact]
    public void BusinessDayContextReadsCurrentSettingsAndClockTimeZone()
    {
        using var dir = new TestDirectory(); using var db = dir.Open();
        var clock = new ActionClock { UtcNow = new DateTimeOffset(2026, 11, 15, 2, 0, 0, TimeSpan.Zero) };
        var context = new BusinessDayContext(db, clock);
        Assert.Equal(Day("2026-11-14"), context.Current);
        db.Transaction(c => Execute(c, "UPDATE business_settings SET rollover_minutes=0;"));
        Assert.Equal(Day("2026-11-15"), context.Current);
        clock.TimeZone = TimeZoneInfo.CreateCustomTimeZone("test", TimeSpan.FromHours(-8), "test", "test");
        Assert.Equal(Day("2026-11-14"), context.Current);
    }
    [Fact]
    public void SnapshotGroupsInterleavedItemsByParentIncludingEmptyDeletedAndArchivedGroups()
    {
        using var directory = new TestDirectory();
        using var db = directory.Open();
        var repo = new NoteRepository(db);
        var empty = Note(0);
        var active = Note(1);
        var deleted = Note(2);
        repo.Insert(empty);
        repo.Insert(active);
        repo.Insert(deleted);
        var activeLate = Item(active.Id, 8);
        var activeEarly = Item(active.Id, 1, completed: true, archivedDay: Day("2026-11-13"));
        var deletedEarly = Item(deleted.Id, 0);
        var deletedLate = Item(deleted.Id, 7);
        foreach (var item in new[] { activeLate, deletedEarly, activeEarly, deletedLate })
            repo.Insert(item);
        repo.SoftDelete(deleted.Id, Now, Day("2026-11-15"));
        Freeze(db, "2026-11-14");
        var notes = new HistoryQueries(db).DaySnapshot(Day("2026-11-14")).Notes;
        Assert.Equal(new[] { empty.Id, active.Id, deleted.Id }, notes.Select(n => n.Note.Id));
        Assert.Empty(notes[0].Items);
        Assert.Equal(new[] { activeEarly.Id, activeLate.Id }, notes[1].Items.Select(i => i.Item.Id));
        Assert.Equal(activeEarly.ArchivedDay, notes[1].Items[0].Item.ArchivedDay);
        Assert.Equal(new[] { deletedEarly.Id, deletedLate.Id }, notes[2].Items.Select(i => i.Item.Id));
        Assert.True(notes[2].Deleted);
        Assert.All(notes[2].Items, item => Assert.True(item.Deleted));
    }

}
