using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows.Threading;
using DeskNodes.App.Interop;
using DeskNodes.Core.Domain;
using DeskNodes.Core.Presentation;
using Microsoft.Win32;

namespace DeskNodes.App.Platform;

internal sealed class ScreenProvider : IDisposable
{
    private readonly Dispatcher dispatcher = Dispatcher.CurrentDispatcher;
    public event EventHandler? Changed;
    public ScreenProvider()
    {
        SystemEvents.DisplaySettingsChanged += OnChanged;
        SystemEvents.UserPreferenceChanged += OnPreferenceChanged;
    }
    private void OnPreferenceChanged(object sender, UserPreferenceChangedEventArgs e) => OnChanged(sender, e);
    private void OnChanged(object? sender, EventArgs e) => dispatcher.BeginInvoke(() => Changed?.Invoke(this, EventArgs.Empty));
    public void NotifyWindowMessage(int message)
    {
        if (message is NativeMethods.WM_DISPLAYCHANGE or NativeMethods.WM_SETTINGCHANGE)
            Changed?.Invoke(this, EventArgs.Empty);
    }
    public ScreenSet GetScreens()
    {
        var screens = new List<ScreenInfo>();
        if (!NativeMethods.EnumDisplayMonitors(0, 0, (nint monitor, nint dc, ref NativeMethods.Rect rect, nint data) =>
        {
            var info = new NativeMethods.MonitorInfo { Size = (uint)Marshal.SizeOf<NativeMethods.MonitorInfo>(), Device = "" };
            if (!NativeMethods.GetMonitorInfo(monitor, ref info))
                return true;
            double scale = NativeMethods.GetDpiForMonitor(monitor, NativeMethods.MDT_EFFECTIVE_DPI, out uint dpi, out _) == 0 ? dpi / 96d : 1;
            RectD Convert(NativeMethods.Rect r) => new(r.Left / scale, r.Top / scale, (r.Right - r.Left) / scale, (r.Bottom - r.Top) / scale);
            screens.Add(new(info.Device, info.Device, Convert(info.Monitor), Convert(info.Work), (info.Flags & NativeMethods.MONITORINFOF_PRIMARY) != 0, scale)
            {
                PixelBounds = new(info.Monitor.Left, info.Monitor.Top,
                    info.Monitor.Right - info.Monitor.Left, info.Monitor.Bottom - info.Monitor.Top)
            });
            return true;
        }, 0))
            throw new Win32Exception(Marshal.GetLastWin32Error());
        return new(screens);
    }
    public static string DeviceForWindow(nint handle)
    {
        var info = new NativeMethods.MonitorInfo { Size = (uint)Marshal.SizeOf<NativeMethods.MonitorInfo>(), Device = "" };
        return NativeMethods.GetMonitorInfo(NativeMethods.MonitorFromWindow(handle, NativeMethods.MONITOR_DEFAULTTONEAREST), ref info) ? info.Device : "";
    }
    public void Dispose()
    {
        SystemEvents.DisplaySettingsChanged -= OnChanged;
        SystemEvents.UserPreferenceChanged -= OnPreferenceChanged;
    }
}
