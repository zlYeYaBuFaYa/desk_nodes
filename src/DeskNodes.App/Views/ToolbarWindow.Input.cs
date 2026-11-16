using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using DeskNodes.App.Interop;
using DeskNodes.Core.Domain;
using DeskNodes.Core.Presentation;

namespace DeskNodes.App.Views;

internal partial class ToolbarWindow
{
    private static PointD Pointer()
    {
        NativeMethods.GetCursorPos(out var point);
        return new(point.X, point.Y);
    }
    private static bool OnButton(DependencyObject? element)
    {
        while (element is not null)
        {
            if (element is Button) return true;
            element = element is ContentElement content ? ContentOperations.GetParent(content) : VisualTreeHelper.GetParent(element);
        }
        return false;
    }
    private bool resumeInterrupted;
    private void Down(object sender, MouseButtonEventArgs e)
    {
        if (!round && grip?.IsMouseOver != true) return;
        resumeInterrupted = animating;
        frames.Stop();
        entranceHit.IsOpen = false;
        animating = false;
        Place(Bounds);
        generation++;
        pressed = true;
        dragging = false;
        downPixels = Pointer();
        safe = Bounds;
        safeScreen = screen;
        grabOffset = new(downPixels.X / screen.DpiScale - safe.X, downPixels.Y / screen.DpiScale - safe.Y);
        CaptureMouse();
        dragWatch.Start();
        Tick();
        e.Handled = true;
    }
    private void Move(object sender, MouseEventArgs e)
    {
        if (!pressed) return;
        var point = Pointer();
        dragging |= ToolbarRules.IsDrag((point.X - downPixels.X) / screen.DpiScale, (point.Y - downPixels.Y) / screen.DpiScale);
        if (!dragging) return;
        var screens = app.Screens.GetScreens();
        screen = screens.At(point) ?? screen;
        if (round)
        {
            var home = ToolbarGeometry.ProjectHome(screens, screen, point);
            projected = home.Position;
            Place(home.Entrance);
        }
        else
        {
            var target = new RectD(point.X / screen.DpiScale - grabOffset.X, point.Y / screen.DpiScale - grabOffset.Y, safe.Width, safe.Height);
            Place(ToolbarGeometry.Release(screens, point, screen.Id, target, app.Preferences.Anchor?.Edge).Bounds);
        }
    }
    private void Up(object sender, MouseButtonEventArgs e)
    {
        if (!pressed) return;
        bool moved = dragging;
        pressed = false;
        dragging = false;
        dragWatch.Stop();
        ReleaseMouseCapture();
        bool saved = true;
        if (moved)
        {
            if (round && projected is not null) saved = app.SavePreferences(app.Preferences with { Home = projected });
            else
            {
                var placement = ToolbarGeometry.Release(app.Screens.GetScreens(), Pointer(), screen.Id, Bounds, app.Preferences.Anchor?.Edge);
                saved = app.SavePreferences(app.Preferences with { Anchor = ToolbarRules.Anchor(placement) });
            }
        }
        if (!saved)
        {
            RestoreStable();
            e.Handled = true;
            return;
        }
        UpdateEntranceHit();
        Tick(clicked: !moved, completed: moved && idle.State == ToolbarIdleState.Collapsing, completedGeneration: idle.Generation);
        e.Handled = true;
    }
    private void CancelDrag()
    {
        if (!pressed) return;
        pressed = dragging = false;
        dragWatch.Stop();
        screen = safeScreen;
        Place(safe);
        ReleaseMouseCapture();
        UpdateEntranceHit();
        if (resumeInterrupted)
        {
            resumeInterrupted = false;
            var resume = idle.ResumeAnimation();
            if (resume.Action != ToolbarIdleAction.None)
            {
                animating = true;
                Transition(resume.Action, resume.Generation);
            }
            else
                Tick();
        }
        else
            Tick();
    }
}
