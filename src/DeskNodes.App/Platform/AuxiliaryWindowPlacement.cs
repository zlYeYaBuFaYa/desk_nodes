using System.Windows;
using System.Windows.Interop;
using DeskNodes.App.Interop;
using DeskNodes.Core.Domain;

namespace DeskNodes.App.Platform;

internal static class AuxiliaryWindowPlacement
{
    public static void Position(Window window, ScreenProvider provider, double contentWidth, double contentHeight, double minimumWidth = 0)
    {
        var screens = provider.GetScreens();
        var screen = NativeMethods.GetCursorPos(out var pointer)
            ? screens.At(new PointD(pointer.X, pointer.Y)) ?? screens.Primary : screens.Primary;
        var work = screen.WorkArea;
        double frameHeight = SystemParameters.WindowCaptionHeight + 2 * SystemParameters.ResizeFrameHorizontalBorderHeight;
        window.MinWidth = Math.Min(minimumWidth, work.Width);
        window.MinHeight = Math.Min(contentHeight + frameHeight, work.Height);
        window.Width = Math.Min(contentWidth + 2 * SystemParameters.ResizeFrameVerticalBorderWidth, work.Width);
        window.Height = Math.Min(contentHeight + frameHeight, work.Height);
        double left = work.X + (work.Width - window.Width) / 2;
        double top = work.Y + (work.Height - window.Height) / 2;
        var handle = new WindowInteropHelper(window).EnsureHandle();
        NativeMethods.SetWindowPos(handle, 0,
            (int)Math.Round(left * screen.DpiScale), (int)Math.Round(top * screen.DpiScale),
            (int)Math.Round(window.Width * screen.DpiScale), (int)Math.Round(window.Height * screen.DpiScale),
            NativeMethods.NoZOrder | NativeMethods.NoActivate | NativeMethods.NoOwnerZOrder);
    }
}
