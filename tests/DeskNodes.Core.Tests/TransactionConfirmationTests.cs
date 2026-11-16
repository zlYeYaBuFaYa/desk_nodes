using DeskNodes.Core.Presentation;
using DeskNodes.Core.Services;
using DeskNodes.Core.Storage;
using Microsoft.Data.Sqlite;
using static DeskNodes.Core.Tests.TestData;

namespace DeskNodes.Core.Tests;

public sealed class TransactionConfirmationTests
{
    [Theory]
    [InlineData("owner")]
    [InlineData("snapshot")]
    [InlineData("checkpoint")]
    [InlineData("commit")]
    public void FailedRolloverKeepsBothBuffersDirtyAndRetrySealsNewText(string fault)
    {
        using var fixture = new RolloverTests.Fixture();
        var database = fixture.Database;
        var repository = new NoteRepository(database);
        var note = Note();
        repository.Insert(note);
        var first = Item(note.Id);
        var second = Item(note.Id, 1);
        repository.Insert(first);
        repository.Insert(second);
        fixture.Service.CheckAndAdvance();
        bool injected = true;
        string[] committed = [first.Text, second.Text];
        string[] text = ["新的第一项", "新的第二项"];
        int retries = 0;
        var tracker = new PendingCommitTracker(database);
        fixture.Barrier.Callback = () =>
        {
            bool success = true;
            for (int i = 0; i < 2; i++)
            {
                int index = i;
                if (committed[i] == text[i])
                    continue;
                try
                {
                    tracker.Save(() =>
                    {
                        if (injected && fault == "owner" && index == 1)
                            throw new IOException("second owner");
                        database.Transaction(c =>
                        {
                            using var command = c.CreateCommand();
                            command.CommandText = "UPDATE items SET text=$text WHERE id=$id";
                            command.Parameters.AddWithValue("$text", text[index]);
                            command.Parameters.AddWithValue("$id", (index == 0 ? first.Id : second.Id).ToString());
                            command.ExecuteNonQuery();
                        });
                    }, () => committed[index] = text[index], () => retries++);
                }
                catch (IOException) { success = false; }
            }
            return success ? CommitResult.Committed : CommitResult.Failed;
        };
        string? trigger = fault switch
        {
            "snapshot" => "CREATE TRIGGER injected BEFORE INSERT ON snapshots BEGIN SELECT RAISE(ABORT,'fault'); END;",
            "checkpoint" => "CREATE TRIGGER injected BEFORE UPDATE ON checkpoint BEGIN SELECT RAISE(ABORT,'fault'); END;",
            // A deferred reference fails only at the final COMMIT, after all rollover writes.
            "commit" => "CREATE TRIGGER injected AFTER UPDATE ON checkpoint BEGIN INSERT INTO snapshot_notes SELECT '2026-11-13', n.*, 0 FROM notes n; END;",
            _ => null
        };
        if (trigger is not null)
            database.Transaction(c => Execute(c, trigger));
        fixture.Clock.UtcNow = Now.AddDays(1);
        Assert.Equal(RolloverStatus.Failed, fixture.Service.CheckAndAdvance().Status);
        Assert.Equal(new[] { first.Text, second.Text }, repository.GetItems(note.Id).Select(i => i.Text));
        Assert.NotEqual(text[0], committed[0]);
        Assert.NotEqual(text[1], committed[1]);
        Assert.True(retries > 0);
        Assert.Equal(0L, fixture.Query("SELECT count(*) FROM snapshots"));
        injected = false;
        if (trigger is not null)
            database.Transaction(c => Execute(c, "DROP TRIGGER injected"));
        Assert.Equal(RolloverStatus.Sealed, fixture.Service.CheckAndAdvance().Status);
        Assert.Equal(text, committed);
        Assert.Equal(text, repository.GetItems(note.Id).Select(i => i.Text));
        Assert.Equal(text, database.Read(c =>
        {
            using var command = c.CreateCommand();
            command.CommandText = "SELECT text FROM snapshot_items ORDER BY sort_order";
            using var reader = command.ExecuteReader();
            var rows = new List<string>();
            while (reader.Read()) rows.Add(reader.GetString(0));
            return rows;
        }));
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void CombinedCommitRestoresBothStoresOnPreferenceOrFinalCommitFailure(bool commitFailure)
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        var repository = new NoteRepository(database);
        repository.Insert(Note());
        var old = new LocalPreferences { DeskCollapsed = true, Page = 2 };
        var candidate = old with { DeskCollapsed = false, Page = 0 };
        var disk = old;
        var state = new PreferencesState(old, value =>
        {
            if (!commitFailure && value == candidate)
                throw new IOException("disk full");
            disk = value;
        });
        int restores = 0;
        void Restore()
        {
            restores++;
            Save(old);
        }
        void Save(LocalPreferences value)
        {
            if (!state.TrySave(value, out var failure))
                throw failure!;
        }
        void Write() => database.Transaction(c =>
        {
            Execute(c, "UPDATE notes SET title='changed'");
            if (commitFailure)
                Execute(c, "INSERT INTO snapshot_notes SELECT '2026-11-14', n.*, 0 FROM notes n");
        });
        var coordinator = new CombinedCommitCoordinator(database);
        Assert.ThrowsAny<Exception>(() => coordinator.Commit(Write, () => Save(candidate), Restore));
        Assert.Equal(commitFailure ? 1 : 0, restores);
        Assert.Equal(old, disk);
        Assert.Equal(old, state.Value);
        Assert.NotEqual("changed", Assert.Single(repository.GetNotes()).Title);
        coordinator.Commit(() => database.Transaction(c => Execute(c, "UPDATE notes SET title='retry'")),
            () => Save(old with { Page = 1 }), () => Save(old));
        Assert.Equal(1, disk.Page);
        Assert.Equal("retry", Assert.Single(repository.GetNotes()).Title);
    }

    [Fact]
    public void CombinedPublicationFailureIsReportedAfterOuterCommitAndKeepsPreferences()
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        var repository = new NoteRepository(database);
        repository.Insert(Note());
        var old = new LocalPreferences { Page = 2 };
        var disk = old;
        var state = new PreferencesState(old, value => disk = value);
        var publication = new IOException("refresh failed");
        int restores = 0;
        var failure = Assert.Throws<AggregateException>(() => database.Transaction(connection =>
        {
            new CombinedCommitCoordinator(database).Commit(
                () => database.Transaction(c => Execute(c, "UPDATE notes SET title='committed'")),
                () => Assert.True(state.TrySave(old with { Page = 0 }, out _)),
                () => restores++,
                () =>
                {
                    Assert.Equal("committed", Assert.Single(repository.GetNotes()).Title);
                    throw publication;
                });
            Assert.Equal(0, restores);
        }));
        Assert.Same(publication, Assert.Single(failure.InnerExceptions));
        Assert.Equal("committed", Assert.Single(repository.GetNotes()).Title);
        Assert.Equal(0, state.Value.Page);
        Assert.Equal(state.Value, disk);
        Assert.Equal(0, restores);
    }

    [Fact]
    public void CombinedRestoreFailureKeepsOriginalCommitFailure()
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        new NoteRepository(database).Insert(Note());
        var restoreFailure = new IOException("restore failed");
        int restores = 0;
        var failure = Assert.Throws<AggregateException>(() => new CombinedCommitCoordinator(database).Commit(
            () => database.Transaction(c => Execute(c, "INSERT INTO snapshot_notes SELECT '2026-11-14', n.*, 0 FROM notes n")),
            () => { },
            () => { restores++; throw restoreFailure; }));
        Assert.IsType<SqliteException>(failure.InnerExceptions[0]);
        Assert.Same(restoreFailure, failure.InnerExceptions[1]);
        Assert.Equal(1, restores);
        Assert.Equal(0L, database.Read(c => Scalar(c, "SELECT count(*) FROM snapshot_notes")));
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void CaughtSavepointFailureNeverConfirmsItsWrites(bool outerFails)
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        var calls = new List<string>();
        void Run() => database.Transaction(_ =>
        {
            database.OnOuterCommitted(() => calls.Add("outer committed"));
            database.OnOuterRolledBack(() => calls.Add("outer rolled back"));
            Assert.Throws<IOException>(() => database.Transaction(_ =>
            {
                database.OnOuterCommitted(() => calls.Add("inner committed"));
                database.OnOuterRolledBack(() => calls.Add("inner rolled back"));
                throw new IOException("savepoint failure");
            }));
            Assert.Empty(calls);
            if (outerFails)
                throw new IOException("outer failure");
        });
        if (outerFails)
            Assert.Throws<IOException>(Run);
        else
            Run();
        Assert.Equal(new[] { outerFails ? "outer rolled back" : "outer committed", "inner rolled back" }, calls);
    }

    [Fact]
    public void FailedCompensationPreservesOriginalFailureAndRunsRemainingCallbacks()
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        var original = new IOException("write failed");
        var compensation = new IOException("restore failed");
        bool lastCalled = false;
        var failure = Assert.Throws<AggregateException>(() => database.Transaction(_ =>
        {
            database.OnOuterRolledBack(() => throw compensation);
            database.OnOuterRolledBack(() => lastCalled = true);
            throw original;
        }));
        Assert.Equal(new Exception[] { original, compensation }, failure.InnerExceptions);
        Assert.True(lastCalled);
        database.Transaction(c => Execute(c, "UPDATE business_settings SET rollover_minutes=1"));
        Assert.Equal(1L, database.Read(c => Scalar(c, "SELECT rollover_minutes FROM business_settings")));
    }

    [Fact]
    public void CompletionCallbacksRunInOrderOutsideLockAndCanStartAnotherTransaction()
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        var order = new List<int>();
        database.OnOuterCommitted(() => order.Add(0));
        database.OnOuterRolledBack(() => order.Add(-1));
        database.Transaction(_ =>
        {
            database.OnOuterCommitted(() =>
            {
                Assert.True(Task.Run(() => database.Read(_ => 1)).Wait(TimeSpan.FromSeconds(2)));
                database.Transaction(_ => order.Add(1));
            });
            database.Transaction(_ => database.OnOuterCommitted(() => order.Add(2)));
            Assert.Equal(new[] { 0 }, order);
        });
        Assert.Equal(new[] { 0, 1, 2 }, order);
    }
}
