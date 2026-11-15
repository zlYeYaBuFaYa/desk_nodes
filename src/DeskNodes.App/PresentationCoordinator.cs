using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;
using DeskNodes.App.Interop;
using DeskNodes.App.Platform;
using DeskNodes.App.Views;
using DeskNodes.Core.Domain;
using DeskNodes.Core.Presentation;
using DeskNodes.Core.Services;

namespace DeskNodes.App;

internal sealed class PresentationCoordinator : IDisposable
{
    private readonly AppCoordinator app;
    private readonly VirtualDesktop desktop = new();
    private readonly PresentationState state = new();
    private readonly Dictionary<(string Screen, DockEdge Edge), int> dockPages = [];
    private readonly Dictionary<(string Screen, DockEdge Edge), DockOverflowWindow> dockLabels = [];
    public DockResult Dock(ScreenInfo screen, DockEdge edge)
    {
        var screens = app.Screens.GetScreens();
        var notes = app.Repository.GetNotes().Where(n => n.Placement.DockEdge == edge && screens.Resolve(n.Placement.DisplayDeviceHint).Id == screen.Id);
        RectD? home = screen.Id == ToolbarGeometry.AnchorScreen(screens, app.Preferences).Id
            ? ToolbarGeometry.Home(screens, screen, app.Preferences.Home).HomeZone : null;
        return DockLayout.Arrange(screen, edge, notes.Select(n => new DockItem(n.Id, n.Placement.DockOrder ?? 0, n.Collapsed ? 32 : n.Placement.Bounds.Height)), home, dockPages.GetValueOrDefault((screen.Id, edge)));
    }
    private readonly NoteSelection selection = new();
    private readonly List<SelectionOverlay> overlays = [];
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(100) };
    private PresentationBar? selectionBar, deletionBar, errorBar;
    private (int Count, RectD Bounds)? deletionState;
    private DateTimeOffset errorUntil;
    private DateTimeOffset desktopCheck;
    private PointD? boxStart;
    private NoteId? clicked;
    private bool append, dragged, priorRaised;
    public bool Selecting => selectionBar is not null;
    public Dictionary<NoteId, SuppressionReason> Suppressed { get; } = [];
    public PresentationCoordinator(AppCoordinator app)
    {
        this.app = app;
        timer.Tick += (_, _) => Tick();
        timer.Start();
    }
    public void Refresh()
    {
        var notes = app.Repository.GetNotes();
        var screens = app.Screens.GetScreens();
        Suppressed.Clear();
        var overflow = new HashSet<NoteId>();
        foreach (var group in notes.Where(n => n.Placement.DockEdge is not null).GroupBy(n => (screens.Resolve(n.Placement.DisplayDeviceHint).Id, Edge: n.Placement.DockEdge!.Value)))
        {
            var screen = screens.Resolve(group.Key.Id);
            var result = Dock(screen, group.Key.Edge);
            overflow.UnionWith(result.Overflow);
            var key = (screen.Id, group.Key.Edge);
            if (result.Overflow.Count > 0)
            {
                if (!dockLabels.TryGetValue(key, out var label))
                {
                    label = new(delta =>
                    {
                        dockPages[key] = (Dock(screen, key.Item2).Page + delta + result.PageCount) % result.PageCount;
                        foreach (var window in app.Windows.Values) window.Place();
                        Refresh();
                    }, id =>
                    {
                        for (int page = 0; page < result.PageCount; page++)
                        {
                            dockPages[key] = page;
                            if (Dock(screen, key.Item2).Visible.Any(n => n.Id == id)) break;
                        }
                        foreach (var window in app.Windows.Values) window.Place();
                        Refresh();
                        app.Windows[id].SetTemporarilyRaised(true);
                    });
                    dockLabels.Add(key, label);
                }
                label.DataContext = new DockOverflowModel($"{result.Page + 1}/{result.PageCount}", result.Overflow.Select(id => new DockOverflowEntry(id, notes.First(n => n.Id == id).Title)).ToArray());
                if (result.OverflowBounds is { } bounds)
                {
                    label.Left = bounds.X;
                    label.Top = bounds.Y;
                    label.Width = bounds.Width;
                    label.Height = bounds.Height;
                }
                if (!app.Preferences.DeskCollapsed && !Selecting) label.Show();
                else label.Hide();
            }
        }
        foreach (var key in dockLabels.Keys.ToArray())
        {
            if (notes.Any(n => n.Placement.DockEdge == key.Edge && screens.Resolve(n.Placement.DisplayDeviceHint).Id == key.Screen) && Dock(screens.Resolve(key.Screen), key.Edge).Overflow.Count > 0) continue;
            dockLabels[key].Close();
            dockLabels.Remove(key);
        }
        foreach (var note in notes)
        {
            var window = app.Windows[note.Id];
            var handle = new WindowInteropHelper(window).EnsureHandle();
            string screen = screens.Resolve(note.Placement.DisplayDeviceHint).Id;
            int last = notes.Where(n => screens.Resolve(n.Placement.DisplayDeviceHint).Id == screen)
                .Select(n => app.Preferences.Pages.GetValueOrDefault(n.Id.ToString())).DefaultIfEmpty().Max();
            var reasons = PresentationRules.Suppressed(app.Preferences.DeskCollapsed,
                app.Preferences.Pages.TryGetValue(note.Id.ToString(), out int page) ? page : null, app.Preferences.Page, last,
                overflow.Contains(note.Id), desktop.IsCurrent(handle));
            Suppressed[note.Id] = reasons;
            if (reasons == SuppressionReason.None)
            {
                window.Show();
                window.SetTemporarilyRaised(app.Raised || Selecting);
            }
            else if (state.Transition != DeskTransition.Collapsing || reasons != SuppressionReason.Collapsed) window.Hide();
        }
        selection.Retain(Visible());
        UpdateSelection();
        if (selectionBar is not null)
            NativeMethods.SetWindowPos(new WindowInteropHelper(selectionBar).Handle, NativeMethods.Topmost, 0, 0, 0, 0,
                NativeMethods.NoActivate | NativeMethods.NoMove | NativeMethods.NoSize);
    }
    private IEnumerable<NoteId> Visible() => Suppressed.Where(p => p.Value == SuppressionReason.None).Select(p => p.Key);
    public void Collapse(bool collapsed)
    {
        ExitSelection();
        if (collapsed) app.EndRaised();
        long generation = state.Request(collapsed);
        app.SavePreferences(app.Preferences with { DeskCollapsed = collapsed });
        var screens = app.Screens.GetScreens();
        var screen = ToolbarGeometry.AnchorScreen(screens, app.Preferences);
        var entry = app.CollapseEntrance;
        int index = 0;
        foreach (var pair in app.Windows)
        {
            if ((Suppressed.GetValueOrDefault(pair.Key) & ~SuppressionReason.Collapsed) != 0) continue;
            var target = CollapseGeometry.Target(entry, screen.WorkArea, index++);
            double scale = screens.Resolve(ScreenProvider.DeviceForWindow(new WindowInteropHelper(pair.Value).Handle)).DpiScale;
            double ratio = screen.DpiScale / scale;
            target = new(target.X * ratio, target.Y * ratio, target.Width * ratio, target.Height * ratio);
            pair.Value.Present(collapsed, target, .28, () =>
            {
                if (generation != state.Generation) return;
                state.Complete(generation);
                Refresh();
            });
        }
        if (index == 0) state.Complete(generation);
    }
    public void EnterSelection(NoteId? initial = null)
    {
        if (Selecting || app.NoteCount == 0 || app.Editors.TryCommitPending() != CommitResult.Committed) return;
        priorRaised = app.Raised;
        if (app.Preferences.DeskCollapsed) Collapse(false);
        foreach (var screen in app.Screens.GetScreens().Screens)
        {
            var overlay = new SelectionOverlay(this, screen);
            overlays.Add(overlay);
            overlay.Show();
        }
        selectionBar = new(true, DeleteSelection, SelectAll, ExitSelection) { Topmost = true };
        selectionBar.Model.ActionText = "删除";
        selectionBar.Place(PresentationRules.Prompt(app.Screens.GetScreens().Primary.WorkArea, 380, 46, 28));
        selectionBar.Show();
        if (initial is { } id) selection.Apply([id]);
        Refresh();
    }
    public void ExitSelection()
    {
        if (!Selecting) return;
        Mouse.Capture(null);
        boxStart = null;
        foreach (var overlay in overlays) overlay.Close();
        overlays.Clear();
        selectionBar?.Close();
        selectionBar = null;
        selection.Apply([]);
        foreach (var window in app.Windows.Values)
        {
            window.SetMultiSelection(false, false);
            window.SetTemporarilyRaised(priorRaised && app.Raised);
        }
    }
    private void UpdateSelection()
    {
        foreach (var pair in app.Windows) pair.Value.SetMultiSelection(Selecting, selection.Picked.Contains(pair.Key));
        foreach (var overlay in overlays) System.Windows.Automation.AutomationProperties.SetName(overlay, $"便签多选覆盖层，已选 {selection.Picked.Count} 张，拖动框选，Escape 完成");
        if (selectionBar is null) return;
        selectionBar.Model.Message = $"已选 {selection.Picked.Count} 张";
        selectionBar.Model.CanAct = selection.CanDelete;
        selectionBar.Model.Refresh();
    }
    private void SelectAll()
    {
        selection.Apply(Visible());
        UpdateSelection();
    }
    private void DeleteSelection() => app.Run(() =>
    {
        if (!selection.CanDelete) return;
        app.DeleteNotes(selection.Picked.ToArray());
    });
    public void Keys(KeyEventArgs e)
    {
        if (app.Editors.HasComposition || e.Key == Key.ImeProcessed) return;
        if (e.Key == Key.Escape)
        {
            if (Selecting) ExitSelection();
            else app.EndRaised();
            e.Handled = true;
        }
        if (!Selecting) return;
        if (e.Key == Key.A && Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) SelectAll();
        else if (e.Key is Key.Delete or Key.Back) DeleteSelection();
        else return;
        e.Handled = true;
    }
    private static PointD Pointer()
    {
        NativeMethods.GetCursorPos(out var p);
        return new(p.X, p.Y);
    }
    public void BeginBox(UIElement source, NoteId? id, MouseButtonEventArgs e)
    {
        if (!Selecting) EnterSelection();
        if (!Selecting) return;
        boxStart = Pointer();
        clicked = id;
        dragged = false;
        append = Keyboard.Modifiers.HasFlag(ModifierKeys.Control);
        Mouse.Capture(source);
        e.Handled = true;
    }
    public void MoveBox(MouseEventArgs e)
    {
        if (boxStart is not { } start || e.LeftButton != MouseButtonState.Pressed) return;
        var p = Pointer();
        if (Math.Abs(p.X - start.X) + Math.Abs(p.Y - start.Y) < 5) return;
        dragged = true;
        var box = new RectD(Math.Min(start.X, p.X), Math.Min(start.Y, p.Y), Math.Abs(start.X - p.X), Math.Abs(start.Y - p.Y));
        foreach (var overlay in overlays) overlay.Draw(box);
        e.Handled = true;
    }
    public void EndBox(MouseButtonEventArgs e)
    {
        if (boxStart is not { } start) return;
        var p = Pointer();
        if (dragged)
        {
            var box = new RectD(Math.Min(start.X, p.X), Math.Min(start.Y, p.Y), Math.Abs(start.X - p.X), Math.Abs(start.Y - p.Y));
            selection.Apply(NoteSelection.Intersect(box, Visible().Select(id => (id, app.Windows[id].PixelBounds))), append);
        }
        else if (clicked is { } id) selection.Toggle(id);
        else selection.Apply([]);
        boxStart = null;
        Mouse.Capture(null);
        foreach (var overlay in overlays) overlay.Draw(null);
        UpdateSelection();
        e.Handled = true;
    }
    public void Deactivated()
    {
        Application.Current.Dispatcher.BeginInvoke(() =>
        {
            var foreground = NativeMethods.GetForegroundWindow();
            NativeMethods.GetWindowThreadProcessId(foreground, out uint process);
            if (!PresentationRules.EndsRaise(toggle: false, escape: false, collapsed: false, empty: false,
                appDeactivated: true, foregroundOwned: foreground == 0 || process == Environment.ProcessId, composing: app.Editors.HasComposition)) return;
            ExitSelection();
            app.EndRaised();
        }, DispatcherPriority.Background);
    }
    public void Error(string message)
    {
        errorBar ??= new(false, () => { });
        errorBar.HideAction();
        errorBar.Model.Message = message;
        errorBar.Model.Refresh();
        errorBar.PlaceError(app.Screens.GetScreens().Primary.WorkArea);
        errorUntil = app.Clock.UtcNow.AddSeconds(5);
    }
    private void Tick()
    {
        if (app.Clock.UtcNow >= desktopCheck)
        {
            desktopCheck = app.Clock.UtcNow.AddSeconds(1);
            bool changed = app.Windows.Any(pair =>
                desktop.IsCurrent(new WindowInteropHelper(pair.Value).Handle) == Suppressed.GetValueOrDefault(pair.Key).HasFlag(SuppressionReason.OtherDesktop));
            if (changed) Refresh();
        }
        int count = app.Undo.PromptCount(app.Clock.UtcNow);
        if (count > 0)
        {
            deletionBar ??= new(false, () => app.Run(() =>
            {
                app.UndoDeletion();
            }));
            var bounds = PresentationRules.DeletionPrompt(app.Screens.GetScreens().Primary.WorkArea, Selecting);
            if (deletionState is not { } previous || previous.Count != count)
            {
                deletionBar.Model.Message = $"已删除 {count} 项";
                deletionBar.Model.ActionText = "撤销";
                deletionBar.Model.Refresh();
            }
            if (deletionState is not { } placed || placed.Bounds != bounds) deletionBar.Place(bounds);
            if (!deletionBar.IsVisible) deletionBar.Show();
            deletionState = (count, bounds);
        }
        else if (deletionState is not null)
        {
            deletionBar?.Hide();
            deletionState = null;
        }
        if (app.Clock.UtcNow >= errorUntil) errorBar?.Hide();
    }
    public void Dispose()
    {
        timer.Stop();
        ExitSelection();
        deletionBar?.Close();
        errorBar?.Close();
        foreach (var label in dockLabels.Values) label.Close();
        desktop.Dispose();
    }
}
