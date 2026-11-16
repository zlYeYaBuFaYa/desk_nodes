using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using DeskNodes.App.Interop;
using DeskNodes.Core.Domain;
using DeskNodes.Core.Presentation;
using DeskNodes.Core.Services;

namespace DeskNodes.App.Views;

// Bind a semantic key while letting WPF update the brush when the application palette changes.
public static class HistoryResources
{
    public static readonly DependencyProperty BackgroundKeyProperty = DependencyProperty.RegisterAttached(
        "BackgroundKey", typeof(string), typeof(HistoryResources), new PropertyMetadata(null, BackgroundKeyChanged));
    public static string? GetBackgroundKey(DependencyObject target) => (string?)target.GetValue(BackgroundKeyProperty);
    public static void SetBackgroundKey(DependencyObject target, string? value) => target.SetValue(BackgroundKeyProperty, value);
    private static void BackgroundKeyChanged(DependencyObject target, DependencyPropertyChangedEventArgs e)
    {
        if (target is Border border)
            border.SetResourceReference(Border.BackgroundProperty, e.NewValue as string ?? "HistoryWeak");
    }
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
    public HistoryWindow(AppCoordinator app)
    {
        this.app = app;
        model = new(app);
        InitializeComponent();
        DataContext = model;
        Activated += (_, _) => Reload();
        Closed += (_, _) => model.Invalidate();
    }
    internal void RefreshTheme() => Reload();
    private void PositionAtPointer() => Platform.AuxiliaryWindowPlacement.Position(this, app.Screens,
        (double)FindResource("HistoryContentWidth"), (double)FindResource("HistoryContentHeight"),
        (double)FindResource("HistoryMinimumWidth"));
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
