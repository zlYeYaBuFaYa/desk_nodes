using DeskNodes.Core.Domain;
using DeskNodes.Core.Storage;
using Microsoft.Data.Sqlite;
using static DeskNodes.Core.Tests.TestData;

namespace DeskNodes.Core.Tests;

public sealed class RepositoryTests
{
    [Fact]
    public void CrudRoundTripsEveryFieldAndSortsNotesAndItems()
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        var repository = new NoteRepository(database);
        var early = Note(-5, NoteColor.Mint);
        var later = new Note(NoteId.New(), "", NoteColor.Lavender, 100,
            new Placement(new RectD(-400, -80, 300, 500), "DISPLAY2", DockEdge.Right, 3),
            NoteLevel.Topmost, new RectD(10, -20, 220, 330), false, true, Now, Now.AddMinutes(1));
        repository.Insert(later);
        repository.Insert(early);
        var item = Item(early.Id, 5, struck: true);
        var firstItem = Item(early.Id, -2, completed: true);
        repository.Insert(item);
        repository.Insert(firstItem);
        Assert.Equal(new[] { early, later }, repository.GetNotes());
        Assert.Equal(new[] { firstItem, item }, repository.GetItems(early.Id));

        var updatedNote = new Note(early.Id, "更新", NoteColor.Cherry, 200,
            new Placement(new RectD(0, 0, 340, 300), "DISPLAY3", DockEdge.Top, 0), NoteLevel.Normal,
            new RectD(1, 2, 240, 400), false, true, Now, Now.AddSeconds(1));
        var updatedItem = new NoteItem(item.Id, early.Id, "更新事项", true, false, 8, null, Now, Now.AddSeconds(2));
        repository.Update(updatedNote);
        repository.Update(updatedItem);
        Assert.Equal(new[] { later, updatedNote }, repository.GetNotes());
        Assert.Equal(updatedItem, repository.GetItems(early.Id)[1]);

        Assert.Throws<SqliteException>(() => repository.Insert(updatedNote));
        Assert.Equal(2, repository.GetNotes().Count);
        Assert.Throws<KeyNotFoundException>(() => repository.Update(Note()));
        Assert.Throws<KeyNotFoundException>(() => repository.Update(Item(early.Id)));
    }

    [Fact]
    public void ItemSoftDeleteAndRestoreKeepIdentityAndAppendToLiveItems()
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        var repository = new NoteRepository(database);
        var note = Note();
        repository.Insert(note);
        var item = Item(note.Id);
        var remaining = Item(note.Id, 8);
        repository.Insert(item);
        repository.Insert(remaining);
        Assert.True(repository.SoftDelete(item.Id, Now.AddMinutes(1)));
        Assert.False(repository.SoftDelete(item.Id, Now.AddMinutes(2)));
        Assert.Equal(remaining, Assert.Single(repository.GetItems(note.Id)));
        NoteItem tombstone = repository.GetItems(note.Id, includeDeleted: true)[0];
        Assert.Equal(Now.AddMinutes(1), tombstone.DeletedAt);
        Assert.Equal(1L, database.Read(connection => Scalar(connection, "SELECT count(*) FROM pending_deleted_items;")));
        Assert.True(repository.Restore(item.Id, Now.AddMinutes(3)));
        Assert.False(repository.Restore(item.Id, Now.AddMinutes(4)));
        NoteItem restored = repository.GetItems(note.Id)[1];
        Assert.Equal(item.Id, restored.Id);
        Assert.Equal(item.Text, restored.Text);
        Assert.Equal(9, restored.SortOrder);
        Assert.Equal(item.CreatedAt, restored.CreatedAt);
        Assert.Equal(Now.AddMinutes(3), restored.UpdatedAt);
        Assert.Null(restored.DeletedAt);
        Assert.Equal(0L, database.Read(connection => Scalar(connection, "SELECT count(*) FROM pending_deleted_items;")));
    }

    [Fact]
    public void WholeNoteRestoreExcludesEarlierDeletedAndArchivedChildren()
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        var repository = new NoteRepository(database);
        var note = Note();
        repository.Insert(note);
        var live = Item(note.Id);
        var earlier = Item(note.Id, 1);
        var archived = Item(note.Id, 2, completed: true, archivedDay: HistoryDay.Parse("2026-11-14"));
        repository.Insert(live);
        repository.Insert(earlier);
        repository.Insert(archived);
        repository.SoftDelete(earlier.Id, Now.AddSeconds(1));
        Assert.True(repository.SoftDelete(note.Id, Now.AddSeconds(2)));
        Assert.False(repository.SoftDelete(note.Id, Now.AddSeconds(3)));
        Assert.Empty(repository.GetNotes());
        Assert.Empty(repository.GetItems(note.Id));
        Assert.Equal(note.Id, Assert.Single(repository.GetNotes(includeDeleted: true)).Id);
        Assert.False(repository.Restore(live.Id, Now.AddSeconds(3)));
        Assert.True(repository.Restore(note.Id, Now.AddSeconds(4)));
        Assert.False(repository.Restore(note.Id, Now.AddSeconds(5)));
        Assert.Equal(note.Id, Assert.Single(repository.GetNotes()).Id);
        NoteItem restored = Assert.Single(repository.GetItems(note.Id));
        Assert.Equal(live.Id, restored.Id);
        Assert.Null(restored.DeletedAt);
        Assert.Equal(Now.AddSeconds(4), restored.UpdatedAt);
        var all = repository.GetItems(note.Id, includeDeleted: true, includeArchived: true);
        Assert.Equal(Now.AddSeconds(1), all[1].DeletedAt);
        Assert.Equal(archived, all[2]);
        Assert.Equal(0L, database.Read(connection => Scalar(connection, "SELECT count(*) FROM pending_deleted_notes;")));
        Assert.Equal(1L, database.Read(connection => Scalar(connection, "SELECT count(*) FROM pending_deleted_items;")));
    }

    [Fact]
    public void ArchivedItemsAreNotReactivatedAndMissingIdsDoNotChangeState()
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        var repository = new NoteRepository(database);
        var note = Note();
        repository.Insert(note);
        var archived = Item(note.Id, archivedDay: HistoryDay.Parse("2026-11-14"));
        repository.Insert(archived);
        Assert.Empty(repository.GetItems(note.Id));
        Assert.Equal(archived, Assert.Single(repository.GetItems(note.Id, includeArchived: true)));
        Assert.True(repository.SoftDelete(archived.Id, Now));
        Assert.False(repository.Restore(archived.Id, Now.AddMinutes(1)));
        Assert.False(repository.SoftDelete(NoteId.New(), Now));
        Assert.False(repository.SoftDelete(ItemId.New(), Now));
        Assert.False(repository.Restore(NoteId.New(), Now));
        Assert.False(repository.Restore(ItemId.New(), Now));
    }

    [Fact]
    public void DatabaseEnforcesForeignKeysAndExclusiveItemStates()
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        var repository = new NoteRepository(database);
        Assert.Throws<SqliteException>(() => repository.Insert(Item(NoteId.New())));
        var note = Note();
        repository.Insert(note);
        var item = Item(note.Id);
        repository.Insert(item);
        Assert.Throws<SqliteException>(() => database.Transaction(connection =>
            Execute(connection, "UPDATE items SET completed=1, struck=1;")));
        Assert.Equal(item, Assert.Single(repository.GetItems(note.Id)));
        Assert.Throws<SqliteException>(() => database.Transaction(connection => Execute(connection, "DELETE FROM notes;")));
        Assert.Single(repository.GetNotes());
    }

    [Fact]
    public void TimesAreStoredAsUnixMillisecondsAndReadAsUtcInstants()
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        var repository = new NoteRepository(database);
        DateTimeOffset local = Now.ToOffset(TimeSpan.FromHours(8));
        var note = new Note(NoteId.New(), "", NoteColor.Paper, 0,
            new Placement(new RectD(0, 0, 288, 240), ""), NoteLevel.Back, null, false, false,
            local, local, local);
        repository.Insert(note);
        Assert.Equal(Now.ToUnixTimeMilliseconds(), database.Read(connection => Scalar(connection, "SELECT created_at FROM notes;")));
        var result = Assert.Single(repository.GetNotes(includeDeleted: true));
        Assert.Equal(TimeSpan.Zero, result.CreatedAt.Offset);
        Assert.Equal(Now, result.CreatedAt);
        Assert.Equal(Now, result.DeletedAt);
    }

    [Fact]
    public void RestoringLiveTombstonesDoesNotModifyFrozenHistory()
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        SealSnapshot(database);
        var repository = new NoteRepository(database);
        var note = Assert.Single(repository.GetNotes());
        repository.SoftDelete(note.Id, Now);
        repository.Restore(note.Id, Now.AddMinutes(1));
        Assert.Equal(1L, database.Read(connection => Scalar(connection, "SELECT completed FROM snapshot_items;")));
        Assert.Equal(0L, database.Read(connection => Scalar(connection, "SELECT deleted FROM snapshot_items;")));
        Assert.Equal(1000L, database.Read(connection => Scalar(connection, "SELECT sealed_at FROM snapshots;")));
    }
}
