using DeskNodes.Core.Services;
using DeskNodes.Core.Domain;
using DeskNodes.Core.Backup;
using DeskNodes.Core.Storage;

namespace DeskNodes.Core.Tests;

public sealed class ImportServiceTests
{
    private sealed class Clock : IClock
    {
        public DateTimeOffset UtcNow => TestData.Now;
        public TimeZoneInfo TimeZone => TimeZoneInfo.Utc;
    }
    private sealed class Hotkeys(List<string> calls, string fault) : IHotkeyRegistrationService
    {
        private readonly List<string> events = calls;
        private readonly string failure = fault;
        public string Binding = "old";
        public bool Released;
        public Action? Prepared;
        public IHotkeyCandidate Prepare(HotkeyAction action, string? text)
        {
            events.Add("prepare:" + action);
            if (failure == "conflict" || (failure == "raise" && action == HotkeyAction.Raise))
                throw new InvalidOperationException("conflict");
            Prepared?.Invoke();
            return new Candidate(this, action, text);
        }
        public void MarkConflict(HotkeyAction action, string text) => events.Add("conflict:" + action);
        private sealed class Candidate(Hotkeys owner, HotkeyAction action, string? text) : IHotkeyCandidate
        {
            public void Commit()
            {
                owner.events.Add("commit:" + action);
                if (owner.failure == "commit")
                    throw new IOException("commit");
                if (action == HotkeyAction.NewNote)
                    owner.Binding = text!;
            }
            public void Dispose() => owner.Released = true;
        }
    }
    [Theory]
    [InlineData("success")]
    [InlineData("raise")]
    [InlineData("conflict")]
    [InlineData("replace")]
    [InlineData("commit")]
    [InlineData("cancel")]
    [InlineData("undo")]
    [InlineData("invalidate")]
    [InlineData("publish")]
    [InlineData("cancelAfterPrepare")]
    public void ImportPreservesStateOnFailureAndPublishesInOrder(string fault)
    {
        using var directory = new TestDirectory();
        using var live = directory.Open();
        using var staging = DeskNodesDatabase.Open(Path.Combine(directory.DirectoryPath, "stage.sqlite3"));
        var oldNote = TestData.Note();
        var newNote = TestData.Note();
        new NoteRepository(live).Insert(oldNote);
        new NoteRepository(staging).Insert(newNote);
        var incoming = new BusinessPreferences { HotkeyNew = "Ctrl+Alt+Q", HotkeyFloat = "Ctrl+Alt+W" };
        new BusinessPreferencesStore(staging).Save(incoming);
        var clock = new Clock();
        var undoQueue = new DeletionUndoQueue(live, clock);
        var deleted = TestData.Item(oldNote.Id);
        new NoteRepository(live).Insert(deleted);
        Assert.True(undoQueue.DeleteItem(deleted.Id));
        string before = WindowsBackupCodec.Serialize(WindowsBackupCodec.Export(live, clock));
        string expected = WindowsBackupCodec.Serialize(WindowsBackupCodec.Export(staging, clock));
        var calls = new List<string>();
        var hotkeys = new Hotkeys(calls, fault);
        if (fault == "replace")
            hotkeys.Prepared = staging.Dispose;
        using var cancellation = new CancellationTokenSource();
        if (fault == "cancel")
            cancellation.Cancel();
        if (fault == "cancelAfterPrepare")
            hotkeys.Prepared = cancellation.Cancel;
        bool replaced = false;
        bool undo = true;
        bool context = true;
        bool published = false;
        bool conflict = false;
        var service = new ImportService(live, hotkeys, () =>
        {
            Assert.NotNull(new NoteRepository(live).GetNote(newNote.Id));
            Assert.Equal(incoming.HotkeyNew, hotkeys.Binding);
            if (fault == "undo")
                throw new IOException("undo");
            calls.Add("undo");
            undoQueue.Clear();
            undo = false;
        }, () =>
        {
            if (fault == "invalidate")
                throw new IOException("invalidate");
            calls.Add("invalidate");
            context = false;
        });
        void Apply() => service.Apply(staging, () =>
        {
            Assert.NotNull(new NoteRepository(live).GetNote(newNote.Id));
            Assert.Equal("old", hotkeys.Binding);
            replaced = true;
            calls.Add("replaced");
        }, preferences =>
        {
            Assert.Equal(incoming.HotkeyNew, preferences.HotkeyNew);
            if (fault == "publish")
                throw new IOException("publish");
            calls.Add("publish");
            published = true;
        }, _ => conflict = true, cancellation.Token);
        if (fault == "replace")
            Assert.Throws<ObjectDisposedException>(() => Apply());
        else if (fault == "conflict")
            Assert.Throws<InvalidOperationException>(() => Apply());
        else if (fault is "commit" or "undo" or "invalidate" or "publish")
            Assert.Throws<IOException>(() => Apply());
        else if (fault is "cancel" or "cancelAfterPrepare")
            Assert.Throws<OperationCanceledException>(() => Apply());
        else
            Apply();
        bool success = fault is "success" or "raise";
        bool dataReplaced = success || fault is "commit" or "undo" or "invalidate" or "publish";
        bool undoCleared = success || fault is "invalidate" or "publish";
        bool invalidated = success || fault == "publish";
        Assert.Equal(dataReplaced, replaced);
        Assert.Equal(dataReplaced ? expected : before, WindowsBackupCodec.Serialize(WindowsBackupCodec.Export(live, clock)));
        Assert.Equal(!undoCleared, undoQueue.HasUndoableDeletion(clock.UtcNow));
        Assert.Equal(!undoCleared, undo);
        Assert.Equal(!invalidated, context);
        Assert.Equal(success, published);
        Assert.Equal(fault == "raise", conflict);
        Assert.NotNull(new NoteRepository(live).GetNote(dataReplaced ? newNote.Id : oldNote.Id));
        Assert.Null(new NoteRepository(live).GetNote(dataReplaced ? oldNote.Id : newNote.Id));
        Assert.Equal(dataReplaced && fault != "commit" ? incoming.HotkeyNew : "old", hotkeys.Binding);
        if (success)
        {
            Assert.Equal(new[] { "prepare:NewNote", "replaced", "commit:NewNote", "undo", "invalidate", "publish", "prepare:Raise", fault == "raise" ? "conflict:Raise" : "commit:Raise" }, calls);
        }
        if (fault is "replace" or "commit" or "cancelAfterPrepare")
            Assert.True(hotkeys.Released);
        if (fault == "cancel")
            Assert.Empty(calls);
    }
}
