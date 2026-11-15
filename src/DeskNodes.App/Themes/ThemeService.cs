using System.Windows;
using System.Windows.Threading;
using DeskNodes.Core.Presentation;
using Microsoft.Win32;

namespace DeskNodes.App.Themes;

internal sealed class ThemeService : IDisposable
{
    private readonly Func<Appearance> appearance;
    private readonly Dispatcher dispatcher;
    private ThemeState state;
    private readonly ResourceDictionary resources;
    private ResourceDictionary? palette;
    private ResourceDictionary? contrast;
    public bool EffectiveDark => state.EffectiveDark;
    public bool TransparencyEnabled => state.TransparencyEnabled;
    public bool HighContrast => state.HighContrast;
    public bool SolidFallback => state.SolidFallback;
    public event EventHandler? Changed;
    public ThemeService(Func<Appearance> appearance, Dispatcher dispatcher, ResourceDictionary resources)
    {
        this.resources = resources;
        this.appearance = appearance;
        this.dispatcher = dispatcher;
        Refresh();
        SystemEvents.UserPreferenceChanged += OnPreferenceChanged;
        SystemParameters.StaticPropertyChanged += OnSystemParametersChanged;
    }
    private void OnPreferenceChanged(object sender, UserPreferenceChangedEventArgs e) => dispatcher.BeginInvoke(Refresh);
    private void OnSystemParametersChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e) => dispatcher.BeginInvoke(Refresh);
    public void Refresh()
    {
        const string path = @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";
        var next = ThemeRules.Resolve(appearance(), Registry.GetValue(path, "AppsUseLightTheme", 1) is int light && light == 0,
            Registry.GetValue(path, "EnableTransparency", 0) is int enabled && enabled != 0, SystemParameters.HighContrast, SystemParameters.IsRemoteSession);
        if (state == next && palette is not null)
            return;
        state = next;
        if (palette is not null)
            resources.MergedDictionaries.Remove(palette);
        if (contrast is not null)
            resources.MergedDictionaries.Remove(contrast);
        palette = new ResourceDictionary { Source = new Uri(next.EffectiveDark ? "Themes/Dark.xaml" : "Themes/Light.xaml", UriKind.Relative) };
        resources.MergedDictionaries.Add(palette);
        contrast = next.HighContrast ? new ResourceDictionary { Source = new Uri("Themes/HighContrast.xaml", UriKind.Relative) } : null;
        if (contrast is not null)
            resources.MergedDictionaries.Add(contrast);
        Changed?.Invoke(this, EventArgs.Empty);
    }
    public void Dispose()
    {
        SystemEvents.UserPreferenceChanged -= OnPreferenceChanged;
        SystemParameters.StaticPropertyChanged -= OnSystemParametersChanged;
    }
}
