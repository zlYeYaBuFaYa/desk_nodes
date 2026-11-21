using DeskNodes.Core.Services;
using DeskNodes.Core.Storage;

namespace DeskNodes.Core.Tests;

public sealed class EditorSessionTests
{
    private sealed class Scheduler
    {
        private long now;
        private readonly List<(long Due, Action Callback)> pending = [];
        public void Schedule(TimeSpan delay, Action callback) => pending.Add((now + (long)delay.TotalMilliseconds, callback));
        public void Advance(int milliseconds)
        {
            now += milliseconds;
            foreach (var entry in pending.Where(p => p.Due <= now).ToArray())
            {
                pending.Remove(entry);
                entry.Callback();
            }
        }
    }
    private sealed class Log : IDeskNodesLog
    {
        public void Info(string message) { }
        public void Warn(string message) { }
        public void Error(string message, Exception exception) { }
    }
    [Fact]
    public void DebounceCommitsLatestRevisionOnlyAfter400Milliseconds()
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        var time = new Scheduler();
        var session = new EditorSession(new Log(), database);
        var saved = new List<string>();
        var owner = session.Register("item", "old", saved.Add, time.Schedule);
        session.Change(owner, "first");
        time.Advance(399);
        Assert.Empty(saved);
        session.Change(owner, "latest");
        time.Advance(1);
        Assert.Empty(saved);
        time.Advance(399);
        Assert.Equal(new[] { "latest" }, saved);
        Assert.False(owner.Dirty);
    }
    [Fact]
    public void CompositionSuppressesWritesAndEndRestartsDebounce()
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        var time = new Scheduler();
        var session = new EditorSession(new Log(), database);
        var saved = new List<string>();
        var owner = session.Register("item", "old", saved.Add, time.Schedule);
        session.Change(owner, "中");
        session.SetComposition(owner, true);
        time.Advance(1000);
        Assert.Equal(CommitResult.Composing, session.TryCommitPending());
        Assert.Empty(saved);
        session.Change(owner, "中文");
        session.SetComposition(owner, false);
        time.Advance(1000);
        Assert.Empty(saved);
        session.Reschedule(owner);
        time.Advance(399);
        Assert.Empty(saved);
        time.Advance(1);
        Assert.Equal(new[] { "中文" }, saved);
    }
    [Fact]
    public void RefreshPreservesActiveAndDirtyText()
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        var session = new EditorSession(new Log(), database);
        var owner = session.Register("item", "old", _ => { }, (_, _) => { });
        Assert.False(session.Refresh(owner, "remote", true));
        Assert.Equal("old", owner.Text);
        session.Change(owner, "dirty");
        Assert.False(session.Refresh(owner, "remote", false));
        Assert.Equal("dirty", owner.Text);
        session.TryCommitPending();
        Assert.True(session.Refresh(owner, "remote", false));
        Assert.Equal("remote", owner.Committed);
    }
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void InvalidatedTimersAndDeferredCompositionCannotWriteSameId(bool all)
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        var time = new Scheduler();
        var session = new EditorSession(new Log(), database);
        var saved = new List<string>();
        var old = session.Register("same", "old", saved.Add, time.Schedule);
        session.Change(old, "stale");
        if (all)
            session.InvalidateAll();
        else
            session.Remove(old);
        var replacement = session.Register("same", "fresh", saved.Add, time.Schedule);
        session.Change(replacement, "new edit");
        session.SetComposition(old, false);
        time.Advance(400);
        Assert.Equal(new[] { "new edit" }, saved);
        Assert.Equal("old", old.Committed);
        Assert.Equal("new edit", replacement.Committed);
    }
    [Fact]
    public void OlderTransactionConfirmationCannotClearNewerRevision()
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        var time = new Scheduler();
        var session = new EditorSession(new Log(), database);
        var saved = new List<string>();
        var owner = session.Register("item", "old", saved.Add, time.Schedule);
        database.Transaction(_ =>
        {
            session.Change(owner, "first");
            session.TryCommitPending();
            session.Change(owner, "second");
        });
        Assert.True(owner.Dirty);
        Assert.Equal("old", owner.Committed);
        time.Advance(400);
        Assert.Equal(new[] { "first", "second" }, saved);
        Assert.False(owner.Dirty);
    }
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void RemovedOwnersCannotSaveOrAcknowledgeReplacement(bool all)
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        var time = new Scheduler();
        var session = new EditorSession(new Log(), database);
        var saved = new List<string>();
        var old = session.Register("same", "old", saved.Add, time.Schedule);
        session.Change(old, "stale");
        EditorSession.Owner? replacement = null;
        database.Transaction(_ =>
        {
            session.TryCommitPending();
            if (all)
                session.InvalidateAll();
            else
                session.Remove(old);
            replacement = session.Register("same", "new", saved.Add, time.Schedule);
            session.SetComposition(old, false);
            session.Change(old, "late event");
        });
        time.Advance(1000);
        Assert.Equal(new[] { "stale" }, saved);
        Assert.Equal("old", old.Committed);
        Assert.Equal("new", replacement!.Committed);
        Assert.False(replacement.Dirty);
    }
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void FailureKeepsDirtyAndSchedulesRetry(bool outerRollback)
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        var time = new Scheduler();
        var session = new EditorSession(new Log(), database);
        bool fail = !outerRollback;
        string persisted = "old";
        var owner = session.Register("item", "old", text =>
        {
            if (fail)
                throw new IOException("save");
            database.Transaction(c => TestData.Execute(c, "CREATE TABLE IF NOT EXISTS saved(text TEXT); DELETE FROM saved; INSERT INTO saved VALUES ('new');"));
            persisted = text;
        }, time.Schedule);
        session.Change(owner, "new");
        if (outerRollback)
            Assert.Throws<IOException>(() => database.Transaction(_ =>
            {
                Assert.Equal(CommitResult.Committed, session.TryCommitPending());
                throw new IOException("outer");
            }));
        else
            time.Advance(400);
        Assert.True(owner.Dirty);
        Assert.Equal("old", owner.Committed);
        Assert.Equal(CommitResult.Failed, session.Status);
        fail = false;
        time.Advance(399);
        Assert.True(owner.Dirty);
        time.Advance(1);
        Assert.False(owner.Dirty);
        Assert.Equal("new", persisted);
        Assert.Equal("new", database.Read(c => TestData.Scalar(c, "SELECT text FROM saved")));
    }
}
