using DeskNodes.Core.Presentation;
using DeskNodes.Core.Domain;

namespace DeskNodes.Core.Tests;

public sealed class ToolbarRulesTests
{
    [Theory]
    [InlineData(3.99, 3.99, false)]
    [InlineData(4, 0, true)]
    [InlineData(0, -4, true)]
    [InlineData(-5, 1, true)]
    public void DragUsesMaximumAxisAndIncludesThreshold(double x, double y, bool expected) =>
        Assert.Equal(expected, ToolbarRules.IsDrag(x, y));

    [Fact]
    public void SpringSettlesWithinHalfSecondAndHasSmallOvershoot()
    {
        Assert.Equal(0, ToolbarRules.Spring(0));
        var samples = Enumerable.Range(0, 501).Select(i => ToolbarRules.Spring(i / 1000d)).ToArray();
        Assert.InRange(samples.Max(), 1.02, 1.04);
        Assert.InRange(ToolbarRules.Spring(.499), .99, 1.01);
        Assert.Equal(1, ToolbarRules.Spring(.5));
        Assert.Equal(1, ToolbarRules.Spring(10));
    }

    [Fact]
    public void ControlsWaitThenStaggerAndFinishAtFinalCoordinates()
    {
        Assert.Equal(0, ToolbarRules.ControlProgress(.079, 0));
        Assert.Equal(0, ToolbarRules.ControlProgress(.107, 1));
        Assert.InRange(ToolbarRules.ControlProgress(.19, 0), .499, .501);
        Assert.Equal(1, ToolbarRules.ControlProgress(.44, 5), 12);
    }

    [Theory]
    [InlineData(0, false)]
    [InlineData(1, true)]
    [InlineData(100, true)]
    public void EmptyLibraryDisablesManagement(int count, bool enabled) => Assert.Equal(enabled, ToolbarRules.CanManage(count));

    [Theory]
    [InlineData(true, null, 0, 0, false)]
    [InlineData(false, null, 3, 0, true)]
    [InlineData(false, 1, 3, 1, true)]
    [InlineData(false, 0, 3, 1, false)]
    [InlineData(false, 2, 2, 3, true)]
    public void VisibilityKeepsNewNotesAndClampsEachScreen(bool collapsed, int? page, int shared, int last, bool expected) =>
        Assert.Equal(expected, ToolbarRules.IsVisible(collapsed, page, shared, last));

    [Fact]
    public void ReleasedAnchorsRoundTripAtMixedDpi()
    {
        var screen = new ScreenInfo("right", "device", new(1000, 0, 1000, 800), new(1000, 0, 1000, 760), false, 1.5);
        var screens = new ScreenSet([screen]);
        var bounds = new RectD(1928, 200, 64, 296);
        var anchor = ToolbarRules.Anchor(new(screen, bounds, ScreenEdge.Right));
        Assert.Equal("device", anchor.DeviceHint);
        var resolved = ToolbarGeometry.ResolveAnchor(screens, new() { Anchor = anchor }, ToolbarOrientation.Vertical, false);
        Assert.Equal(bounds, resolved);
        var free = ToolbarRules.Anchor(new(screen, bounds, null));
        Assert.Equal(new PointD(bounds.Center.X * 1.5, bounds.Center.Y * 1.5), free.Center);
        Assert.Equal(bounds, ToolbarGeometry.ResolveAnchor(screens, new() { Anchor = free }, ToolbarOrientation.Vertical, false));
    }

    [Theory]
    [InlineData(ToolbarOrientation.Vertical, ScreenEdge.Bottom)]
    [InlineData(ToolbarOrientation.Vertical, ScreenEdge.Right)]
    [InlineData(ToolbarOrientation.Horizontal, ScreenEdge.Right)]
    [InlineData(ToolbarOrientation.Horizontal, ScreenEdge.Top)]
    public void ExpandedHomePreservesTheHandleEntrance(ToolbarOrientation orientation, ScreenEdge edge)
    {
        var screen = new ScreenInfo("a", "a", new(0, 0, 1000, 800), new(0, 0, 1000, 760), true);
        var home = ToolbarGeometry.Home(new([screen]), screen, new(edge));
        var full = ToolbarGeometry.Expand(home, screen.WorkArea, orientation, false);
        Assert.Equal(home.Entrance, ToolbarRules.HandleRound(full, orientation, edge));
    }

    [Theory]
    [InlineData(ToolbarOrientation.Vertical, ScreenEdge.Bottom)]
    [InlineData(ToolbarOrientation.Horizontal, ScreenEdge.Right)]
    public void MorphFrameIncludesTheSpringOvershoot(ToolbarOrientation orientation, ScreenEdge edge)
    {
        var screen = new ScreenInfo("a", "a", new(0, 0, 1000, 800), new(0, 0, 1000, 760), true);
        var home = ToolbarGeometry.Home(new([screen]), screen, new(edge));
        var start = home.Entrance;
        var end = ToolbarGeometry.Expand(home, screen.WorkArea, orientation, false);
        var frame = ToolbarRules.AnimationFrame(start, end);
        for (int i = 0; i <= 500; i++)
        {
            double progress = ToolbarRules.Spring(i / 1000d);
            double x = start.X + (end.X - start.X) * progress;
            double y = start.Y + (end.Y - start.Y) * progress;
            double right = x + start.Width + (end.Width - start.Width) * progress;
            double bottom = y + start.Height + (end.Height - start.Height) * progress;
            Assert.True(x >= frame.X && y >= frame.Y && right <= frame.Right && bottom <= frame.Bottom);
        }
    }
}
