using System.ComponentModel;
using System.Windows;
using System.Windows.Interop;
using DeskNodes.App.Interop;
using DeskNodes.Core.Domain;
using DeskNodes.Core.Presentation;

namespace DeskNodes.App.Views;

internal sealed class BarModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    public string Message { get; set; } = "";
    public string ActionText { get; set; } = "";
    public bool CanAct { get; set; } = true;
    public string ActionHelp => CanAct ? ActionText : "尚未选择便签，删除不可用";
    public void Refresh() => PropertyChanged?.Invoke(this, new(null));
}
internal partial class PresentationBar : Window
{
    private readonly Action act;
    private readonly Action selectAll;
    private readonly Action finish;
    public BarModel Model { get; } = new();
    public PresentationBar(bool selection, Action act, Action? selectAll = null, Action? finish = null)
    {
        InitializeComponent();
        DataContext = Model;
        this.act = act;
        this.selectAll = selectAll ?? (() => { });
        this.finish = finish ?? (() => { });
        all.Visibility = done.Visibility = selection ? Visibility.Visible : Visibility.Collapsed;
        SourceInitialized += (_, _) =>
        {
            var hwnd = new WindowInteropHelper(this).Handle;
            NativeMethods.SetWindowLongPtr(hwnd, NativeMethods.GWL_EXSTYLE, NativeMethods.GetWindowLongPtr(hwnd, NativeMethods.GWL_EXSTYLE) | NativeMethods.WS_EX_TOOLWINDOW | NativeMethods.WS_EX_NOACTIVATE);
        };
    }
    public void Place(RectD bounds)
    {
        Left = bounds.X;
        Top = bounds.Y;
        Width = bounds.Width;
        Height = bounds.Height;
    }
    public void PlaceError(RectD workArea)
    {
        SizeToContent = SizeToContent.Height;
        MinHeight = Math.Min(44, workArea.Height);
        MaxHeight = Math.Min(72, workArea.Height);
        Width = Math.Min(360, workArea.Width);
        var content = (FrameworkElement)Content;
        content.Measure(new Size(Width, double.PositiveInfinity));
        var bounds = PresentationRules.Prompt(workArea, Width, Math.Clamp(content.DesiredSize.Height, MinHeight, MaxHeight), 80);
        Left = bounds.X;
        Top = bounds.Y;
        Show();
        UpdateLayout();
        bounds = PresentationRules.Prompt(workArea, Width, ActualHeight, 80);
        Left = bounds.X;
        Top = bounds.Y;
    }
    public void HideAction() => action.Visibility = Visibility.Collapsed;
    private void All(object sender, RoutedEventArgs e) => selectAll();
    private void Act(object sender, RoutedEventArgs e) => act();
    private void Done(object sender, RoutedEventArgs e) => finish();
}
