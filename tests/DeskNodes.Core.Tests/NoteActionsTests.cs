using DeskNodes.Core.Domain;
using DeskNodes.Core.Services;
using DeskNodes.Core.Storage;
using static DeskNodes.Core.Tests.TestData;

namespace DeskNodes.Core.Tests;

internal sealed class ActionClock : IClock
{
    public DateTimeOffset UtcNow { get; set; } = Now;
    public TimeZoneInfo TimeZone { get; set; } = TimeZoneInfo.Utc;
}

public sealed class NoteActionsTests
{
    [Fact]
    public void CreationCyclesLeastUsedColorsIncludingDeletedLatestAndAppends()
    {
        using var dir = new TestDirectory();
        using var db = dir.Open();
        var clock = new ActionClock();
        var actions = new NoteActions(db, clock);
        var repo = new NoteRepository(db);
        var placement = Note().Placement;
        var first = actions.CreateNote(placement, false);
        Assert.Equal(NoteColor.Paper, first.Note.Color);
        Assert.Equal("今日待办", first.Note.Title);
        Assert.Equal(NoteLevel.Back, first.Note.SavedLevel);
        Assert.False(first.Note.AutomaticHeight);
        Assert.Equal(first.FirstItemId, Assert.Single(repo.GetItems(first.Note.Id)).Id);
        var all = new List<CreatedNote> { first };
        for (int i = 1; i < 7; i++)
        {
            clock.UtcNow = clock.UtcNow.AddSeconds(1);
            all.Add(actions.CreateNote(placement, true));
            Assert.Equal((NoteColor)i, all[i].Note.Color);
            Assert.Equal(i, all[i].Note.SortOrder);
        }
        repo.SoftDelete(all[3].Note.Id, clock.UtcNow, new BusinessDayContext(db, clock).Current);
        clock.UtcNow = clock.UtcNow.AddSeconds(1);
        Assert.Equal(NoteColor.Cherry, actions.CreateNote(placement, true).Note.Color);
        var queue = new DeletionUndoQueue(db, clock);
        queue.DeleteNotes(repo.GetNotes().Select(n => n.Id));
        Assert.Equal(NoteColor.Lavender, actions.CreateNote(placement, true).Note.Color);
    }

    [Fact]
    public void EditingInsertionOrderingMutualExclusionAndProgress()
    {
        using var dir = new TestDirectory();
        using var db = dir.Open();
        var actions = new NoteActions(db, new ActionClock());
        var repo = new NoteRepository(db);
        var created = actions.CreateNote(Note().Placement, true);
        actions.EditTitle(created.Note.Id, " \t");
        actions.EditText(created.FirstItemId, "首行");
        Assert.Equal("首行", actions.CollapsedSummary(created.Note.Id));
        var added = actions.InsertFollowing(created.Note.Id, created.FirstItemId, ["二", "三"]);
        Assert.Equal(new[] { "首行", "二", "三" }, repo.GetItems(created.Note.Id).Select(i => i.Text));
        actions.ToggleCompleted(added[0]);
        actions.ToggleStruck(added[0]);
        Assert.Equal(new Progress(0, 2), actions.GetProgress(created.Note.Id));
        actions.ToggleCompleted(added[0]);
        Assert.Equal(new Progress(1, 3), actions.GetProgress(created.Note.Id));
        actions.ToggleCompleted(added[0]);
        actions.ToggleStruck(added[1]);
        actions.ToggleStruck(added[1]);
        Assert.All(repo.GetItems(created.Note.Id), i => { Assert.False(i.Completed); Assert.False(i.Struck); Assert.Null(i.ArchivedDay); });
        actions.MoveItem(created.Note.Id, added[1], 0);
        Assert.Equal(new[] { "三", "首行", "二" }, repo.GetItems(created.Note.Id).Select(i => i.Text));
        Assert.Throws<ArgumentOutOfRangeException>(() => actions.MoveItem(created.Note.Id, added[0], 3));
        Assert.Throws<KeyNotFoundException>(() => actions.MoveItem(created.Note.Id, ItemId.New(), 0));
        Assert.Throws<KeyNotFoundException>(() => actions.EditText(ItemId.New(), "不存在"));
        Assert.Equal(new[] { "三", "首行", "二" }, repo.GetItems(created.Note.Id).Select(i => i.Text));
        actions.EditTitle(created.Note.Id, "标题");
        Assert.Equal("标题", actions.CollapsedSummary(created.Note.Id));
        int before = repo.GetItems(created.Note.Id).Count;
        Assert.Throws<ArgumentNullException>(() => actions.InsertFollowing(created.Note.Id, added[0], ["有效", null!]));
        Assert.Equal(before, repo.GetItems(created.Note.Id).Count);
    }

    [Fact]
    public void MultilineInsertionFailureRollsBackEarlierRowsAndOrder()
    {
        using var dir = new TestDirectory(); using var db = dir.Open();
        var actions = new NoteActions(db, new ActionClock());
        var created = actions.CreateNote(Note().Placement, true);
        var repo = new NoteRepository(db);
        var before = Assert.Single(repo.GetItems(created.Note.Id));
        db.Transaction(c => Execute(c, """
            CREATE TRIGGER reject_text BEFORE INSERT ON items WHEN NEW.text='reject'
            BEGIN SELECT RAISE(ABORT,'test write failure'); END;
            """));
        Assert.Throws<Microsoft.Data.Sqlite.SqliteException>(() =>
            actions.InsertFollowing(created.Note.Id, created.FirstItemId, ["accepted", "reject"]));
        Assert.Equal(before, Assert.Single(repo.GetItems(created.Note.Id)));
    }

    [Theory]
    [InlineData("- one\r\n* two\n• three\r· four")]
    [InlineData("1. one\n2) two\n（3）three\n(4) four")]
    [InlineData("- [ ] one\n- [x] two\n[ ]three\n[X] four")]
    public void PasteRemovesPrefixesAndSplitsAllNewlines(string text)
    {
        var result = PasteParser.Parse(text + "\n \t\n");
        Assert.False(result.KeepNativePaste);
        Assert.Equal("one", result.FirstLine);
        Assert.Equal(new[] { "two", "three", "four" }, result.FollowingLines);
    }

    [Fact]
    public void SingleLinePasteIsNativeAndEmptyMultilineDoesNotCreateItems()
    {
        Assert.True(PasteParser.Parse("- [x] native").KeepNativePaste);
        var empty = PasteParser.Parse("\n \r\n- [ ] ");
        Assert.False(empty.KeepNativePaste);
        Assert.Null(empty.FirstLine);
        Assert.Empty(empty.FollowingLines);
    }

    [Fact]
    public void DecimalLinesStayIntactWhileNumberedListsStillSplit()
    {
        var result = PasteParser.Parse("3.14\n10.5\n1. one\n2) two");
        Assert.False(result.KeepNativePaste);
        Assert.Equal("3.14", result.FirstLine);
        Assert.Equal(new[] { "10.5", "one", "two" }, result.FollowingLines);
    }

    [Fact]
    public void CleanupRetainsFirstBlankAndDoesNotTouchFrozenHistoryOrDeletedList()
    {
        using var dir = new TestDirectory();
        using var db = dir.Open();
        SealSnapshot(db);
        var clock = new ActionClock();
        var repo = new NoteRepository(db);
        var note = Assert.Single(repo.GetNotes());
        var actions = new NoteActions(db, clock);
        var original = Assert.Single(repo.GetItems(note.Id));
        actions.EditText(original.Id, " \t");
        var blank = actions.InsertAfter(note.Id, original.Id, "\u3000");
        Assert.Equal(1, actions.CleanupBlankItems(note.Id));
        Assert.Equal(original.Id, Assert.Single(repo.GetItems(note.Id)).Id);
        Assert.DoesNotContain(repo.GetItems(note.Id, true, true), i => i.Id == blank);
        actions.InsertAfter(note.Id, original.Id, "内容");
        Assert.Equal(1, actions.CleanupBlankItems(note.Id));
        Assert.Equal("内容", Assert.Single(repo.GetItems(note.Id)).Text);
        Assert.Equal(0, new RecentlyDeleted(db, clock, new(db, clock)).Count());
        Assert.Equal(0L, db.Read(c => Scalar(c, "SELECT count(*) FROM pending_deleted_items;")));
        Assert.Equal(original.Text, Assert.Single(Assert.Single(new HistoryQueries(db).DaySnapshot(HistoryDay.Parse("2026-11-14")).Notes).Items).Item.Text);
    }
}
