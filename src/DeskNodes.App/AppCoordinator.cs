using System.IO;
using System.Collections.Immutable;
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
    public PresentationCoordinator Presentation { get; private set; } = null!;
    public IReadOnlyDictionary<NoteId, NoteWindow> Windows => windows;
    public RectD CollapseEntrance => toolbar?.EntranceBounds ?? ToolbarGeometry.ResolveAnchor(Screens.GetScreens(), Preferences, Preferences.Orientation, false);
    private DeskNodesDatabase? database;
    private Forms.NotifyIcon? tray;
    private Forms.ContextMenuStrip? trayMenu;
    private DispatcherTimer? timer;
    private ToolbarWindow? toolbar;
    private System.Drawing.Icon? trayIcon;
    private SettingsWindow? settingsWindow;
    public bool SettingsVisible => settingsWindow?.IsVisible == true;
    public event EventHandler? PreferencesChanged;
    public string LastError { get; private set; } = "";
    public event EventHandler? ErrorChanged;
    public void RecordError(string message)
    {
        LastError = message;
        ErrorChanged?.Invoke(this, EventArgs.Empty);
    }
    public void OpenSettings()
    {
        if (settingsWindow is null)
        {
            settingsWindow = new(this);
            settingsWindow.Closed += (_, _) =>
            {
                settingsWindow = null;
                toolbar?.InputChanged();
            };
        }
        settingsWindow.Show();
        settingsWindow.Activate();
        toolbar?.InputChanged();
    }
    public int RolloverMinutes => database!.Read(connection =>
    {
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT rollover_minutes FROM business_settings WHERE singleton=1";
        return Convert.ToInt32(command.ExecuteScalar());
    });
    public void SetRolloverMinutes(int minutes)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(minutes);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(minutes, 1439);
        database!.Transaction(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText = "UPDATE business_settings SET rollover_minutes=$minutes WHERE singleton=1";
            command.Parameters.AddWithValue("$minutes", minutes);
            command.ExecuteNonQuery();
        });
        var result = rollover.CheckAndAdvance();
        if (result.Status == RolloverStatus.Failed) throw new InvalidOperationException("跨天处理失败，将自动重试。");
        Refresh();
        historyWindow?.Reload();
    }
    public bool TrayMenuOpen { get; private set; }
    public bool Raised { get; private set; }
    public int NoteCount => windows.Count;
    public AppMenus Menus { get; private set; } = null!;
    private HistoryWindow? historyWindow;
    public RecentlyDeleted Deleted { get; private set; } = null!;
    public void OpenHistory(HistoryDay? day = null, bool deleted = false)
    {
        if (historyWindow is null)
        {
            historyWindow = new(this);
            historyWindow.Closed += (_, _) => historyWindow = null;
        }
        historyWindow.Open(day, deleted);
    }
    public void RestoreDeleted(DeletedEntry entry) => Run(() =>
    {
        var result = entry.Member.NoteId is { } note ? Deleted.Restore(note) : Deleted.Restore(entry.Member.ItemId!.Value);
        if (result == RestoreResult.Restored)
        {
            if (entry.Member.NoteId is not null && Preferences.DeskCollapsed)
                SavePreferences(Preferences with { DeskCollapsed = false });
            Refresh();
            if (entry.Member.NoteId is { } restored)
                Presentation.RevealRestored(restored);
        }
        else
            Presentation.Error("未能恢复内容，请刷新后重试。");
        historyWindow?.Reload();
    });
    public HistoryQueries History { get; private set; } = null!;
    public BusinessDayContext BusinessDays { get; private set; } = null!;
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
        Presentation = new(this);
        Editors.SaveFailed += (_, _) => Presentation.Error("保存失败，请重试；编辑内容已保留。");
        Refresh();
        Screens.Changed += (_, _) => Refresh();
        History = new(database);
        Deleted = new(database, Clock, Undo);
        BusinessDays = new(database, Clock);
        Menus = new(this);
        toolbar = new(this);
        Screens.Changed += (_, _) => ShowToolbar();
        var menu = trayMenu = new Forms.ContextMenuStrip();
        menu.Opening += (_, _) =>
        {
            Menus.PopulateTray(menu);
            TrayMenuOpen = true;
            toolbar?.InputChanged();
        };
        menu.Closed += (_, _) =>
        {
            TrayMenuOpen = false;
            toolbar?.InputChanged();
        };
        trayIcon = CreateTrayIcon();
        tray = new Forms.NotifyIcon
        {
            Text = "DeskNodes",
            Icon = trayIcon,
            ContextMenuStrip = menu,
            Visible = true
        };
        tray.MouseClick += (_, e) =>
        {
            if (e.Button == Forms.MouseButtons.Left) ShowToolbar();
        };
        timer = new DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(30)
        };
        timer.Tick += (_, _) =>
        {
            var result = rollover.CheckAndAdvance();
            if (result.Status == RolloverStatus.Sealed) Refresh();
            if (result.Status == RolloverStatus.Failed) Presentation.Error("跨天处理失败，当前内容已保留。稍后将重试。");
            Presentation.Refresh();
        };
        timer.Start();
    }

    private static System.Drawing.Icon CreateTrayIcon()
    {
        byte[] Draw(int size)
        {
            using var bitmap = new System.Drawing.Bitmap(size, size);
            using var graphics = System.Drawing.Graphics.FromImage(bitmap);
            graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            graphics.ScaleTransform(size / 32f, size / 32f);
            using var paper = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(246, 241, 231));
            using var pen = new System.Drawing.Pen(System.Drawing.Color.FromArgb(36, 40, 45), 2);
            graphics.FillEllipse(paper, 3, 3, 26, 26);
            graphics.DrawEllipse(pen, 3, 3, 26, 26);
            graphics.DrawLine(pen, 11, 11, 21, 11);
            graphics.DrawLine(pen, 11, 16, 21, 16);
            graphics.DrawLine(pen, 11, 21, 17, 21);
            using var png = new MemoryStream();
            bitmap.Save(png, System.Drawing.Imaging.ImageFormat.Png);
            return png.ToArray();
        }
        var images = new[] { (Size: 16, Data: Draw(16)), (Size: 32, Data: Draw(32)) };
        using var stream = new MemoryStream();
        using var writer = new BinaryWriter(stream, System.Text.Encoding.UTF8, true);
        writer.Write((ushort)0);
        writer.Write((ushort)1);
        writer.Write((ushort)images.Length);
        int offset = 6 + images.Length * 16;
        foreach (var image in images)
        {
            writer.Write((byte)image.Size);
            writer.Write((byte)image.Size);
            writer.Write((byte)0);
            writer.Write((byte)0);
            writer.Write((ushort)1);
            writer.Write((ushort)32);
            writer.Write(image.Data.Length);
            writer.Write(offset);
            offset += image.Data.Length;
        }
        foreach (var image in images) writer.Write(image.Data);
        stream.Position = 0;
        using var icon = new System.Drawing.Icon(stream);
        return (System.Drawing.Icon)icon.Clone();
    }
    public void RebuildTray()
    {
        if (tray is null) return;
        tray.Visible = false;
        tray.Icon = trayIcon;
        tray.Visible = true;
    }
    public void ShowToolbar() => toolbar?.RestoreExpanded();
    public void SavePreferences(LocalPreferences value)
    {
        value = value.Normalize();
        bool typographyChanged = value.Font != Preferences.Font || value.TextSize != Preferences.TextSize;
        if (typographyChanged && Editors.TryCommitPending() != CommitResult.Committed)
            throw new InvalidOperationException("请先结束组词或完成当前编辑，再切换字体和字号。");
        if (typographyChanged && !new Themes.NoteFonts().Resolve(value.Font).Available)
            throw new InvalidOperationException(value.Font == NoteFont.Wenkai ? "此版本未包含文楷字体，请选择其他字体。" : "所选字体未安装。");
        preferencesStore.Save(value);
        Preferences = value;
        if (typographyChanged)
            foreach (var window in windows.Values) window.RefreshTypography();
        PreferencesChanged?.Invoke(this, EventArgs.Empty);
        RefreshTheme();
        toolbar?.Rebuild();
        toolbar?.InputChanged();
        RefreshVisibility();
    }
    public void Exit() => Application.Current.Shutdown();
    public void ToggleCollapsed() => Presentation.Collapse(!Preferences.DeskCollapsed);
    public void EndRaised()
    {
        Raised = false;
        foreach (var window in windows.Values) window.SetTemporarilyRaised(Presentation.Selecting);
        toolbar?.Rebuild();
    }
    public void ToggleRaised()
    {
        Presentation.ExitSelection();
        if (Raised)
        {
            EndRaised();
            return;
        }
        if (Preferences.DeskCollapsed) Presentation.Collapse(false);
        Raised = true;
        Presentation.Refresh();
        var target = windows.Values.FirstOrDefault(w => w.IsVisible && w.IsSelected) ?? windows.Values.FirstOrDefault(w => w.IsVisible);
        if (target is not null && !NativeMethods.SetForegroundWindow(new WindowInteropHelper(target).Handle))
            Presentation.Error("点击便签继续");
        toolbar?.Rebuild();
    }
    public void Arrange()
    {
        Presentation.ExitSelection();
        var screens = Screens.GetScreens();
        var notes = Repository.GetNotes();
        var previousBounds = windows.ToDictionary(p => p.Key, p => p.Value.Bounds);
        var arrangement = Arranger.Arrange(screens, notes, (note, width) => windows[note.Id].MeasureForArrangement(width),
            ToolbarGeometry.ResolveAnchor(screens, Preferences, Preferences.Orientation, Preferences.Pages.Values.Any(p => p > 0)),
            ToolbarGeometry.AnchorScreen(screens, Preferences).Id);
        database!.Transaction(_ =>
        {
            foreach (var entry in arrangement.Notes)
            {
                var note = notes.First(n => n.Id == entry.Id);
                Repository.Update(new Note(note.Id, note.Title, note.Color, note.SortOrder, entry.ToPlacement(screens.Resolve(entry.ScreenId)),
                    note.SavedLevel, null, note.AutomaticHeight, note.Collapsed, note.CreatedAt, Clock.UtcNow));
            }
        });
        SavePreferences(Preferences with { DeskCollapsed = false, Page = 0,
            Pages = arrangement.Notes.ToImmutableDictionary(n => n.Id.ToString(), n => n.Page) });
        Refresh();
        foreach (var pair in windows.Where(p => p.Value.IsVisible)) pair.Value.ArrangeFrom(previousBounds[pair.Key]);
    }
    public void ChangePage(int delta)
    {
        Presentation.ExitSelection();
        int pages = Preferences.Pages.Values.DefaultIfEmpty().Max() + 1;
        SavePreferences(Preferences with { Page = (Preferences.Page + delta + pages) % pages });
    }
    private void RefreshVisibility() => Presentation.Refresh();

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
            Presentation.Error("操作失败，当前内容已保留。请重试。");
        }
    }

    public void Select(NoteWindow target)
    {
        foreach (var window in windows.Values)
            window.SetSelected(window == target);
    }

    public void RefreshTheme()
    {
        historyWindow?.RefreshTheme();
        foreach (var window in windows.Values) window.RefreshTheme();
        toolbar?.RefreshTheme();
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

            }
            else
                window.RefreshNote(note);
        }
        if (notes.Count == 0)
        {
            Raised = false;
            if (Preferences.DeskCollapsed) SavePreferences(Preferences with { DeskCollapsed = false });
        }
        RefreshVisibility();
        toolbar?.Rebuild();
    }

    public void CreateNote()
    {
        Presentation.ExitSelection();
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
        var window = windows[created.Note.Id];
        if (NativeMethods.SetForegroundWindow(new WindowInteropHelper(window).Handle))
            window.FocusItem(created.FirstItemId);
        else
            Log.Warn("系统拒绝前台激活，请点击新便签继续编辑。");
    }

    public void ChangeSize(int delta, bool reset = false) => Run(() =>
    {
        SavePreferences(Preferences with
        {
            TextSize = reset ? NoteTextSize.Standard : (NoteTextSize)Math.Clamp((int)Preferences.TextSize + delta, 0, 3)
        });
    });
    public void Update(Note note, NoteColor? color = null, NoteLevel? level = null, Placement? placement = null,
        bool? automatic = null, bool? collapsed = null, RectD? free = null, bool clearFree = false)
    {
        Repository.Update(new Note(note.Id, note.Title, color ?? note.Color, note.SortOrder, placement ?? note.Placement,
            level ?? note.SavedLevel, clearFree ? null : free ?? note.FreeRestore, automatic ?? note.AutomaticHeight,
            collapsed ?? note.Collapsed, note.CreatedAt, Clock.UtcNow));
        Refresh();
    }

    public void ReorderDock(IReadOnlyList<Note> notes)
    {
        database!.Transaction(_ =>
        {
            for (int i = 0; i < notes.Count; i++)
            {
                var n = notes[i];
                Repository.Update(new Note(n.Id, n.Title, n.Color, n.SortOrder,
                    new(n.Placement.Bounds, n.Placement.DisplayDeviceHint, n.Placement.DockEdge, i),
                    n.SavedLevel, n.FreeRestore, n.AutomaticHeight, n.Collapsed, n.CreatedAt, Clock.UtcNow));
            }
        });
        Refresh();
    }

    public void DeleteNotes(IEnumerable<NoteId> ids)
    {
        Undo.DeleteNotes(ids);
        Presentation.ExitSelection();
        NewInputSinceDeletion = false;
        Refresh();
    }
    public void UndoDeletion()
    {
        Undo.Undo(Clock.UtcNow);
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
        settingsWindow?.Close();
        historyWindow?.Close();
        Presentation?.Dispose();
        toolbar?.Close();
        tray?.Dispose();
        trayIcon?.Dispose();
        trayMenu?.Dispose();
        foreach (var window in windows.Values)
            window.ReleaseEditors();
        Editors?.Dispose();
        Screens?.Dispose();
        database?.Dispose();
        database = null;
    }
}
