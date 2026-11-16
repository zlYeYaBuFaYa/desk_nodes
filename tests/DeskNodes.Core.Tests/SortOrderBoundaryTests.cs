using DeskNodes.Core.Backup;
using DeskNodes.Core.Domain;
using DeskNodes.Core.Services;
using DeskNodes.Core.Storage;
using Microsoft.Data.Sqlite;
using static DeskNodes.Core.Tests.TestData;

namespace DeskNodes.Core.Tests;

public sealed class SortOrderBoundaryTests
{
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void CreateAtExhaustedOrderStablyRenumbersIncludingTombstonesAndRoundTrips(bool tombstone)
    {
        using var directory = new TestDirectory();
        using var db = directory.Open();
        var repo = new NoteRepository(db);
        var first = Note(17);
        var tied = Note(17);
        var last = Note(long.MaxValue);
        repo.Insert(first);
        repo.Insert(last);
        repo.Insert(tied);
        if (tombstone)
            repo.SoftDelete(last.Id, Now, HistoryDay.Parse("2026-11-15"));
        var before = repo.GetNotes(true);
        var created = new NoteActions(db, new ActionClock()).CreateNote(first.Placement, true);
        var after = repo.GetNotes(true);
        Assert.Equal(before.Select(n => n.Id).Append(created.Note.Id), after.Select(n => n.Id));
        Assert.Equal(new long[] { 0, 1, 2, 3 }, after.Select(n => n.SortOrder));
        Assert.Equal(3, created.Note.SortOrder);
        Assert.Equal(tombstone, repo.GetNote(last.Id, true)!.DeletedAt is not null);
        using var stage = WindowsBackupCodec.Stage(WindowsBackupCodec.Export(db, new ActionClock()),
            Path.Combine(directory.DirectoryPath, "roundtrip.sqlite3"));
        Assert.Equal(after, new NoteRepository(stage).GetNotes(true));
    }

    [Theory]
    [InlineData("renumber")]
    [InlineData("append")]
    public void NoteRenumberAndAppendFailuresRollBackEntireCreation(string failure)
    {
        using var directory = new TestDirectory();
        using var db = directory.Open();
        var repo = new NoteRepository(db);
        var first = Note(10);
        var last = Note(long.MaxValue);
        repo.Insert(first);
        repo.Insert(last);
        string trigger = failure == "renumber"
            ? "CREATE TRIGGER reject_order BEFORE UPDATE OF sort_order ON notes WHEN OLD.sort_order=9223372036854775807 BEGIN SELECT RAISE(ABORT,'failure'); END;"
            : "CREATE TRIGGER reject_item BEFORE INSERT ON items BEGIN SELECT RAISE(ABORT,'failure'); END;";
        db.Transaction(c => Execute(c, trigger));
        Assert.Throws<SqliteException>(() => new NoteActions(db, new ActionClock()).CreateNote(first.Placement, true));
        Assert.Equal(new[] { first, last }, repo.GetNotes(true));
        Assert.Empty(repo.GetItems(first.Id, true, true));
        Assert.Empty(repo.GetItems(last.Id, true, true));
    }

    [Fact]
    public void RestoringAtExhaustedItemOrderStablyRenumbersOnlyActiveSiblingsAndRoundTrips()
    {
        using var directory = new TestDirectory();
        using var db = directory.Open();
        var repo = new NoteRepository(db);
        var note = Note();
        var other = Note(1);
        repo.Insert(note);
        repo.Insert(other);
        var a = Item(note.Id, 9);
        var b = Item(note.Id, 9);
        var last = Item(note.Id, long.MaxValue);
        var restore = Item(note.Id, 0);
        var tombstone = Item(note.Id, long.MaxValue);
        var archived = Item(note.Id, long.MaxValue, completed: true, archivedDay: HistoryDay.Parse("2026-11-14"));
        var unrelated = Item(other.Id, long.MaxValue);
        foreach (var item in new[] { a, b, last, restore, tombstone, archived, unrelated })
            repo.Insert(item);
        repo.SoftDelete(restore.Id, Now, HistoryDay.Parse("2026-11-15"));
        repo.SoftDelete(tombstone.Id, Now, HistoryDay.Parse("2026-11-15"));
        var before = repo.GetItems(note.Id);
        Assert.True(repo.Restore(restore.Id, Now.AddSeconds(1)));
        var after = repo.GetItems(note.Id);
        Assert.Equal(before.Select(i => i.Id).Append(restore.Id), after.Select(i => i.Id));
        Assert.Equal(new long[] { 0, 1, 2, 3 }, after.Select(i => i.SortOrder));
        Assert.Equal(long.MaxValue, repo.GetItem(tombstone.Id, true, true)!.SortOrder);
        Assert.Equal(archived, repo.GetItem(archived.Id, true, true));
        Assert.Equal(unrelated, repo.GetItem(unrelated.Id));
        Assert.Equal(0L, db.Read(c => Scalar(c, "SELECT count(*) FROM items WHERE typeof(sort_order)!='integer';")));
        using var stage = WindowsBackupCodec.Stage(WindowsBackupCodec.Export(db, new ActionClock()),
            Path.Combine(directory.DirectoryPath, "roundtrip.sqlite3"));
        Assert.Equal(after, new NoteRepository(stage).GetItems(note.Id));
    }

    [Theory]
    [InlineData("renumber")]
    [InlineData("restore")]
    public void ItemOrderFailureRollsBackRenumberAndDeletionMembership(string failure)
    {
        using var directory = new TestDirectory();
        using var db = directory.Open();
        var repo = new NoteRepository(db);
        var note = Note();
        repo.Insert(note);
        var first = Item(note.Id, 10);
        var last = Item(note.Id, long.MaxValue);
        var restore = Item(note.Id);
        repo.Insert(first);
        repo.Insert(last);
        repo.Insert(restore);
        repo.SoftDelete(restore.Id, Now, HistoryDay.Parse("2026-11-15"));
        var before = repo.GetItems(note.Id, true, true);
        string condition = failure == "renumber" ? "OLD.sort_order=9223372036854775807" : "OLD.deleted_at IS NOT NULL";
        db.Transaction(c => Execute(c, $"CREATE TRIGGER reject_order BEFORE UPDATE ON items WHEN {condition} BEGIN SELECT RAISE(ABORT,'failure'); END;"));
        Assert.Throws<SqliteException>(() => repo.Restore(restore.Id, Now.AddSeconds(1)));
        Assert.Equal(before, repo.GetItems(note.Id, true, true));
        Assert.Equal(1L, db.Read(c => Scalar(c, "SELECT count(*) FROM pending_deleted_items;")));
    }
}
