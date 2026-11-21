using System.Windows;
using System.ComponentModel;
using System.Windows.Input;
using System.Windows.Interop;
using DeskNodes.App.Interop;
using DeskNodes.Core.Domain;
using DeskNodes.Core.Presentation;

namespace DeskNodes.App.Views;
internal sealed class OverlayViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    public double Left { get; set; }
    public double Top { get; set; }
    public double Width { get; set; }
    public double Height { get; set; }
    public Visibility Visibility { get; set; } = Visibility.Collapsed;
    public void Refresh() => PropertyChanged?.Invoke(this, new(null));
}
internal partial class SelectionOverlay : Window
{
    private readonly OverlayViewModel model = new();
    private readonly PresentationCoordinator presentation;
    private readonly ScreenInfo screen;
    public SelectionOverlay(PresentationCoordinator presentation, ScreenInfo screen)
    {
        this.presentation = presentation;
        this.screen = screen;
        InitializeComponent();
        DataContext = model;
        Left = screen.Bounds.X;
        Top = screen.Bounds.Y;
        Width = screen.Bounds.Width;
        Height = screen.Bounds.Height;
        SourceInitialized += (_, _) => NativeMethods.SetWindowPos(new WindowInteropHelper(this).Handle, NativeMethods.Topmost,
            (int)screen.PixelBounds.X, (int)screen.PixelBounds.Y, (int)screen.PixelBounds.Width, (int)screen.PixelBounds.Height, NativeMethods.NoActivate);
        PreviewMouseLeftButtonDown += (_, e) => presentation.BeginBox(this, null, e);
        PreviewMouseMove += (_, e) => presentation.MoveBox(e);
        PreviewMouseLeftButtonUp += (_, e) => presentation.EndBox(e);
        PreviewKeyDown += (_, e) => presentation.Keys(e);
    }
    public void Draw(RectD? pixels)
    {
        model.Visibility = pixels is null ? Visibility.Collapsed : Visibility.Visible;
        if (pixels is { } r)
        {
            model.Left = r.X / screen.DpiScale - screen.Bounds.X;
            model.Top = r.Y / screen.DpiScale - screen.Bounds.Y;
            model.Width = r.Width / screen.DpiScale;
            model.Height = r.Height / screen.DpiScale;
        }
        model.Refresh();
    }
}
