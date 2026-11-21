using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;
using DeskNodes.App.Interop;
using DeskNodes.Core.Services;
using DeskNodes.Core.Storage;
using TextBox = System.Windows.Controls.TextBox;

namespace DeskNodes.App.Editing;

/// <summary>Each registration owns its buffer and timer until the corresponding editor is removed.</summary>
internal sealed class EditorCoordinator(IDeskNodesLog log, DeskNodesDatabase database) : ICommitBarrier, IDisposable
{
    private sealed record Binding(EditorSession.Owner Owner, DispatcherTimer Timer, Action<string> Refresh, Action Detach);
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
        int compositionEpoch = 0;
        void CompositionStarted(object sender, TextCompositionEventArgs e)
        {
            session.SetComposition(owner, true);
            timer.Stop();
            compositionEpoch++;
        }
        void CompositionUpdated(object sender, TextCompositionEventArgs e)
        {
            session.SetComposition(owner, true);
            timer.Stop();
        }
        TextCompositionManager.AddPreviewTextInputStartHandler(editor, CompositionStarted);
        TextCompositionManager.AddPreviewTextInputUpdateHandler(editor, CompositionUpdated);
        void QueueCompositionEnded()
        {
            // Esc 取消通常不产生 TextInput。等本条输入消息把候选从文本里拿走，再结束组词并重新防抖。
            int epoch = compositionEpoch;
            editor.Dispatcher.BeginInvoke(() =>
            {
                if (!owner.Valid || !owner.Composing || epoch != compositionEpoch)
                    return;
                session.SetComposition(owner, false);
                session.Reschedule(owner);
            }, DispatcherPriority.Background);
        }
        editor.PreviewKeyDown += (_, e) =>
        {
            if (owner.Composing && (e.Key == Key.Escape || (e.Key == Key.ImeProcessed && e.ImeProcessedKey == Key.Escape)))
                QueueCompositionEnded();
        };
        HwndSource? source = null;
        HwndSourceHook? hook = null;
        void EnsureImeHook()
        {
            if (hook is not null)
                return;
            source = PresentationSource.FromVisual(editor) as HwndSource;
            if (source is null)
                return;
            hook = (hwnd, message, wParam, lParam, ref handled) =>
            {
                if (message == NativeMethods.WM_IME_ENDCOMPOSITION && owner.Composing && editor.IsKeyboardFocusWithin)
                    QueueCompositionEnded();
                return 0;
            };
            source.AddHook(hook);
        }
        RoutedEventHandler onLoaded = (_, _) => EnsureImeHook();
        editor.Loaded += onLoaded;
        if (editor.IsLoaded)
            EnsureImeHook();
        void Detach()
        {
            editor.Loaded -= onLoaded;
            if (source is { IsDisposed: false } && hook is not null)
                source.RemoveHook(hook);
            hook = null;
            source = null;
        }
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
        }, Detach));
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
            binding.Detach();
        }
    }
    public void InvalidateAll()
    {
        session.InvalidateAll();
        foreach (var pair in owners)
        {
            pair.Value.Timer.Stop();
            pair.Value.Detach();
            pair.Key.IsUndoEnabled = false;
        }
        owners.Clear();
    }
    public void Dispose() => InvalidateAll();
}
