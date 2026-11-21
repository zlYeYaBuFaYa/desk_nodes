using System.Runtime.InteropServices;

namespace DeskNodes.App.Interop;

internal static partial class NativeMethods
{
    internal const int WM_HOTKEY = 0x0312, WM_POWERBROADCAST = 0x0218, WM_TIMECHANGE = 0x001E, WM_IME_ENDCOMPOSITION = 0x010E;
    internal const int PBT_APMSUSPEND = 0x0004, PBT_APMRESUMESUSPEND = 0x0007, PBT_APMRESUMEAUTOMATIC = 0x0012;
    internal const uint MOD_NOREPEAT = 0x4000;
    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool RegisterHotKey(nint window, int id, uint modifiers, uint virtualKey);
    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool UnregisterHotKey(nint window, int id);
    [LibraryImport("gdi32.dll")]
    internal static partial nint CreateRoundRectRgn(int left, int top, int right, int bottom, int ellipseWidth, int ellipseHeight);
    [LibraryImport("gdi32.dll")] [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool DeleteObject(nint value);
    [LibraryImport("user32.dll")]
    internal static partial int SetWindowRgn(nint window, nint region, [MarshalAs(UnmanagedType.Bool)] bool redraw);
    internal const int SM_CXSMICON = 49, WM_DPICHANGED = 0x02E0;
    internal const uint ABM_GETTASKBARPOS = 5;
    [StructLayout(LayoutKind.Sequential)]
    internal struct AppBarData
    {
        public uint Size;
        public nint Window;
        public uint CallbackMessage;
        public uint Edge;
        public Rect Bounds;
        public nint Parameter;
    }
    [LibraryImport("shell32.dll")]
    internal static partial nuint SHAppBarMessage(uint message, ref AppBarData data);
    [LibraryImport("user32.dll")]
    internal static partial int GetSystemMetricsForDpi(int index, uint dpi);
    internal const int VK_ESCAPE = 0x1B;
    [LibraryImport("user32.dll")]
    internal static partial short GetAsyncKeyState(int key);
    internal const uint SPI_GETSCREENREADER = 0x0046;
    internal const int WS_EX_NOACTIVATE = 0x08000000;
    internal const int DWMWA_SYSTEMBACKDROP_TYPE = 38;
    [LibraryImport("user32.dll", EntryPoint = "RegisterWindowMessageW", StringMarshalling = StringMarshalling.Utf16)]
    internal static partial uint RegisterWindowMessage(string name);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool GetCursorPos(out Point point);
    [LibraryImport("user32.dll")] internal static partial nint GetForegroundWindow();
    [LibraryImport("user32.dll")] internal static partial uint GetWindowThreadProcessId(nint window, out uint process);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static partial bool GetWindowRect(nint window, out Rect rect);
    internal const int GWL_EXSTYLE = -20;
    internal const int WS_EX_TOOLWINDOW = 0x80;
    internal const int DWMWA_WINDOW_CORNER_PREFERENCE = 33, DWMWCP_ROUND = 2;
    internal const int WM_ACTIVATEAPP = 0x1C, WM_EXITSIZEMOVE = 0x232, WM_SIZING = 0x214;
    internal const int WM_DISPLAYCHANGE = 0x7E, WM_SETTINGCHANGE = 0x1A;
    internal const uint SPI_GETCLIENTAREAANIMATION = 0x1042;
    internal const uint MONITOR_DEFAULTTONEAREST = 2, MONITORINFOF_PRIMARY = 1;
    internal const int MDT_EFFECTIVE_DPI = 0;
    internal static readonly nint Bottom = 1, Topmost = -1, NotTopmost = -2;
    internal const uint NoSize = 1, NoMove = 2, NoZOrder = 4, NoActivate = 0x10, NoOwnerZOrder = 0x200;
    [StructLayout(LayoutKind.Sequential)] internal struct Point { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] internal struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    internal struct MonitorInfo
    {
        public uint Size; public Rect Monitor, Work; public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string Device;
    }
    internal delegate bool MonitorCallback(nint monitor, nint dc, ref Rect rect, nint data);
    [LibraryImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool SetWindowPos(nint window, nint after, int x, int y, int width, int height, uint flags);
    [LibraryImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)] private static partial nint GetLong64(nint window, int index);
    [LibraryImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)] private static partial nint SetLong64(nint window, int index, nint value);
    [LibraryImport("user32.dll", EntryPoint = "GetWindowLongW", SetLastError = true)] private static partial int GetLong32(nint window, int index);
    [LibraryImport("user32.dll", EntryPoint = "SetWindowLongW", SetLastError = true)] private static partial int SetLong32(nint window, int index, int value);
    internal static nint GetWindowLongPtr(nint window, int index) => nint.Size == 8 ? GetLong64(window, index) : GetLong32(window, index);
    internal static nint SetWindowLongPtr(nint window, int index, nint value) => nint.Size == 8 ? SetLong64(window, index, value) : SetLong32(window, index, (int)value);
    [LibraryImport("user32.dll")] internal static partial nint MonitorFromWindow(nint window, uint flags);
    [LibraryImport("user32.dll")] internal static partial nint MonitorFromPoint(Point point, uint flags);
    [DllImport("user32.dll", EntryPoint = "GetMonitorInfoW", CharSet = CharSet.Unicode, SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool GetMonitorInfo(nint monitor, ref MonitorInfo info);
    [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool EnumDisplayMonitors(nint dc, nint clip, MonitorCallback callback, nint data);
    [LibraryImport("user32.dll")] internal static partial uint GetDpiForWindow(nint window);
    [LibraryImport("shcore.dll")] internal static partial int GetDpiForMonitor(nint monitor, int type, out uint x, out uint y);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static partial bool SetForegroundWindow(nint window);
    [LibraryImport("dwmapi.dll")] internal static partial int DwmSetWindowAttribute(nint window, int attribute, ref int value, int size);
    [LibraryImport("user32.dll", EntryPoint = "SystemParametersInfoW")] [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool SystemParametersInfo(uint action, uint parameter, out int value, uint flags);
    internal static void SetDwmPreference(nint window, int attribute, int value)
    {
        if (Environment.OSVersion.Version.Build >= 22621) DwmSetWindowAttribute(window, attribute, ref value, sizeof(int));
    }
}
