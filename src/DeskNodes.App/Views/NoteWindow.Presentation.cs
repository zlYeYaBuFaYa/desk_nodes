using System.Windows;
using System.Windows.Media.Animation;
using System.Windows.Automation;
using System.Windows.Interop;
using DeskNodes.App.Interop;
using DeskNodes.Core.Domain;

namespace DeskNodes.App.Views;
internal sealed partial class NoteWindow
{
    private long presentationGeneration;
    public void ArrangeFrom(RectD previous)
    {
        if (app.Animations.ReducedMotion) return;
        var target = RestoreTarget().Bounds;
        var duration = TimeSpan.FromSeconds(.26);
        foreach (var entry in new[] { (LeftProperty, previous.X, target.X), (TopProperty, previous.Y, target.Y),
            (WidthProperty, previous.Width, target.Width), (HeightProperty, previous.Height, target.Height) })
        {
            BeginAnimation(entry.Item1, new DoubleAnimation(entry.Item2, entry.Item3, duration)
            {
                FillBehavior = FillBehavior.Stop,
                EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut }
            });
        }
    }
    public RectD PixelBounds
    {
        get
        {
            NativeMethods.GetWindowRect(new WindowInteropHelper(this).Handle, out var r);
            return new(r.Left, r.Top, Math.Max(0, r.Right - r.Left), Math.Max(0, r.Bottom - r.Top));
        }
    }
    public void SetMultiSelection(bool active, bool picked)
    {
        state.Picked = picked;
        layout.IsHitTestVisible = !active;
        title.IsReadOnly = active;
        foreach (var row in itemRows.Values) row.Editor.IsReadOnly = active;
        ResizeMode = active ? ResizeMode.NoResize : ResizeMode.CanResize;
        state.Refresh();
        AutomationProperties.SetName(this, $"{note.Title}，{(picked ? "已勾选" : "未勾选")}");
    }
    public void Present(bool collapse, RectD entrance, double seconds, Action completed)
    {
        long generation = ++presentationGeneration;
        var restore = RestoreTarget().Bounds;
        var from = new RectD(Left, Top, ActualWidth > 0 ? ActualWidth : Width, ActualHeight > 0 ? ActualHeight : Height);
        double opacity = Opacity;
        foreach (var property in new[] { LeftProperty, TopProperty, WidthProperty, HeightProperty, OpacityProperty }) BeginAnimation(property, null);
        Place();
        var target = collapse ? entrance : restore;
        if (!collapse && !IsVisible) from = entrance;
        bool reduced = app.Animations.ReducedMotion;
        if (reduced)
        {
            completed();
            return;
        }
        MinWidth = MinHeight = 1;
        MaxWidth = MaxHeight = double.PositiveInfinity;
        Show();
        var duration = TimeSpan.FromSeconds(seconds);
        void AnimateProperty(DependencyProperty property, double start, double end) => BeginAnimation(property, new DoubleAnimation(start, end, duration) { FillBehavior = FillBehavior.HoldEnd, EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut } });
        AnimateProperty(LeftProperty, from.X, target.X);
        AnimateProperty(TopProperty, from.Y, target.Y);
        AnimateProperty(WidthProperty, from.Width, target.Width);
        AnimateProperty(HeightProperty, from.Height, target.Height);
        var fade = new DoubleAnimation(collapse ? opacity : 0, collapse ? 0 : 1, duration);
        fade.Completed += (_, _) =>
        {
            if (generation != presentationGeneration) return;
            if (collapse) Hide();
            foreach (var property in new[] { LeftProperty, TopProperty, WidthProperty, HeightProperty, OpacityProperty }) BeginAnimation(property, null);
            Opacity = 1;
            Place();
            completed();
        };
        BeginAnimation(OpacityProperty, fade);
    }
}
