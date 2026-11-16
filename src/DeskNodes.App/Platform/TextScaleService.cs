using System.Windows;
using System.Windows.Threading;
using Windows.UI.ViewManagement;

namespace DeskNodes.App.Platform;

// Windows text size is independent of monitor DPI. Keep all WPF updates on its Dispatcher.
internal sealed class TextScaleService : IDisposable
{
    private readonly Dispatcher dispatcher;
    private readonly ResourceDictionary resources;
    private UISettings? settings;
    private bool disposed;
    public double Scale { get; private set; } = 1;
    public event EventHandler? Changed;

    public TextScaleService(Dispatcher dispatcher, ResourceDictionary resources)
    {
        this.dispatcher = dispatcher;
        this.resources = resources;
        try
        {
            settings = new UISettings();
            settings.TextScaleFactorChanged += TextScaleChanged;
        }
        catch (Exception)
        {
            settings = null;
        }
        Refresh();
    }

    private void TextScaleChanged(UISettings sender, object args)
        => dispatcher.BeginInvoke(Refresh);

    private void Refresh()
    {
        if (disposed)
            return;
        double scale;
        try
        {
            scale = settings?.TextScaleFactor ?? 1;
        }
        catch (Exception)
        {
            scale = 1;
        }
        Scale = double.IsFinite(scale) && scale > 0 ? scale : 1;
        foreach (var size in new[] { 10, 11, 12, 14, 18, 20, 24, 32 })
            resources[$"TextSize{size}"] = size * Scale;
        foreach (int length in new[] { 24, 28, 32, 36, 52, 60, 64, 68 })
            resources[$"ToolbarLength{length}"] = length * Math.Max(1, Scale);
        resources["StackHintHeight"] = Math.Max(44, 14 + 16 * Scale);
        Changed?.Invoke(this, EventArgs.Empty);
    }

    public void Dispose()
    {
        disposed = true;
        if (settings is not null)
            settings.TextScaleFactorChanged -= TextScaleChanged;
    }
}
