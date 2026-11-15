using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;
using DeskNodes.App.Interop;
using DeskNodes.App.Platform;
using DeskNodes.App.Themes;
using DeskNodes.Core.Domain;
using DeskNodes.Core.Presentation;

namespace DeskNodes.App.Views;

internal sealed partial class NoteWindow : Window
{
    private readonly AppCoordinator app;
    private Note note;
    private readonly NoteViewModel state = new();
    private readonly Dictionary<ItemId, ItemRowView> itemRows = [];
    private readonly NoteFonts fonts = new();
    private WindowLevelService? levels;
    private NoteTypography type = NoteTypography.For(NoteTextSize.Standard);
    private bool placing;
    private bool removing;
    private bool selected;
    public bool IsSelected => selected;
    private bool initialized;
    private int openMenus;
    public void SetTemporarilyRaised(bool raised)
    {
        if (levels is null) return;
        levels.TemporarilyRaised = raised;
        levels.Apply(!raised);
    }
    public double MeasureForArrangement(double width)
    {
        rows.Measure(new Size(Math.Max(1, width - 36), double.PositiveInfinity));
        var screen = app.Screens.GetScreens().Resolve(note.Placement.DisplayDeviceHint);
        return type.AutomaticHeight(rows.DesiredSize.Height, screen.WorkArea.Height);
    }
    public void SetSelected(bool value)
    {
        selected = value;
        UpdateSelection();
    }

    public NoteWindow(AppCoordinator app, Note note)
    {
        this.app = app;
        this.note = note;
        InitializeComponent();
        DataContext = state;
        title.Text = note.Title;
        app.Editors.Register(title, "title:" + note.Id, text => app.Actions.EditTitle(note.Id, text));
        PreviewKeyDown += WindowKeys;
        add.Click += (_, _) => app.Run(AddItem);
        more.Click += (_, _) => OpenMenu();
        title.ContextMenu = CreateEditorMenu(title);
        ContextMenu = new ContextMenu();
        ContextMenuOpening += OpenContextMenu;
        PreviewKeyDown += ContextMenuKeys;
        PreviewMouseLeftButtonDown += (_, e) =>
        {
            if (app.Presentation.Selecting || Keyboard.Modifiers.HasFlag(ModifierKeys.Control))
                app.Presentation.BeginBox(this, note.Id, e);
            else app.Select(this);
        };
        PreviewMouseMove += (_, e) => app.Presentation.MoveBox(e);
        PreviewMouseLeftButtonUp += (_, e) => app.Presentation.EndBox(e);
        Activated += (_, _) =>
        {
            app.Select(this);
            levels?.Apply();
        };
        Deactivated += (_, _) =>
        {
            if (!app.Editors.HasComposition) levels?.Apply(true);
            UpdateSelection();
        };
        SourceInitialized += (_, _) =>
        {
            nint hwnd = new WindowInteropHelper(this).Handle;
            NativeMethods.SetWindowLongPtr(hwnd, NativeMethods.GWL_EXSTYLE, NativeMethods.GetWindowLongPtr(hwnd, NativeMethods.GWL_EXSTYLE) | NativeMethods.WS_EX_TOOLWINDOW);
            NativeMethods.SetDwmPreference(hwnd, NativeMethods.DWMWA_WINDOW_CORNER_PREFERENCE, NativeMethods.DWMWCP_ROUND);
            levels = new(hwnd)
            {
                SavedLevel = this.note.SavedLevel
            };
            levels.Apply(true);
            HwndSource.FromHwnd(hwnd)?.AddHook(WindowMessage);
            initialized = true;
            Place();
        };
        Loaded += (_, _) =>
        {
            if (presentationGeneration == 0) Animate(false);
        };
        Closing += (_, e) =>
        {
            if (!removing && !Application.Current.Dispatcher.HasShutdownStarted) e.Cancel = true;
        };
        Closed += (_, _) => ReleaseEditors();
        SizeChanged += (_, _) =>
        {
            if (!placing && initialized && note.AutomaticHeight) MeasureHeight();
        };
        LostKeyboardFocus += (_, _) => Dispatcher.BeginInvoke(() =>
        {
            if (removing || openMenus > 0 || IsKeyboardFocusWithin || app.Editors.HasComposition) return;
            app.Run(() =>
            {
                if (app.Actions.CleanupBlankItems(note.Id) > 0) app.Refresh();
            });
        }, DispatcherPriority.Background);
        RefreshNote(note);
    }

    private void UpdateSelection()
    {
        state.Selected = selected;
        state.SelectionOpacity = applicationActive || SystemParameters.HighContrast ? 1 : .45;
        state.Refresh();
    }

    public void RefreshNote(Note value)
    {
        note = value;
        state.Collapsed = note.Collapsed;
        state.Color = note.Color;
        if (levels is not null)
        {
            levels.SavedLevel = note.SavedLevel;
            levels.Apply(!IsActive);
        }
        app.Editors.Refresh(title, note.Title);
        var items = app.Repository.GetItems(note.Id);
        foreach (var id in itemRows.Keys.Except(items.Select(i => i.Id)).ToArray())
        {
            app.Editors.Remove(itemRows[id].Editor);
            rows.Children.Remove(itemRows[id]);
            itemRows.Remove(id);
        }
        for (int i = 0; i < items.Count; i++)
        {
            var item = items[i];
            if (!itemRows.TryGetValue(item.Id, out var row))
            {
                row = CreateRow(item);
                itemRows.Add(item.Id, row);
            }
            int current = rows.Children.IndexOf(row);
            if (current != i)
            {
                if (current >= 0) rows.Children.Remove(row);
                rows.Children.Insert(i, row);
            }
            app.Editors.Refresh(row.Editor, item.Text);
            row.State.Completed = item.Completed;
            row.State.Struck = item.Struck;
            row.State.Refresh();
        }
        var progress = app.Actions.GetProgress(note.Id);
        state.Count = $"{progress.Completed}/{progress.Total}";
        state.Summary = app.Actions.CollapsedSummary(note.Id);
        RefreshTypography();
        UpdateSelection();
    }

    private NoteFontMapping? lastFontMapping;
    public void RefreshTypography()
    {
        type = NoteTypography.For(app.Preferences.TextSize);
        var font = fonts.Resolve(app.Preferences.Font);
        if (lastFontMapping != font)
        {
            lastFontMapping = font;
            app.Log.Info($"便签字体 {app.Preferences.Font}：{font.Family}；标题 {font.TitleWeight}；可用 {font.Available}。");
        }
        state.Typography = type;
        state.Font = new(font.Family);
        state.TitleWeight = (FontWeight)new FontWeightConverter().ConvertFromString(font.TitleWeight)!;
        state.Refresh();
        foreach (var row in itemRows.Values)
        {
            row.State.Typography = type;
            row.State.Font = state.Font;
            row.State.Refresh();
        }
        Place();
    }

    public void RefreshTheme() => UpdateSelection();
    private Note Current() => app.Repository.GetNote(note.Id) ?? throw new InvalidOperationException("便签已删除。");
    public void RemoveAnimated()
    {
        removing = true;
        ReleaseEditors();
        if (IsVisible) Animate(true);
        else Close();
    }

    public void CloseForImport()
    {
        removing = true;
        presentationGeneration++;
        foreach (var property in new[] { LeftProperty, TopProperty, WidthProperty, HeightProperty, OpacityProperty })
            BeginAnimation(property, null);
        ReleaseEditors();
        Close();
    }

    public void ReleaseEditors()
    {
        app.Editors.Remove(title);
        foreach (var row in itemRows.Values) app.Editors.Remove(row.Editor);
    }
}
