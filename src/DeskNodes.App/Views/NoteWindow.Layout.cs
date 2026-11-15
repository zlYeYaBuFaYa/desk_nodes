using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using DeskNodes.App.Interop;
using DeskNodes.App.Platform;
using DeskNodes.Core.Domain;
using DeskNodes.Core.Presentation;

namespace DeskNodes.App.Views;

internal sealed partial class NoteWindow
{
    public RectD Bounds
    {
        get
        {
            if (!initialized) return RestoreTarget().Bounds;
            nint handle = new WindowInteropHelper(this).Handle;
            var screen = app.Screens.GetScreens().Resolve(ScreenProvider.DeviceForWindow(handle));
            var origin = PointToScreen(new Point(0, 0));
            return new(origin.X / screen.DpiScale, origin.Y / screen.DpiScale, ActualWidth, ActualHeight);
        }
    }

    private nint WindowMessage(nint hwnd, int message, nint wParam, nint lParam, ref bool handled)
    {
        // 移动或调整大小结束时保存位置与尺寸。
        if (message == NativeMethods.WM_EXITSIZEMOVE && !placing) app.Run(() => SaveBounds(true));
        // WM_SIZING 区分手动调整大小与仅移动窗口。
        if (message == NativeMethods.WM_SIZING) manuallySized = true;
        if (message == NativeMethods.WM_ACTIVATEAPP)
        {
            applicationActive = wParam != 0;
            UpdateSelection();
            if (!applicationActive && !app.Editors.HasComposition)
            {
                if (levels is not null) levels.TemporarilyRaised = false;
                levels?.Apply(true);
            }
        }
        app.Screens.NotifyWindowMessage(message);
        return 0;
    }

    private bool manuallySized;
    private bool applicationActive = true;
    private void Drag(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState != MouseButtonState.Pressed || app.Editors.HasComposition || note.Placement.DockEdge is not null) return;
        DragMove();
        app.Run(() => SaveBounds(false));
        e.Handled = true;
    }

    private void SaveBounds(bool fromSystem)
    {
        if (note.Collapsed || note.Placement.DockEdge is not null) return;
        var screen = app.Screens.GetScreens().Resolve(ScreenProvider.DeviceForWindow(new WindowInteropHelper(this).Handle));
        var rect = Bounds.Fit(screen.WorkArea.Inset(8));
        app.Update(app.Repository.GetNote(note.Id)!, placement: new(new(rect.X - screen.Bounds.X, rect.Y - screen.Bounds.Y, rect.Width, rect.Height), screen.DeviceHint), automatic: fromSystem && manuallySized ? false : null);
        manuallySized = false;
    }

    private (ScreenInfo Screen, RectD Bounds) RestoreTarget()
    {
        var screens = app.Screens.GetScreens();
        var screen = screens.Resolve(note.Placement.DisplayDeviceHint);
        var placement = NoteLayout.Restore(note.Placement, screens);
        var r = placement.Bounds;
        RectD target = new(screen.Bounds.X + r.X, screen.Bounds.Y + r.Y, r.Width, r.Height);
        if (placement.DockEdge is { } edge)
        {
            var dock = DockLayout.Arrange(screen, edge, app.Repository.GetNotes().Where(n => n.Placement.DockEdge == edge && screens.Resolve(n.Placement.DisplayDeviceHint).Id == screen.Id).Select(n => new DockItem(n.Id, n.Placement.DockOrder ?? 0, n.Collapsed ? 32 : n.Placement.Bounds.Height)), ToolbarGeometry.Home(screens, screen, app.Preferences.Home).HitZone);
            var entry = dock.Visible.FirstOrDefault(n => n.Id == note.Id);
            if (entry is not null) target = entry.Bounds;
        }
        return (screen, new(target.X, target.Y, target.Width, note.Collapsed ? 32 : target.Height));
    }

    public void Place()
    {
        placing = true;
        try
        {
            var (screen, target) = RestoreTarget();
            MinWidth = Math.Min(200, screen.WorkArea.Width);
            MaxWidth = Math.Min(400, screen.WorkArea.Width);
            MinHeight = note.Collapsed ? 32 : Math.Min(120, screen.WorkArea.Height);
            MaxHeight = Math.Max(MinHeight, Math.Min(600, screen.WorkArea.Height));
            Left = target.X;
            Top = target.Y;
            Width = target.Width;
            Height = target.Height;
            if (initialized)
                NativeMethods.SetWindowPos(new WindowInteropHelper(this).Handle, 0,
                    (int)Math.Round(target.X * screen.DpiScale), (int)Math.Round(target.Y * screen.DpiScale),
                    (int)Math.Round(target.Width * screen.DpiScale), (int)Math.Round(Height * screen.DpiScale),
                    NativeMethods.NoActivate | NativeMethods.NoZOrder | NativeMethods.NoOwnerZOrder);
        }
        finally
        {
            placing = false;
        }
        MeasureHeight();
    }

    private void MeasureHeight()
    {
        if (placing || manuallySized || !note.AutomaticHeight || note.Collapsed || note.Placement.DockEdge is not null || Width <= 0) return;
        rows.Measure(new Size(Math.Max(1, Width - 36), double.PositiveInfinity));
        var screen = app.Screens.GetScreens().Resolve(initialized ? ScreenProvider.DeviceForWindow(new WindowInteropHelper(this).Handle) : note.Placement.DisplayDeviceHint);
        var bounds = Bounds;
        double height = type.AutomaticHeight(rows.DesiredSize.Height, screen.WorkArea.Height);
        placing = true;
        try
        {
            Height = height;
            if (initialized)
            {
                double top = Math.Clamp(bounds.Y, screen.WorkArea.Y + 8, Math.Max(screen.WorkArea.Y + 8, screen.WorkArea.Bottom - 8 - height));
                NativeMethods.SetWindowPos(new WindowInteropHelper(this).Handle, 0,
                    (int)Math.Round(bounds.X * screen.DpiScale), (int)Math.Round(top * screen.DpiScale),
                    (int)Math.Round(Width * screen.DpiScale), (int)Math.Round(height * screen.DpiScale),
                    NativeMethods.NoActivate | NativeMethods.NoZOrder | NativeMethods.NoOwnerZOrder);
            }
        }
        finally
        {
            placing = false;
        }
    }

    private void HeaderDrag(object sender, MouseButtonEventArgs e)
    {
        if (e.OriginalSource == sender) Drag(sender, e);
    }

    private void Animate(bool delete)
    {
        bool reduced = app.Preferences.ReduceMotion || !NativeMethods.SystemParametersInfo(NativeMethods.SPI_GETCLIENTAREAANIMATION, 0, out int enabled, 0) || enabled == 0;
        var duration = TimeSpan.FromSeconds(reduced ? .12 : delete ? .18 : .20);
        var fade = new DoubleAnimation(delete ? 1 : 0, delete ? 0 : 1, duration);
        if (delete) fade.Completed += (_, _) =>
        {
            removing = true;
            Close();
        };
        BeginAnimation(OpacityProperty, fade);
        if (!reduced)
        {
            var scale = new ScaleTransform(1, 1);
            shell.RenderTransformOrigin = new(.5, .5);
            shell.RenderTransform = scale;
            scale.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(delete ? 1 : .97, delete ? .97 : 1, duration));
            scale.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(delete ? 1 : .97, delete ? .97 : 1, duration));
        }
    }
}
