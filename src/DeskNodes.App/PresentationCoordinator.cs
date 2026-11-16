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
    public void RevealRestored(NoteId id)
    {
        var note = app.Repository.GetNote(id);
        if (note is null) return;
        if (app.Preferences.Pages.TryGetValue(id.ToString(), out int savedPage))
            app.SavePreferences(app.Preferences with { Page = savedPage });
        if (note.Placement.DockEdge is { } edge)
        {
            var screen = app.Screens.GetScreens().Resolve(note.Placement.DisplayDeviceHint);
            if (DockLayout.PageForNote(Dock(screen, edge), id) is { } page)
                dockPages[(screen.Id, edge)] = page;
        }
        foreach (var window in app.Windows.Values) window.Place();
        Refresh();
    }
    private readonly Dictionary<(string Screen, DockEdge Edge), int> dockPages = [];
    private readonly Dictionary<(string Screen, DockEdge Edge), DockOverflowWindow> dockLabels = [];
    public DockResult Dock(ScreenInfo screen, DockEdge edge)
    {
        var screens = app.Screens.GetScreens();
        var notes = app.Repository.GetNotes().Where(n => n.Placement.DockEdge == edge && screens.Resolve(n.Placement.DisplayDeviceHint).Id == screen.Id);
        RectD? home = screen.Id == ToolbarGeometry.AnchorScreen(screens, app.Preferences).Id
            ? ToolbarGeometry.Home(screens, screen, app.Preferences.Home).HomeZone : null;
        return DockLayout.Arrange(screen, edge, notes.Select(n => new DockItem(n.Id, n.Placement.DockOrder ?? 0, n.Collapsed ? 32 * app.TextScale : n.Placement.Bounds.Height)), home, dockPages.GetValueOrDefault((screen.Id, edge)));
    }
    private readonly NoteSelection selection = new();
    private readonly List<SelectionOverlay> overlays = [];
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(100) };
    private PresentationBar? selectionBar, deletionBar, errorBar;
    private (int Count, RectD Bounds)? deletionState;
    private readonly MonotonicTimeline timeline;
    private TimeSpan errorUntil;
    private TimeSpan desktopCheck;
    private PointD? boxStart;
    private NoteId? clicked;
    private bool append, dragged, priorRaised;
    private bool disposed;
    public bool Selecting => selectionBar is not null;
    public Dictionary<NoteId, SuppressionReason> Suppressed { get; } = [];
    public PresentationCoordinator(AppCoordinator app)
    {
        this.app = app;
        timeline = new(app.TimeProvider);
        timer.Tick += (_, _) => Tick();
        timer.Start();
    }
    public void Refresh()
    {
        if (disposed)
            return;
        var notes = app.Repository.GetNotes();
        var screens = app.Screens.GetScreens();
        var byId = notes.ToDictionary(n => n.Id);
        var lastPages = notes.GroupBy(n => screens.Resolve(n.Placement.DisplayDeviceHint).Id)
            .ToDictionary(g => g.Key, g => g.Max(n => app.Preferences.Pages.GetValueOrDefault(n.Id.ToString())));
        var docks = new Dictionary<(string Screen, DockEdge Edge), DockResult>();
        var anchorScreen = ToolbarGeometry.AnchorScreen(screens, app.Preferences).Id;
        Suppressed.Clear();
        var overflow = new HashSet<NoteId>();
        foreach (var group in notes.Where(n => n.Placement.DockEdge is not null).GroupBy(n => (screens.Resolve(n.Placement.DisplayDeviceHint).Id, Edge: n.Placement.DockEdge!.Value)))
        {
            var screen = screens.Resolve(group.Key.Id);
            RectD? home = screen.Id == anchorScreen ? ToolbarGeometry.Home(screens, screen, app.Preferences.Home).HomeZone : null;
            var key = (screen.Id, group.Key.Edge);
            var result = DockLayout.Arrange(screen, group.Key.Edge,
                group.Select(n => new DockItem(n.Id, n.Placement.DockOrder ?? 0, n.Collapsed ? 32 * app.TextScale : n.Placement.Bounds.Height)),
                home, dockPages.GetValueOrDefault(key));
            docks[key] = result;
            overflow.UnionWith(result.Overflow);
            if (result.Overflow.Count > 0)
            {
                if (!dockLabels.TryGetValue(key, out var label))
                {
                    label = new(delta => ChangeDockPage(key, delta), id => SelectDockNote(key, id));
                    dockLabels.Add(key, label);
                }
                label.DataContext = new DockOverflowModel($"{result.Page + 1}/{result.PageCount}", result.Overflow.Select(id => new DockOverflowEntry(id, byId[id].Title)).ToArray());
                if (result.OverflowBounds is { } bounds)
                {
                    label.Left = bounds.X;
                    label.Top = bounds.Y;
                    label.Width = bounds.Width;
                    label.Height = bounds.Height;
                }

            }
        }
        foreach (var key in dockLabels.Keys.ToArray())
        {
            if (docks.TryGetValue(key, out var current) && current.Overflow.Count > 0) continue;
            dockLabels[key].Close();
            dockLabels.Remove(key);
        }
        foreach (var note in notes)
        {
            if (!app.Windows.TryGetValue(note.Id, out var window))
            {
                System.Diagnostics.Debug.Assert(false, "便签窗口与存储不同步。");
                app.Log.Warn($"展示刷新缺少便签窗口：{note.Id}");
                continue;
            }
            var handle = new WindowInteropHelper(window).EnsureHandle();
            string screen = screens.Resolve(note.Placement.DisplayDeviceHint).Id;
            int last = lastPages[screen];
            var reasons = PresentationRules.Suppressed(app.Preferences.DeskCollapsed,
                app.Preferences.Pages.TryGetValue(note.Id.ToString(), out int page) ? page : null, app.Preferences.Page, last,
                overflow.Contains(note.Id), desktop.IsCurrent(handle));
            Suppressed[note.Id] = reasons;
            if (reasons == SuppressionReason.None)
            {
                if (PresentationRules.ShouldShowOnRefresh(state.Transition, window.IsVisible))
                    window.Show();
                window.SetTemporarilyRaised(app.Raised || Selecting);
            }
            else if (state.Transition != DeskTransition.Collapsing || reasons != SuppressionReason.Collapsed) window.Hide();
        }
        UpdateDockLabelVisibility();
        selection.Retain(Visible());
        UpdateSelection();
        if (selectionBar is not null)
            NativeMethods.SetWindowPos(new WindowInteropHelper(selectionBar).Handle, NativeMethods.Topmost, 0, 0, 0, 0,
                NativeMethods.NoActivate | NativeMethods.NoMove | NativeMethods.NoSize);
    }
    private DockResult? CurrentDock((string Screen, DockEdge Edge) key)
    {
        var screen = app.Screens.GetScreens().Screens.FirstOrDefault(s => s.Id == key.Screen);
        return screen is null ? null : Dock(screen, key.Edge);
    }
    private void ChangeDockPage((string Screen, DockEdge Edge) key, int delta) => app.Run(() =>
    {
        var result = CurrentDock(key);
        if (result is null)
            return;
        dockPages[key] = (result.Page + delta % result.PageCount + result.PageCount) % result.PageCount;
        foreach (var window in app.Windows.Values)
            window.Place();
        Refresh();
    });
    private void SelectDockNote((string Screen, DockEdge Edge) key, NoteId id) => app.Run(() =>
    {
        var result = CurrentDock(key);
        if (result is null || DockLayout.PageForNote(result, id) is not { } page)
            return;
        dockPages[key] = page;
        foreach (var window in app.Windows.Values)
            window.Place();
        Refresh();
        if (app.Windows.TryGetValue(id, out var target))
            target.SetTemporarilyRaised(true);
    });
    private IEnumerable<NoteId> Visible() => Suppressed.Where(p => p.Value == SuppressionReason.None).Select(p => p.Key);
    public void Collapse(bool collapsed)
    {
        ExitSelection();
        if (collapsed) app.EndRaised();
        long generation = state.Request(collapsed);
        if (!app.SavePreferences(app.Preferences with { DeskCollapsed = collapsed }))
        {
            state.Complete(generation);
            Refresh();
            return;
        }
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
    private void UpdateDockLabelVisibility()
    {
        foreach (var label in dockLabels.Values)
        {
            if (!disposed && !app.Preferences.DeskCollapsed && !Selecting)
                label.Show();
            else
                label.Hide();
        }
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
        UpdateDockLabelVisibility();
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
        app.RecordError(message);
        errorBar ??= new(false, () => { });
        errorBar.HideAction();
        errorBar.Model.Message = message;
        errorBar.Model.Refresh();
        errorBar.PlaceError(app.Screens.GetScreens().Primary.WorkArea);
        errorUntil = timeline.Elapsed + TimeSpan.FromSeconds(5);
    }
    private void Tick()
    {
        if (timeline.Elapsed >= desktopCheck)
        {
            desktopCheck = timeline.Elapsed + TimeSpan.FromSeconds(1);
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
        if (timeline.Elapsed >= errorUntil) errorBar?.Hide();
    }
    public void Dispose()
    {
        disposed = true;
        timer.Stop();
        ExitSelection();
        deletionBar?.Close();
        errorBar?.Close();
        foreach (var label in dockLabels.Values) label.Close();
        desktop.Dispose();
    }
}
