using DeskNodes.Core.Domain;
using DeskNodes.Core.Services;
using DeskNodes.Core.Storage;
using static DeskNodes.Core.Tests.TestData;

namespace DeskNodes.Core.Tests;

public sealed class DeletionActionsTests
{
    [Fact]
    public void FailedBatchRollsBackRowsAndDoesNotPublishUndoEntry()
    {
        using var dir = new TestDirectory(); using var db = dir.Open();
        var repo = new NoteRepository(db);
        var first = Note(0); var second = Note(1);
        repo.Insert(first); repo.Insert(second); repo.Insert(Item(first.Id));
        db.Transaction(c => Execute(c, """
            CREATE TRIGGER reject_second BEFORE UPDATE ON notes
            WHEN OLD.sort_order=1 AND NEW.deleted_at IS NOT NULL
            BEGIN SELECT RAISE(ABORT,'test write failure'); END;
            """));
        var queue = new DeletionUndoQueue(db, new ActionClock());
        Assert.Throws<Microsoft.Data.Sqlite.SqliteException>(() => queue.DeleteNotes([first.Id, second.Id]));
        Assert.Equal(2, repo.GetNotes().Count);
        Assert.Null(Assert.Single(repo.GetItems(first.Id)).DeletedAt);
        Assert.Equal(0, queue.PromptCount(Now));
        Assert.Equal(0L, db.Read(c => Scalar(c, "SELECT count(*) FROM note_deletion_items;")));
        Assert.Equal(0L, db.Read(c => Scalar(c, "SELECT count(*) FROM pending_deleted_items;")));
    }

    [Theory]
    [InlineData(-.001, false)]
    [InlineData(0, true)]
    [InlineData(4.999, true)]
    [InlineData(5, false)]
    public void UndoHasStrictTimeWindow(double seconds, bool valid)
    {
        using var dir = new TestDirectory();
        using var db = dir.Open();
        var clock = new ActionClock();
        var repo = new NoteRepository(db);
        var note = Note(); repo.Insert(note);
        var queue = new DeletionUndoQueue(db, clock);
        queue.DeleteNote(note.Id);
        var at = Now.AddMilliseconds(Math.Round(seconds * 1000));
        Assert.Equal(valid, queue.HasUndoableDeletion(at));
        Assert.Equal(valid ? 1 : 0, queue.PromptCount(at));
        Assert.Equal(valid ? UndoDecision.StructuralUndo : UndoDecision.TextUndo, queue.DecideUndo(at, false));
        Assert.Equal(UndoDecision.TextUndo, queue.DecideUndo(at, true));
        if (valid) Assert.Equal(TimeSpan.FromMilliseconds(5000 - Math.Round(seconds * 1000)), Assert.Single(queue.Hints(at)).Remaining);
        Assert.Equal(valid, queue.Undo(at));
        Assert.Equal(valid ? 1 : 0, repo.GetNotes().Count);
    }

    [Fact]
    public void BatchCountsOnceShrinksOnRestoreAndUndoKeepsOriginalState()
    {
        using var dir = new TestDirectory();
        using var db = dir.Open();
        var clock = new ActionClock();
        var repo = new NoteRepository(db);
        var a = Note(); var b = Note(1); repo.Insert(a); repo.Insert(b);
        var item = Item(b.Id, 7, completed: true); repo.Insert(item);
        var queue = new DeletionUndoQueue(db, clock);
        var deleted = new RecentlyDeleted(db, clock, queue);
        Assert.True(queue.DeleteNotes([a.Id, b.Id, a.Id]));
        Assert.Equal(1, queue.PromptCount(Now));
        Assert.Equal(2, Assert.Single(queue.Hints(Now)).MemberCount);
        Assert.Equal(2, deleted.Count());
        Assert.Equal(RestoreResult.Restored, deleted.Restore(a.Id));
        Assert.Equal(1, Assert.Single(queue.Hints(Now)).MemberCount);
        Assert.True(queue.Undo(Now.AddSeconds(1)));
        Assert.Equal(b, repo.GetNotes().First(n => n.Id == b.Id));
        Assert.Equal(item, Assert.Single(repo.GetItems(b.Id)));
        Assert.False(queue.HasUndoableDeletion(Now));
        queue.DeleteNotes([a.Id, b.Id]);
        Assert.True(queue.Undo(Now));
        Assert.Equal(2, repo.GetNotes().Count);
        queue.DeleteNote(a.Id);
        queue.Clear();
        Assert.False(queue.Undo(Now));
    }

    [Fact]
    public void UndoIsNewestFirstAndSingleRestoreAppendsAndRemovesToast()
    {
        using var dir = new TestDirectory();
        using var db = dir.Open();
        var clock = new ActionClock();
        var repo = new NoteRepository(db);
        var note = Note(); repo.Insert(note);
        var a = Item(note.Id, 0, struck: true); var b = Item(note.Id, 8); repo.Insert(a); repo.Insert(b);
        var queue = new DeletionUndoQueue(db, clock);
        queue.DeleteItem(a.Id);
        clock.UtcNow = Now.AddSeconds(1);
        queue.DeleteItem(b.Id);
        Assert.Equal(2, queue.PromptCount(clock.UtcNow));
        Assert.True(queue.Undo(clock.UtcNow));
        Assert.Equal(b, Assert.Single(repo.GetItems(note.Id)));
        Assert.Equal(RestoreResult.Restored, new RecentlyDeleted(db, clock, queue).Restore(a.Id));
        var restored = repo.GetItems(note.Id)[1];
        Assert.Equal(a.Id, restored.Id); Assert.Equal(9, restored.SortOrder); Assert.True(restored.Struck);
        Assert.Equal(0, queue.PromptCount(clock.UtcNow));
    }

    [Theory]
    [InlineData(-.001, false)]
    [InlineData(0, true)]
    [InlineData(30 * 86400, true)]
    [InlineData(30 * 86400 + .001, false)]
    public void RecentlyDeletedThirtyDaysIsOnlyAListBoundary(double elapsed, bool listed)
    {
        using var dir = new TestDirectory();
        using var db = dir.Open();
        var clock = new ActionClock();
        var repo = new NoteRepository(db);
        var note = Note(); repo.Insert(note);
        var queue = new DeletionUndoQueue(db, clock); queue.DeleteNote(note.Id);
        clock.UtcNow = Now.AddSeconds(elapsed);
        var deleted = new RecentlyDeleted(db, clock, queue);
        Assert.Equal(listed ? 1 : 0, deleted.Count());
        Assert.Equal(deleted.Count(), deleted.List().Count);
        Assert.Equal(RestoreResult.Restored, deleted.Restore(note.Id));
    }

    [Fact]
    public void WholeRestoreExcludesEarlierIndividualDeletionEvenAtSameTimestampAndPreviewsFour()
    {
        using var dir = new TestDirectory();
        using var db = dir.Open();
        var clock = new ActionClock();
        var repo = new NoteRepository(db);
        var note = Note(); repo.Insert(note);
        var earlier = Item(note.Id); repo.Insert(earlier);
        var actions = new NoteActions(db, clock);
        var ids = actions.InsertFollowing(note.Id, earlier.Id, ["a", "b", "c", "d", "e", "\u3000"]);
        var queue = new DeletionUndoQueue(db, clock);
        queue.DeleteItem(earlier.Id);
        queue.DeleteNote(note.Id);
        var deleted = new RecentlyDeleted(db, clock, queue);
        Assert.Equal(2, deleted.Count());
        var whole = deleted.List().First(e => e.Member.NoteId is not null);
        Assert.Equal(new[] { "a", "b", "c", "d" }, whole.Preview);
        Assert.Equal(1, whole.RemainingCount);
        var single = deleted.List().First(e => e.Member.ItemId is not null);
        Assert.Equal(note.Title, single.Title); Assert.Equal(note.Color, single.Color);
        Assert.Equal(RestoreResult.ParentDeleted, deleted.Restore(earlier.Id));
        Assert.Equal(RestoreResult.Restored, deleted.Restore(note.Id));
        Assert.DoesNotContain(repo.GetItems(note.Id), i => i.Id == earlier.Id);
        Assert.Equal(ids, repo.GetItems(note.Id).Select(i => i.Id));
        Assert.Equal(1, queue.PromptCount(Now));
        Assert.Equal(RestoreResult.Restored, deleted.Restore(earlier.Id));
        Assert.Equal(0, queue.PromptCount(Now));
    }

    [Fact]
    public void ArchivedAndBlankIndividualItemsAreNotListedOrReactivated()
    {
        using var dir = new TestDirectory();
        using var db = dir.Open();
        var clock = new ActionClock();
        var repo = new NoteRepository(db);
        var note = Note(); repo.Insert(note);
        var archived = Item(note.Id, archivedDay: HistoryDay.Parse("2026-11-14")); repo.Insert(archived);
        var actions = new NoteActions(db, clock);
        var created = actions.CreateNote(note.Placement, true);
        actions.EditText(created.FirstItemId, "\u3000\u00a0\t");
        var queue = new DeletionUndoQueue(db, clock);
        queue.DeleteItem(created.FirstItemId);
        repo.SoftDelete(archived.Id, Now, new BusinessDayContext(db, clock).Current);
        var deleted = new RecentlyDeleted(db, clock, queue);
        Assert.Equal(0, deleted.Count()); Assert.Empty(deleted.List());
        Assert.Equal(RestoreResult.Archived, deleted.Restore(archived.Id));
        Assert.Equal(RestoreResult.NotFoundOrNotDeleted, deleted.Restore(ItemId.New()));
    }

    [Fact]
    public void UndoDropsTheBlankThatReplacedTheLastItemUnlessItWasEdited()
    {
        using var dir = new TestDirectory();
        using var db = dir.Open();
        var clock = new ActionClock();
        var repo = new NoteRepository(db);
        var actions = new NoteActions(db, clock);
        var queue = new DeletionUndoQueue(db, clock);
        var created = actions.CreateNote(new Placement(new RectD(0, 0, 200, 160), "DISPLAY1"), true);
        actions.EditText(created.FirstItemId, "只剩这一行");
        Assert.True(queue.DeleteItem(created.FirstItemId));
        Assert.Equal(0, actions.CleanupBlankItems(created.Note.Id));
        var placeholder = Assert.Single(repo.GetItems(created.Note.Id));
        queue.AssociateBlankPlaceholder(created.FirstItemId, placeholder.Id);
        Assert.True(queue.Undo(clock.UtcNow));
        var restored = Assert.Single(repo.GetItems(created.Note.Id));
        Assert.Equal(created.FirstItemId, restored.Id);
        Assert.Equal("只剩这一行", restored.Text);

        Assert.True(queue.DeleteItem(created.FirstItemId));
        actions.CleanupBlankItems(created.Note.Id);
        var edited = Assert.Single(repo.GetItems(created.Note.Id));
        actions.EditText(edited.Id, "替补里写下的");
        queue.AssociateBlankPlaceholder(created.FirstItemId, edited.Id);
        Assert.True(queue.Undo(clock.UtcNow));
        Assert.Equal(
            new HashSet<ItemId> { created.FirstItemId, edited.Id },
            repo.GetItems(created.Note.Id).Select(item => item.Id).ToHashSet());
    }
    [Theory]
    [InlineData("hints")]
    [InlineData("count")]
    [InlineData("available")]
    [InlineData("decision")]
    [InlineData("undo")]
    [InlineData("deleteNote")]
    [InlineData("deleteItem")]
    [InlineData("remove")]
    public void EveryQueueOperationPermanentlyPrunesExpiredEntries(string operation)
    {
        using var directory = new TestDirectory();
        using var db = directory.Open();
        var clock = new ActionClock();
        var repository = new NoteRepository(db);
        var queue = new DeletionUndoQueue(db, clock);
        var notes = Enumerable.Range(0, 100).Select(i => Note(i)).ToArray();
        foreach (var note in notes)
        {
            repository.Insert(note);
            Assert.True(queue.DeleteNote(note.Id));
        }
        Assert.Equal(100, queue.PromptCount(Now));
        clock.UtcNow = Now.AddSeconds(5);
        switch (operation)
        {
            case "hints": Assert.Empty(queue.Hints(clock.UtcNow)); break;
            case "count": Assert.Equal(0, queue.PromptCount(clock.UtcNow)); break;
            case "available": Assert.False(queue.HasUndoableDeletion(clock.UtcNow)); break;
            case "decision": Assert.Equal(UndoDecision.TextUndo, queue.DecideUndo(clock.UtcNow, true)); break;
            case "undo": Assert.False(queue.Undo(clock.UtcNow)); break;
            case "deleteNote": Assert.False(queue.DeleteNote(NoteId.New())); break;
            case "deleteItem": Assert.False(queue.DeleteItem(ItemId.New())); break;
            case "remove": queue.RemoveMember(new(notes[0].Id, null)); break;
        }
        clock.UtcNow = Now.AddSeconds(1);
        Assert.Empty(queue.Hints(clock.UtcNow));
        Assert.False(queue.Undo(clock.UtcNow));
        Assert.Empty(repository.GetNotes());
        Assert.Equal(100, repository.GetNotes(true).Count);
    }

    [Fact]
    public void PruningKeepsNewerBatchMembersAndNewestFirstUndo()
    {
        using var directory = new TestDirectory();
        using var db = directory.Open();
        var clock = new ActionClock();
        var repository = new NoteRepository(db);
        var notes = Enumerable.Range(0, 4).Select(i => Note(i)).ToArray();
        foreach (var note in notes)
            repository.Insert(note);
        var queue = new DeletionUndoQueue(db, clock);
        queue.DeleteNote(notes[0].Id);
        clock.UtcNow = Now.AddSeconds(3);
        queue.DeleteNotes([notes[1].Id, notes[2].Id]);
        clock.UtcNow = Now.AddSeconds(4);
        queue.DeleteNote(notes[3].Id);
        clock.UtcNow = Now.AddSeconds(5);
        queue.RemoveMember(new(notes[1].Id, null));
        Assert.Equal(2, queue.PromptCount(clock.UtcNow));
        Assert.All(queue.Hints(clock.UtcNow), hint => Assert.Equal(1, hint.MemberCount));
        Assert.True(queue.Undo(clock.UtcNow));
        Assert.Equal(notes[3], Assert.Single(repository.GetNotes()));
        Assert.True(queue.Undo(clock.UtcNow));
        Assert.Equal(new[] { notes[2].Id, notes[3].Id }, repository.GetNotes().Select(n => n.Id));
        clock.UtcNow = Now;
        Assert.False(queue.Undo(clock.UtcNow));
    }

}
