using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using DeskNodes.Core.Services;
using DeskNodes.Core.Storage;
using TextBox = System.Windows.Controls.TextBox;

namespace DeskNodes.App.Editing;

/// <summary>Each registration owns its buffer and timer until the corresponding editor is removed.</summary>
internal sealed class EditorCoordinator(IDeskNodesLog log, DeskNodesDatabase database) : ICommitBarrier, IDisposable
{
    private sealed record Binding(EditorSession.Owner Owner, DispatcherTimer Timer, Action<string> Refresh);
    private readonly EditorSession session = new(log, database);
    private readonly Dictionary<TextBox, Binding> owners = [];
    public event EventHandler? TextInput;
    public event EventHandler? SaveFailed
    {
        add => session.SaveFailed += value;
        remove => session.SaveFailed -= value;
    }
    public bool HasComposition => session.HasComposition;
    public CommitResult Status => session.Status;
    public void Register(TextBox editor, string id, Action<string> save)
    {
        var timer = new DispatcherTimer();
        Action? pending = null;
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            pending?.Invoke();
        };
        var owner = session.Register(id, editor.Text, save, (delay, callback) =>
        {
            timer.Stop();
            timer.Interval = delay;
            pending = callback;
            timer.Start();
        });
        bool updating = false;
        editor.TextChanged += (_, _) =>
        {
            if (!owner.Valid || updating)
                return;
            session.Change(owner, editor.Text);
            TextInput?.Invoke(this, EventArgs.Empty);
        };
        void CompositionStarted(object sender, TextCompositionEventArgs e)
        {
            session.SetComposition(owner, true);
            timer.Stop();
        }
        TextCompositionManager.AddPreviewTextInputStartHandler(editor, CompositionStarted);
        TextCompositionManager.AddPreviewTextInputUpdateHandler(editor, CompositionStarted);
        editor.AddHandler(TextCompositionManager.TextInputEvent, new TextCompositionEventHandler((_, _) =>
        {
            session.SetComposition(owner, false);
            editor.Dispatcher.BeginInvoke(() =>
            {
                if (owner.Valid)
                    session.Reschedule(owner);
            }, DispatcherPriority.Background);
        }), true);
        editor.LostKeyboardFocus += (_, _) =>
        {
            if (!owner.Composing)
                session.Commit(owner);
        };
        // Refresh writes are suppressed in this adapter; policy is owned by the session.
        owners.Add(editor, new(owner, timer, text =>
        {
            if (!session.Refresh(owner, text, editor.IsKeyboardFocusWithin))
                return;
            updating = true;
            try
            {
                if (editor.Text != text)
                    editor.Text = text;
            }
            finally
            {
                updating = false;
            }
        }));
    }
    public bool IsComposing(TextBox editor) => owners.TryGetValue(editor, out var binding) && binding.Owner.Composing;
    public void Refresh(TextBox editor, string text) => owners[editor].Refresh(text);
    public CommitResult TryCommitPending() => session.TryCommitPending();
    public void Remove(TextBox editor)
    {
        if (owners.Remove(editor, out var binding))
        {
            session.Remove(binding.Owner);
            binding.Timer.Stop();
        }
    }
    public void InvalidateAll()
    {
        session.InvalidateAll();
        foreach (var pair in owners)
        {
            pair.Value.Timer.Stop();
            pair.Key.IsUndoEnabled = false;
        }
        owners.Clear();
    }
    public void Dispose() => InvalidateAll();
}
