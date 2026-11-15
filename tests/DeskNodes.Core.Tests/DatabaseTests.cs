using DeskNodes.Core.Domain;
using DeskNodes.Core.Storage;
using Microsoft.Data.Sqlite;
using static DeskNodes.Core.Tests.TestData;

namespace DeskNodes.Core.Tests;

public sealed class DatabaseTests
{
    [Fact]
    public void OpenAppliesDurabilityPragmasAndInitializesAnEmptyBusinessStore()
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        database.Read(connection =>
        {
            Assert.Equal(1L, Scalar(connection, "PRAGMA foreign_keys;"));
            Assert.Equal("wal", Scalar(connection, "PRAGMA journal_mode;"));
            Assert.Equal(2L, Scalar(connection, "PRAGMA synchronous;"));
            Assert.Equal(5000L, Scalar(connection, "PRAGMA busy_timeout;"));
            Assert.Equal((long)DeskNodesDatabase.ApplicationId, Scalar(connection, "PRAGMA application_id;"));
            Assert.Equal(1L, Scalar(connection, "PRAGMA user_version;"));
            foreach (string table in new[] { "notes", "items", "checkpoint", "snapshots", "snapshot_notes",
                "snapshot_items", "pending_deleted_notes", "pending_deleted_items" })
                Assert.Equal(0L, Scalar(connection, $"SELECT count(*) FROM {table};"));
            Assert.Equal(240L, Scalar(connection, "SELECT rollover_minutes FROM business_settings;"));
            Assert.Equal("ok", Scalar(connection, "PRAGMA integrity_check;"));
            Assert.Null(Scalar(connection, "PRAGMA foreign_key_check;"));
            return 0;
        });
    }

    [Fact]
    public void ReopenPreservesDataAndDoesNotRepeatInitialization()
    {
        using var directory = new TestDirectory();
        var note = Note();
        using (var database = directory.Open())
        {
            new NoteRepository(database).Insert(note);
            database.Transaction(connection => Execute(connection, "UPDATE business_settings SET rollover_minutes=0;"));
        }
        using var reopened = directory.Open();
        Assert.Equal(note, Assert.Single(new NoteRepository(reopened).GetNotes()));
        Assert.Equal(0L, reopened.Read(connection => Scalar(connection, "SELECT rollover_minutes FROM business_settings;")));
    }

    [Theory]
    [InlineData(DeskNodesDatabase.ApplicationId, 2, DatabaseCompatibilityFailure.FutureVersion)]
    [InlineData(123, 1, DatabaseCompatibilityFailure.ForeignDatabase)]
    [InlineData(0, 0, DatabaseCompatibilityFailure.ForeignDatabase)]
    [InlineData(DeskNodesDatabase.ApplicationId, 0, DatabaseCompatibilityFailure.UnsupportedSchema)]
    public void IncompatibleDatabaseIsRejectedWithoutChangingItsIdentityOrContent(int appId, int version,
        DatabaseCompatibilityFailure expected)
    {
        using var directory = new TestDirectory();
        using (var connection = new SqliteConnection($"Data Source={directory.DatabasePath};Pooling=False"))
        {
            connection.Open();
            Execute(connection, $"CREATE TABLE sentinel(value TEXT); INSERT INTO sentinel VALUES('keep'); " +
                $"PRAGMA application_id={appId}; PRAGMA user_version={version};");
        }
        byte[] before = File.ReadAllBytes(directory.DatabasePath);
        var exception = Assert.Throws<DatabaseCompatibilityException>(() => directory.Open());
        Assert.Equal(expected, exception.Failure);
        Assert.NotEmpty(exception.Message);
        Assert.Equal(before, File.ReadAllBytes(directory.DatabasePath));
    }

    [Fact]
    public void CorruptFileIsNotReplacedWithAnEmptyDatabase()
    {
        using var directory = new TestDirectory();
        byte[] bytes = "This is not a SQLite database"u8.ToArray();
        File.WriteAllBytes(directory.DatabasePath, bytes);
        Assert.Throws<SqliteException>(() => directory.Open());
        Assert.Equal(bytes, File.ReadAllBytes(directory.DatabasePath));
    }

    [Fact]
    public void OuterFailureRollsBackSuccessfulNestedWrites()
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        var repository = new NoteRepository(database);
        Assert.Throws<InvalidOperationException>(() => database.Transaction(_ =>
        {
            repository.Insert(Note());
            database.Transaction(connection => Execute(connection, "UPDATE business_settings SET rollover_minutes=1;"));
            throw new InvalidOperationException("fail outer");
        }));
        Assert.Empty(repository.GetNotes());
        Assert.Equal(240L, database.Read(connection => Scalar(connection, "SELECT rollover_minutes FROM business_settings;")));
        repository.Insert(Note());
        Assert.Single(repository.GetNotes());
    }

    [Fact]
    public void CaughtNestedFailureRollsBackOnlyItsSavepoint()
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        var repository = new NoteRepository(database);
        var first = Note(0);
        var last = Note(2);
        database.Transaction(_ =>
        {
            repository.Insert(first);
            Assert.Throws<InvalidOperationException>(() => database.Transaction(_ =>
            {
                repository.Insert(Note(1));
                throw new InvalidOperationException("fail inner");
            }));
            repository.Insert(last);
        });
        Assert.Equal(new[] { first, last }, repository.GetNotes());
    }

    [Fact]
    public void OuterTransactionAcquiresWriteReservationImmediately()
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        using var other = new SqliteConnection($"Data Source={directory.DatabasePath};Pooling=False;Default Timeout=1");
        other.Open();
        database.Transaction(_ =>
        {
            var exception = Assert.Throws<SqliteException>(() => Execute(other, "BEGIN IMMEDIATE;"));
            Assert.Equal(5, exception.SqliteErrorCode); // SQLITE_BUSY, even before the first write.
        });
        Execute(other, "BEGIN IMMEDIATE; ROLLBACK;");
    }

    [Theory]
    [InlineData("UPDATE snapshots SET sealed_at=2000;")]
    [InlineData("DELETE FROM snapshots;")]
    [InlineData("UPDATE snapshot_notes SET title='changed';")]
    [InlineData("DELETE FROM snapshot_notes;")]
    [InlineData("UPDATE snapshot_items SET text='changed';")]
    [InlineData("DELETE FROM snapshot_items;")]
    [InlineData("INSERT OR REPLACE INTO snapshots VALUES('2026-11-14',2000);")]
    [InlineData("INSERT OR REPLACE INTO snapshot_notes SELECT * FROM snapshot_notes;")]
    [InlineData("INSERT OR REPLACE INTO snapshot_items SELECT * FROM snapshot_items;")]
    public void FrozenSnapshotsRejectMutationAndReplacement(string sql)
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        SealSnapshot(database);
        var exception = Assert.Throws<SqliteException>(() => database.Transaction(connection => Execute(connection, sql)));
        Assert.Equal(19, exception.SqliteErrorCode);
        Assert.Equal(1000L, database.Read(connection => Scalar(connection, "SELECT sealed_at FROM snapshots;")));
        Assert.Equal(1L, database.Read(connection => Scalar(connection, "SELECT count(*) FROM snapshot_notes;")));
        Assert.Equal(1L, database.Read(connection => Scalar(connection, "SELECT count(*) FROM snapshot_items;")));
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void SealedSnapshotRejectsNewMembers(bool insertNote)
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        SealSnapshot(database);
        var repository = new NoteRepository(database);
        var note = Note();
        repository.Insert(note);
        repository.Insert(Item(note.Id));
        string sql = insertNote
            ? $"INSERT INTO snapshot_notes SELECT '2026-11-14', n.*, 0 FROM notes n WHERE id='{note.Id}';"
            : $"INSERT INTO snapshot_items SELECT '2026-11-14', i.*, 0, NULL FROM items i WHERE note_id='{note.Id}';";
        var exception = Assert.Throws<SqliteException>(() => database.Transaction(connection => Execute(connection, sql)));
        Assert.Contains("already sealed", exception.Message);
    }

    [Fact]
    public void DeferredForeignKeyRequiresHeaderAtCommitAndRollbackKeepsConnectionUsable()
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        new NoteRepository(database).Insert(Note());
        var exception = Assert.Throws<SqliteException>(() => database.Transaction(connection =>
            Execute(connection, "INSERT INTO snapshot_notes SELECT '2026-11-14', n.*, 0 FROM notes n;")));
        Assert.Equal(19, exception.SqliteErrorCode);
        Assert.Equal(0L, database.Read(connection => Scalar(connection, "SELECT count(*) FROM snapshot_notes;")));
        database.Transaction(connection => Execute(connection, "UPDATE business_settings SET rollover_minutes=1439;"));
    }

    [Fact]
    public void SnapshotItemRequiresFrozenNoteEvenWhenTheDayHeaderExistsAtCommit()
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        var repository = new NoteRepository(database);
        var note = Note();
        repository.Insert(note);
        repository.Insert(Item(note.Id));
        var exception = Assert.Throws<SqliteException>(() => database.Transaction(connection =>
        {
            Execute(connection, "INSERT INTO snapshot_items SELECT '2026-11-14', i.*, 0, '2026-11-15' FROM items i;");
            Execute(connection, "INSERT INTO snapshots VALUES('2026-11-14',1000);");
        }));
        Assert.Equal(19, exception.SqliteErrorCode);
        Assert.Equal(0L, database.Read(connection => Scalar(connection, "SELECT count(*) FROM snapshots;")));
        Assert.Equal(0L, database.Read(connection => Scalar(connection, "SELECT count(*) FROM snapshot_items;")));
    }

    [Fact]
    public void SnapshotPreservesDeletionAndCarriedToFields()
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        var repository = new NoteRepository(database);
        var note = Note();
        repository.Insert(note);
        repository.Insert(Item(note.Id));
        repository.SoftDelete(note.Id, Now, HistoryDay.Parse("2026-11-15"));
        database.Transaction(connection =>
        {
            Execute(connection, "INSERT INTO snapshot_notes SELECT '2026-11-14', n.*, 1 FROM notes n;");
            Execute(connection, "INSERT INTO snapshot_items SELECT '2026-11-14', i.*, 1, '2026-11-15' FROM items i;");
            Execute(connection, "INSERT INTO snapshots VALUES('2026-11-14',1000);");
        });
        Assert.Equal(1L, database.Read(connection => Scalar(connection, "SELECT deleted FROM snapshot_notes;")));
        Assert.Equal(1L, database.Read(connection => Scalar(connection, "SELECT deleted FROM snapshot_items;")));
        Assert.Equal("2026-11-15", database.Read(connection => Scalar(connection, "SELECT carried_to FROM snapshot_items;")));
        Assert.Null(database.Read(connection => Scalar(connection, "PRAGMA foreign_key_check;")));
    }

    [Theory]
    [InlineData("2026-02-30")]
    [InlineData("2026-1-01")]
    [InlineData("0000-01-01")]
    [InlineData("garbage")]
    public void SchemaRejectsInvalidBusinessDays(string day)
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        Assert.Throws<SqliteException>(() => database.Transaction(connection =>
            Execute(connection, $"INSERT INTO snapshots VALUES('{day}',0);")));
    }

    [Fact]
    public void CheckpointIsSingletonAndSettingsValidateMinuteBounds()
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        database.Transaction(connection => Execute(connection,
            "INSERT INTO checkpoint VALUES(1,'2026-11-15','2026-11-15'); UPDATE business_settings SET rollover_minutes=0;"));
        Assert.Throws<SqliteException>(() => database.Transaction(connection => Execute(connection,
            "INSERT INTO checkpoint VALUES(2,'2026-11-15','2026-11-15');")));
        Assert.Throws<SqliteException>(() => database.Transaction(connection => Execute(connection,
            "UPDATE business_settings SET rollover_minutes=1440;")));
        Assert.Throws<SqliteException>(() => database.Transaction(connection => Execute(connection,
            "UPDATE business_settings SET rollover_minutes=-1;")));
    }
}
