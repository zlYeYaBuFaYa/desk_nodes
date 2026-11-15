using System.Windows.Interop;
using DeskNodes.App.Interop;

namespace DeskNodes.App.Platform;

/// <summary>An invisible top-level window receives broadcasts that message-only windows cannot receive.</summary>
internal sealed class SystemServiceWindow : IDisposable
{
    private readonly AppCoordinator app;
    private readonly HwndSource source;
    private readonly uint taskbarCreated = NativeMethods.RegisterWindowMessage("TaskbarCreated");
    private TimeZoneInfo timeZone = TimeZoneInfo.Local;
    public nint Handle => source.Handle;
    public SystemServiceWindow(AppCoordinator app)
    {
        this.app = app;
        source = new HwndSource(new HwndSourceParameters("DeskNodes.SystemServices")
        {
            Width = 0,
            Height = 0,
            WindowStyle = 0,
            ExtendedWindowStyle = NativeMethods.WS_EX_TOOLWINDOW | NativeMethods.WS_EX_NOACTIVATE,
            ParentWindow = 0
        });
        source.AddHook(Hook);
    }
    public bool RefreshTimeZone()
    {
        TimeZoneInfo.ClearCachedData();
        var next = TimeZoneInfo.Local;
        bool changed = next.Id != timeZone.Id || !next.HasSameRules(timeZone);
        timeZone = next;
        return changed;
    }
    private nint Hook(nint window, int message, nint wParam, nint lParam, ref bool handled)
    {
        try
        {
            if (message == NativeMethods.WM_HOTKEY)
            {
                app.Hotkeys.Dispatch((int)wParam);
                handled = true;
            }
            else if ((uint)message == taskbarCreated)
                app.RebuildTray();
            else if (message == NativeMethods.WM_POWERBROADCAST)
            {
                if ((int)wParam == NativeMethods.PBT_APMSUSPEND)
                    app.Editors.TryCommitPending();
                else if ((int)wParam is NativeMethods.PBT_APMRESUMEAUTOMATIC or NativeMethods.PBT_APMRESUMESUSPEND)
                {
                    app.ResetIdle();
                    app.CheckSystemDay();
                }
            }
            else if (message == NativeMethods.WM_TIMECHANGE)
                app.CheckSystemDay();
            else if (message == NativeMethods.WM_SETTINGCHANGE)
            {
                app.Animations.Refresh();
                ((App)System.Windows.Application.Current).RefreshAppearance();
                app.Screens.NotifyWindowMessage(message);
                if (RefreshTimeZone())
                    app.CheckSystemDay();
                app.ResetIdle();
            }
            else if (message == NativeMethods.WM_DISPLAYCHANGE)
                app.Screens.NotifyWindowMessage(message);
        }
        catch (Exception exception)
        {
            app.Log.Error("系统消息处理失败，将在下次检查重试。", exception);
        }
        return 0;
    }
    public void Dispose()
    {
        source.RemoveHook(Hook);
        source.Dispose();
    }
}
