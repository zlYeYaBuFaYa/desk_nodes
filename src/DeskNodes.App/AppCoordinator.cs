using System.IO;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;
using DeskNodes.App.Editing;
using DeskNodes.App.Interop;
using DeskNodes.App.Platform;
using DeskNodes.App.Views;
using DeskNodes.Core.Domain;
using DeskNodes.Core.Presentation;
using DeskNodes.Core.Services;
using DeskNodes.Core.Storage;
using Forms = System.Windows.Forms;

namespace DeskNodes.App;

internal sealed class AppCoordinator
{
    private DeskNodesDatabase? database;
    private Forms.NotifyIcon? tray;
    private Forms.ContextMenuStrip? trayMenu;
    private DispatcherTimer? timer;
    private DayRolloverService rollover = null!;
    private LocalPreferencesStore preferencesStore = null!;
    private readonly Dictionary<NoteId, NoteWindow> windows = [];
    public string? DataDirectoryPath { get; private set; }
    public NoteRepository Repository { get; private set; } = null!;
    public NoteActions Actions { get; private set; } = null!;
    public DeletionUndoQueue Undo { get; private set; } = null!;
    public EditorCoordinator Editors { get; private set; } = null!;
    public IDeskNodesLog Log { get; private set; } = null!;
    public ScreenProvider Screens { get; private set; } = null!;
    public LocalPreferences Preferences { get; private set; } = new();
    public IClock Clock { get; }
    public AppCoordinator(IClock? clock = null) => Clock = clock ?? new SystemClock();
    public bool NewInputSinceDeletion { get; set; }
    public void Start()
    {
        DataDirectoryPath = DataDirectory.Resolve();
        Log = new FileLog(DataDirectoryPath, Clock);
        database = DeskNodesDatabase.Open(Path.Combine(DataDirectoryPath, DataDirectory.DatabaseFileName));
        preferencesStore = new(Log, DataDirectoryPath);
        Preferences = preferencesStore.Load();
        Editors = new(Log);
        Editors.TextInput += (_, _) => NewInputSinceDeletion = true;
        var clock = Clock;
        Repository = new(database);
        Actions = new(database, clock);
        Undo = new(database, clock);
        Screens = new();
        rollover = new(database, clock, Editors, new(database, DataDirectoryPath, Log), Log);
        rollover.CheckAndAdvance();
        Refresh();
        Screens.Changed += (_, _) => Refresh();
        var menu = trayMenu = new Forms.ContextMenuStrip();
        menu.Items.Add("新建便签", null, (_, _) => Run(CreateNote));
        menu.Items.Add("退出 DeskNodes", null, (_, _) =>
        {
            if (Editors.TryCommitPending() == CommitResult.Committed)
                Application.Current.Shutdown();
        });
        tray = new Forms.NotifyIcon
        {
            Text = "DeskNodes",
            Icon = System.Drawing.SystemIcons.Application,
            ContextMenuStrip = menu,
            Visible = true
        };
        timer = new DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(30)
        };
        timer.Tick += (_, _) =>
        {
            if (rollover.CheckAndAdvance().Status == RolloverStatus.Sealed) Refresh();
        };
        timer.Start();
    }

    public void Run(Action action)
    {
        if (Editors.TryCommitPending() != CommitResult.Committed)
            return;
        try
        {
            action();
        }
        catch (Exception ex)
        {
            Log.Error("操作失败，保留当前窗口与编辑缓冲。", ex);
        }
    }

    public void Select(NoteWindow target)
    {
        foreach (var window in windows.Values)
            window.SetSelected(window == target);
    }

    public void RefreshTheme()
    {
        foreach (var window in windows.Values) window.RefreshTheme();
    }

    public void Refresh()
    {
        var notes = Repository.GetNotes();
        foreach (var id in windows.Keys.Except(notes.Select(n => n.Id)).ToArray())
        {
            var window = windows[id];
            windows.Remove(id);
            window.RemoveAnimated();
        }
        foreach (var note in notes)
        {
            if (!windows.TryGetValue(note.Id, out var window))
            {
                window = new(this, note);
                windows.Add(note.Id, window);
                if (!Preferences.DeskCollapsed)
                    window.Show();
            }
            else
                window.RefreshNote(note);
        }
    }

    public void CreateNote()
    {
        var screens = Screens.GetScreens();
        bool hasPaging = Preferences.Pages.Values.Any(page => page > 0);
        var toolbarTarget = ToolbarGeometry.ResolveAnchor(screens, Preferences, Preferences.Orientation, hasPaging);
        var screen = ToolbarGeometry.AnchorScreen(screens, Preferences);
        var size = NoteLayout.NewSize(Preferences, screen.WorkArea, _ => 160);
        var bounds = NoteLayout.New(screens, screen.Id, toolbarTarget, windows.Values.Where(w => w.IsVisible &&
            ScreenProvider.DeviceForWindow(new WindowInteropHelper(w).Handle) == screen.DeviceHint).Select(w => w.Bounds), size);
        var created = Actions.CreateNote(new(new(bounds.X - screen.Bounds.X, bounds.Y - screen.Bounds.Y, bounds.Width, bounds.Height), screen.DeviceHint), Preferences.NewHeight == 0);
        if (Preferences.DeskCollapsed)
        {
            Preferences = Preferences with
            {
                DeskCollapsed = false
            };
            preferencesStore.Save(Preferences);
        }
        Refresh();
        foreach (var w in windows.Values)
            if (!w.IsVisible)
                w.Show();
        var window = windows[created.Note.Id];
        if (NativeMethods.SetForegroundWindow(new WindowInteropHelper(window).Handle))
            window.FocusItem(created.FirstItemId);
        else
            Log.Warn("系统拒绝前台激活，请点击新便签继续编辑。");
    }

    public void ChangeSize(int delta, bool reset = false) => Run(() =>
    {
        Preferences = Preferences with
        {
            TextSize = reset ? NoteTextSize.Standard : (NoteTextSize)Math.Clamp((int)Preferences.TextSize + delta, 0, 3)
        };
        preferencesStore.Save(Preferences);
        foreach (var window in windows.Values)
            window.RefreshTypography();
    });
    public void Update(Note note, NoteColor? color = null, NoteLevel? level = null, Placement? placement = null,
        bool? automatic = null, bool? collapsed = null, RectD? free = null, bool clearFree = false)
    {
        Repository.Update(new Note(note.Id, note.Title, color ?? note.Color, note.SortOrder, placement ?? note.Placement,
            level ?? note.SavedLevel, clearFree ? null : free ?? note.FreeRestore, automatic ?? note.AutomaticHeight,
            collapsed ?? note.Collapsed, note.CreatedAt, Clock.UtcNow));
        Refresh();
    }

    public void DeleteItem(ItemId id)
    {
        Undo.DeleteItem(id);
        NewInputSinceDeletion = false;
        Refresh();
    }

    public void DeleteNote(NoteId id)
    {
        Undo.DeleteNote(id);
        NewInputSinceDeletion = false;
        Refresh();
    }

    public void Stop()
    {
        timer?.Stop();
        tray?.Dispose();
        trayMenu?.Dispose();
        foreach (var window in windows.Values)
            window.ReleaseEditors();
        Editors?.Dispose();
        Screens?.Dispose();
        database?.Dispose();
        database = null;
    }
}
