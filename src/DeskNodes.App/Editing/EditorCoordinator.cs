using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using DeskNodes.Core.Services;
using TextBox = System.Windows.Controls.TextBox;

namespace DeskNodes.App.Editing;

/// <summary>Each registration owns its buffer and timer until the corresponding editor is removed.</summary>
internal sealed class EditorCoordinator(IDeskNodesLog log) : ICommitBarrier, IDisposable
{
    internal sealed class Owner
    {
        public required string Id { get; init; }
        public required TextBox Editor { get; init; }
        public required Action<string> Save { get; init; }
        public required DispatcherTimer Timer { get; init; }
        public string Committed { get; set; } = "";
        public long Revision { get; set; }
        public bool Composing { get; set; }
        public bool Updating { get; set; }
        public bool Active => Editor.IsKeyboardFocusWithin || Composing;
    }
    private readonly Dictionary<TextBox, Owner> owners = [];
    public event EventHandler? TextInput;
    public event EventHandler? SaveFailed;
    public bool HasComposition => owners.Values.Any(o => o.Composing);
    public CommitResult Status { get; private set; } = CommitResult.Committed;
    public Owner Register(TextBox editor, string id, Action<string> save)
    {
        var owner = new Owner { Id = id, Editor = editor, Save = save, Committed = editor.Text,
            Timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(.4) } };
        owners.Add(editor, owner);
        owner.Timer.Tick += (_, _) => { owner.Timer.Stop(); Commit(owner); };
        editor.TextChanged += (_, _) =>
        {
            if (owner.Updating) return;
            owner.Revision++;
            TextInput?.Invoke(this, EventArgs.Empty);
            owner.Timer.Stop(); if (!owner.Composing) owner.Timer.Start();
        };
        TextCompositionManager.AddPreviewTextInputStartHandler(editor, (_, _) => { owner.Composing = true; owner.Timer.Stop(); });
        TextCompositionManager.AddPreviewTextInputUpdateHandler(editor, (_, _) => { owner.Composing = true; owner.Timer.Stop(); });
        editor.AddHandler(TextCompositionManager.TextInputEvent, new TextCompositionEventHandler((_, _) =>
        {
            owner.Composing = false;
            editor.Dispatcher.BeginInvoke(() => { if (owners.ContainsKey(editor)) { owner.Timer.Stop(); owner.Timer.Start(); } }, DispatcherPriority.Background);
        }), true);
        editor.LostKeyboardFocus += (_, _) => { if (!owner.Composing) Commit(owner); };
        return owner;
    }
    public bool IsComposing(TextBox editor) => owners.TryGetValue(editor, out var owner) && owner.Composing;
    public void Refresh(TextBox editor, string text)
    {
        var owner = owners[editor];
        if (owner.Active || owner.Committed != editor.Text) return;
        owner.Updating = true;
        try { if (editor.Text != text) editor.Text = text; owner.Committed = text; }
        finally { owner.Updating = false; }
    }
    private bool Commit(Owner owner)
    {
        if (owner.Composing) { Status = CommitResult.Composing; return false; }
        if (owner.Committed == owner.Editor.Text) return true;
        long revision = owner.Revision; string text = owner.Editor.Text;
        try
        {
            owner.Save(text);
            if (revision == owner.Revision) owner.Committed = text;
            Status = CommitResult.Committed; return true;
        }
        catch (Exception ex)
        {
            Status = CommitResult.Failed;
            SaveFailed?.Invoke(this, EventArgs.Empty);
            log.Error($"保存编辑失败：{owner.Id}，保留缓冲。", ex);
            return false;
        }
    }
    public CommitResult TryCommitPending()
    {
        if (HasComposition) return Status = CommitResult.Composing;
        bool success = true;
        foreach (var owner in owners.Values) { owner.Timer.Stop(); success &= Commit(owner); }
        return Status = success ? CommitResult.Committed : CommitResult.Failed;
    }
    public void Remove(TextBox editor) { if (owners.Remove(editor, out var owner)) owner.Timer.Stop(); }
    public void Dispose() { foreach (var owner in owners.Values) owner.Timer.Stop(); owners.Clear(); }
}
