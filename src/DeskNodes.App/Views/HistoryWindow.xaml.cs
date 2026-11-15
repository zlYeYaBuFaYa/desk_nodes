using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Interop;
using DeskNodes.App.Interop;
using DeskNodes.App.Themes;
using DeskNodes.Core.Domain;
using DeskNodes.Core.Presentation;
using DeskNodes.Core.Services;

namespace DeskNodes.App.Views;

public sealed class HistoryBrushConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) => (value is string key ? Application.Current?.TryFindResource(key) as Brush : null)
        ?? Application.Current?.TryFindResource("HistoryWeak") as Brush
        ?? SystemColors.WindowBrush;
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => throw new NotSupportedException();
}
public static class HistoryCommands
{
    public static RoutedUICommand Restore { get; } = new();
    public static RoutedUICommand SelectDay { get; } = new();
    public static RoutedUICommand Previous { get; } = new();
    public static RoutedUICommand Next { get; } = new();
    public static RoutedUICommand Today { get; } = new();
    public static RoutedUICommand Retry { get; } = new();
}

internal partial class HistoryWindow : Window
{
    private readonly AppCoordinator app;
    private readonly HistoryViewModel model;
    private readonly ThemeService theme;
    public HistoryWindow(AppCoordinator app)
    {
        this.app = app;
        model = new(app);
        InitializeComponent();
        DataContext = model;
        Activated += (_, _) => Reload();
        theme = new(() => app.Preferences.Appearance, Dispatcher);
        theme.Changed += ThemeChanged;
        ApplyPalette();
        Closed += (_, _) =>
        {
            theme.Changed -= ThemeChanged;
            theme.Dispose();
        };
    }
    private void ThemeChanged(object? sender, EventArgs e)
    {
        ApplyPalette();
        Reload();
    }
    private void ApplyPalette()
    {
        string[] roles = ["Background", "Weak", "Selected", "Progress", "Track", "Foreground", "Secondary",
            "OnSelected", "CarryForeground", "CarryBackground", "Transparent"];
        var keys = roles.Select(role => "History" + role)
            .Concat(Enum.GetValues<NoteColor>().Select(HistoryRules.ColorKey));
        foreach (string key in keys)
        {
            object? brush = TryFindResource(key + (theme.EffectiveDark ? "Dark" : "Light"));
            if (theme.HighContrast)
                brush = key == "HistoryTransparent" ? TryFindResource("HistoryTransparentLight")
                    : key is "HistorySelected" or "HistoryProgress" ? SystemColors.HighlightBrush
                    : key == "HistoryOnSelected" ? SystemColors.HighlightTextBrush
                    : key is "HistoryForeground" or "HistorySecondary" or "HistoryCarryForeground" ? SystemColors.WindowTextBrush
                    : SystemColors.WindowBrush;
            if (brush is Brush)
                Application.Current.Resources[key] = brush;
        }
    }
    internal void RefreshTheme()
    {
        theme.Refresh();
        ApplyPalette();
        Reload();
    }
    private void PositionAtPointer()
    {
        var screens = app.Screens.GetScreens();
        var screen = NativeMethods.GetCursorPos(out var pointer)
            ? screens.At(new PointD(pointer.X, pointer.Y)) ?? screens.Primary : screens.Primary;
        var work = screen.WorkArea;
        double contentHeight = (double)FindResource("HistoryContentHeight");
        double frameHeight = SystemParameters.WindowCaptionHeight + 2 * SystemParameters.ResizeFrameHorizontalBorderHeight;
        MinWidth = Math.Min((double)FindResource("HistoryMinimumWidth"), work.Width);
        MinHeight = Math.Min(contentHeight + frameHeight, work.Height);
        Width = Math.Min((double)FindResource("HistoryContentWidth") + 2 * SystemParameters.ResizeFrameVerticalBorderWidth, work.Width);
        Height = Math.Min(contentHeight + frameHeight, work.Height);
        double left = work.X + (work.Width - Width) / 2;
        double top = work.Y + (work.Height - Height) / 2;
        var handle = new WindowInteropHelper(this).EnsureHandle();
        NativeMethods.SetWindowPos(handle, 0,
            (int)Math.Round(left * screen.DpiScale), (int)Math.Round(top * screen.DpiScale),
            (int)Math.Round(Width * screen.DpiScale), (int)Math.Round(Height * screen.DpiScale),
            NativeMethods.NoZOrder | NativeMethods.NoActivate | NativeMethods.NoOwnerZOrder);
    }
    public void Open(HistoryDay? day, bool deleted)
    {
        if (!IsVisible)
            PositionAtPointer();
        if (day is { } selected)
            model.Navigator.Select(selected);
        DeletedSegment.IsChecked = deleted;
        CalendarSegment.IsChecked = !deleted;
        Reload();
        Show();
        if (WindowState == WindowState.Minimized)
            WindowState = WindowState.Normal;
        Activate();
        if (!deleted)
            Focus();
    }
    private bool IsDeleted => DeletedSegment.IsChecked == true;
    internal void Reload() => model.Reload(IsDeleted);
    private void SegmentChanged(object sender, RoutedEventArgs e)
    {
        if (CalendarPane is null || DeletedPane is null)
            return;
        CalendarPane.Visibility = IsDeleted ? Visibility.Collapsed : Visibility.Visible;
        DeletedPane.Visibility = IsDeleted ? Visibility.Visible : Visibility.Collapsed;
        Reload();
    }
    private void Previous(object sender, ExecutedRoutedEventArgs e)
    {
        model.Navigator.MoveMonth(-1);
        Reload();
    }
    private void Next(object sender, ExecutedRoutedEventArgs e)
    {
        model.Navigator.MoveMonth(1);
        Reload();
    }
    private void Today(object sender, ExecutedRoutedEventArgs e)
    {
        model.Navigator.Today();
        Reload();
    }
    private void Retry(object sender, ExecutedRoutedEventArgs e) => Reload();
    private void SelectDay(object sender, ExecutedRoutedEventArgs e)
    {
        if (e.Parameter is not HistoryDay day)
            return;
        model.Navigator.Select(day);
        Focus();
        Reload();
    }
    private void Navigate(object sender, KeyEventArgs e)
    {
        bool control = Keyboard.Modifiers == ModifierKeys.Control;
        var focus = Keyboard.FocusedElement;
        if (!HistoryRules.HandlesNavigation(!IsDeleted, focus is TextBoxBase, focus is Control && focus != this, control))
            return;
        if (Keyboard.Modifiers != ModifierKeys.None && !control)
            return;
        if (control)
        {
            if (e.Key == Key.Left)
                model.Navigator.MoveMonth(-1);
            else if (e.Key == Key.Right)
                model.Navigator.MoveMonth(1);
            else if (e.Key == Key.T)
                model.Navigator.Today();
            else
                return;
        }
        else
        {
            if (e.Key == Key.Left)
                model.Navigator.MoveDay(-1);
            else if (e.Key == Key.Right)
                model.Navigator.MoveDay(1);
            else if (e.Key == Key.Up)
                model.Navigator.MoveWeek(-1);
            else if (e.Key == Key.Down)
                model.Navigator.MoveWeek(1);
            else
                return;
        }
        e.Handled = true;
        Reload();
    }
    private void Restore(object sender, ExecutedRoutedEventArgs e)
    {
        if (e.Parameter is DeletedEntryView entry)
            app.RestoreDeleted(entry.Entry);
    }
}
