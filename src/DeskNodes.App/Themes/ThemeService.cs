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
    public bool EffectiveDark => state.EffectiveDark;
    public bool TransparencyEnabled => state.TransparencyEnabled;
    public bool HighContrast => state.HighContrast;
    public bool SolidFallback => state.SolidFallback;
    public event EventHandler? Changed;
    public ThemeService(Func<Appearance> appearance, Dispatcher dispatcher)
    {
        this.appearance = appearance;
        this.dispatcher = dispatcher;
        Refresh();
        SystemEvents.UserPreferenceChanged += OnPreferenceChanged;
    }
    private void OnPreferenceChanged(object sender, UserPreferenceChangedEventArgs e) => dispatcher.BeginInvoke(Refresh);
    public void Refresh()
    {
        const string path = @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";
        var next = ThemeRules.Resolve(appearance(), Registry.GetValue(path, "AppsUseLightTheme", 1) is int light && light == 0,
            Registry.GetValue(path, "EnableTransparency", 0) is int enabled && enabled != 0, SystemParameters.HighContrast, SystemParameters.IsRemoteSession);
        if (state == next) return;
        state = next;
        Changed?.Invoke(this, EventArgs.Empty);
    }
    public void Dispose() => SystemEvents.UserPreferenceChanged -= OnPreferenceChanged;
}
