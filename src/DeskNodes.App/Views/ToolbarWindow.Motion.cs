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
    public void ResetIdle()
    {
        idle.ResetIdle();
        Tick();
    }
    private void Tick(bool clicked = false, bool operated = false, bool completed = false, long? completedGeneration = null)
    {
        wake.Stop();
        var home = ToolbarGeometry.Home(app.Screens.GetScreens(), screen, app.Preferences.Home);
        var entrance = round ? Bounds : ToolbarRules.HandleRound(Bounds, app.Preferences.Orientation, HandleEdge);
        var output = idle.Update(Now, new(ToolbarRules.PointerInside(IsMouseOver, entranceHit.IsMouseOver, stackHint.IsMouseOver), dragging || externalDrag, pressed, animating, app.SettingsVisible, menuOpen || app.TrayMenuOpen,
            app.Preferences.KeepToolbarExpanded || NativeMethods.SystemParametersInfo(NativeMethods.SPI_GETSCREENREADER, 0, out int reader, 0) && reader != 0, app.Preferences.AutoShrink, operated, clicked, completed,
            Math.Abs(entrance.Center.X - home.Entrance.Center.X) < 1 && Math.Abs(entrance.Center.Y - home.Entrance.Center.Y) < 1, completedGeneration));
        if (output.Action != ToolbarIdleAction.None) Transition(output.Action, output.Generation);
        if (output.NextWake is { } next)
        {
            wake.Interval = next > Now ? next - Now : TimeSpan.FromMilliseconds(1);
            wake.Start();
        }
    }
    private void Transition(ToolbarIdleAction action, long idleGeneration)
    {
        long current = ++generation;
        var screens = app.Screens.GetScreens();
        var home = ToolbarGeometry.Home(screens, screen, app.Preferences.Home);
        var start = Bounds;
        bool expand = action == ToolbarIdleAction.StartExpand;
        var entrance = start.Width <= 56 && start.Height <= 56 ? start : ToolbarRules.HandleRound(start, app.Preferences.Orientation, HandleEdge);
        var end = expand ? ToolbarGeometry.Expand(new(new(HandleEdge), entrance, entrance), screen.WorkArea, app.Preferences.Orientation, Paging, app.TextScale) : home.Entrance;
        bool fromRound = expand && !animating;
        Parts.Visibility = Visibility.Visible;
        Parts.UpdateLayout();
        var children = AnimatedParts;
        var opacityFrom = children.Select(child => fromRound ? 0 : child.Opacity).ToArray();
        var offsetFrom = children.Select(child => fromRound ? 6 : (child.RenderTransform as TranslateTransform)?.Y ?? 6).ToArray();
        bool reduce = ReducedMotion;
        var orientation = app.Preferences.Orientation;
        var handleEdge = HandleEdge;
        bool atEnd = HandleAtEnd;
        round = !expand;
        Parts.Visibility = Visibility.Visible;
        var finalSize = expand ? end : start;
        Parts.Width = Math.Max(0, finalSize.Width - Parts.Margin.Left - Parts.Margin.Right);
        Parts.Height = Math.Max(0, finalSize.Height - Parts.Margin.Top - Parts.Margin.Bottom);
        Parts.HorizontalAlignment = HorizontalAlignment.Left;
        Parts.VerticalAlignment = VerticalAlignment.Top;
        RoundLabel.Visibility = expand ? Visibility.Collapsed : Visibility.Visible;
        animationBounds = ToolbarRules.AnimationFrame(start, end);
        animating = !reduce;
        var fullSize = ToolbarGeometry.FullSize(app.Preferences.Orientation, Paging, app.TextScale);
        double fullLength = Math.Max(fullSize.Width, fullSize.Height);
        double visibleLength = Math.Max(start.Width, start.Height);
        double remaining = Math.Clamp(expand ? (fullLength - visibleLength) / Math.Max(1, fullLength - 56)
            : (visibleLength - 56) / Math.Max(1, fullLength - 56), 0, 1);
        double expansionScale = Math.Max(.16, remaining);
        double shrink = .08 + (action == ToolbarIdleAction.StartShrinkToHome ? .12 : .18) * remaining;
        double travel = action == ToolbarIdleAction.StartShrinkToHome ? ToolbarGeometry.ReturnDuration(Math.Sqrt(Math.Pow(end.X - start.X, 2) + Math.Pow(end.Y - start.Y, 2))).TotalSeconds : 0;
        duration = expand ? .5 * expansionScale : shrink + travel;
        started = Now;
        stackHint.IsOpen = false;
        entranceHit.IsOpen = false;
        frame = t =>
        {
            double p = expand ? ToolbarRules.Spring(t / expansionScale) : Math.Clamp((t - .08) / Math.Max(.001, shrink - .08), 0, 1);
            var small = ToolbarRules.HandleRound(start, orientation, handleEdge);
            RectD target = expand ? end : small;
            var r = new RectD(start.X + (target.X - start.X) * p, start.Y + (target.Y - start.Y) * p,
                start.Width + (target.Width - start.Width) * p, start.Height + (target.Height - start.Height) * p);
            if (!expand && t >= shrink)
            {
                double q = travel == 0 ? 1 : Math.Clamp((t - shrink) / travel, 0, 1);
                q = q * q * (3 - 2 * q);
                r = new(small.X + (end.X - small.X) * q, small.Y + (end.Y - small.Y) * q, 56, 56);
            }
            Place(r);
            for (int i = 0; i < children.Length; i++)
            {
                var child = children[i];
                double progress = expand ? ToolbarRules.ControlProgress(t / expansionScale, atEnd ? children.Length - 1 - i : i) : Math.Clamp(t / .08, 0, 1);
                child.Opacity = expand ? opacityFrom[i] + (1 - opacityFrom[i]) * progress : opacityFrom[i] * (1 - progress);
                child.IsHitTestVisible = ToolbarRules.PartReceivesPointer(child.Opacity);
                child.RenderTransform = new TranslateTransform(0, expand ? offsetFrom[i] * (1 - progress) : 0);
            }
        };
        bool settled = false;
        finished = () =>
        {
            if (settled || generation != current) return;
            settled = true;
            animating = false;
            Place(end);
            if (expand) ShowExpandedParts();
            else ConcealExpandedParts();
            bool saved;
            if (expand)
                saved = app.SavePreferences(app.Preferences with { Anchor = new(new(end.Center.X * screen.DpiScale, end.Center.Y * screen.DpiScale)) });
            else
            {
                var fullAtHome = ToolbarGeometry.Expand(home, screen.WorkArea, app.Preferences.Orientation, Paging, app.TextScale);
                saved = app.SavePreferences(app.Preferences with { Anchor = ToolbarRules.Anchor(new(screen, fullAtHome, home.Position.Edge)) });
            }
            if (!saved)
            {
                RestoreStable();
                return;
            }
            Rebuild();
            Tick(completed: true, completedGeneration: idleGeneration);
        };
        frames.Stop();
        if (reduce) finished();
        else frames.Start();
    }
    private void ShowExpandedParts()
    {
        Parts.Visibility = Visibility.Visible;
        foreach (UIElement child in AnimatedParts)
        {
            child.Opacity = 1;
            child.IsHitTestVisible = true;
            child.RenderTransform = Transform.Identity;
        }
    }
    private void ConcealExpandedParts()
    {
        Parts.Visibility = Visibility.Collapsed;
        foreach (UIElement child in AnimatedParts)
        {
            child.Opacity = 1;
            child.IsHitTestVisible = true;
            child.RenderTransform = Transform.Identity;
        }
    }
    private void RestoreStable() => RestoreExpanded();
    private void RenderFrame()
    {
        double elapsed = ReducedMotion ? duration : (Now - started).TotalSeconds;
        frame?.Invoke(elapsed);
        if (elapsed < duration) return;
        frames.Stop();
        finished?.Invoke();
    }
}
