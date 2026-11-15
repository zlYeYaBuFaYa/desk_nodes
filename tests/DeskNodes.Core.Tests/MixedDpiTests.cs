using DeskNodes.Core.Domain;
using DeskNodes.Core.Presentation;

namespace DeskNodes.Core.Tests;

public sealed class MixedDpiTests
{
    private static (ScreenInfo Left, ScreenInfo Right, ScreenSet Screens) ConnectedScreens()
    {
        var left = new ScreenInfo("left", "left", new(0, 0, 1920, 1080), new(0, 0, 1920, 1040), true);
        var right = new ScreenInfo("right", "right", new(1280, 0, 1280, 720), new(1280, 0, 1280, 680), false, 1.5)
        {
            PixelBounds = new(1920, 0, 1920, 1080)
        };
        return (left, right, new([left, right]));
    }

    [Fact]
    public void PhysicalSeamIsInternalEvenThoughDipRectanglesOverlap()
    {
        var (left, right, screens) = ConnectedScreens();
        Assert.True(left.Bounds.Intersects(right.Bounds));
        Assert.False(screens.IsOuter(left, ScreenEdge.Right));
        Assert.False(screens.IsOuter(right, ScreenEdge.Left));
        Assert.True(screens.IsOuter(left, ScreenEdge.Left));
        Assert.True(screens.IsOuter(right, ScreenEdge.Right));
    }

    [Theory]
    [InlineData(1919, 700, "left")]
    [InlineData(1920, 700, "right")]
    [InlineData(3000, 900, "right")]
    public void PointerOwnershipUsesPhysicalPixels(double x, double y, string expected)
    {
        var (_, _, screens) = ConnectedScreens();
        Assert.Equal(expected, screens.At(new(x, y))?.Id);
        Assert.Equal(expected, screens.For(new(x, y, 1, 1)).Id);
    }

    [Fact]
    public void ReleaseUsesPointerScreenAndNeverSnapsToItsInternalSeam()
    {
        var (_, right, screens) = ConnectedScreens();
        var result = ToolbarGeometry.Release(screens, new(2000, 900), "left", new(1288, 250, 64, 296));
        Assert.Equal(right, result.Screen);
        Assert.Null(result.Edge);
        Assert.Equal(new RectD(1288, 250, 64, 296), result.Bounds);
        Assert.Equal(right, ToolbarGeometry.Release(screens, new(9000, 0), "right", result.Bounds).Screen);
    }

    [Fact]
    public void FreeAnchorConvertsPixelCenterToDestinationDipAndNewNoteAvoidsFullTarget()
    {
        var (_, right, screens) = ConnectedScreens();
        var preferences = new LocalPreferences { Anchor = new(new PointD(2028, 234)) };
        var target = ToolbarGeometry.ResolveAnchor(screens, preferences, ToolbarOrientation.Vertical, false);
        Assert.Equal(right, ToolbarGeometry.AnchorScreen(screens, preferences));
        Assert.Equal(new RectD(1320, 8, 64, 296), target);
        var note = NoteLayout.New(screens, right.Id, target, [], new(288, 240));
        Assert.False(note.Intersects(target));
        Assert.True(note.X >= right.WorkArea.X);
        Assert.True(note.Right <= right.WorkArea.Right);
        Assert.True(note.Bottom <= right.WorkArea.Bottom);
        // A home entrance alone would leave the expanded target unprotected.
        var home = ToolbarGeometry.Home(screens, right, preferences.Home);
        Assert.True(NoteLayout.New(screens, right.Id, home.HitZone, [], new(288, 240)).Intersects(target));
    }

    [Fact]
    public void HomeProjectionConvertsPixelPointerBeforeComputingDipRatio()
    {
        var (_, right, screens) = ConnectedScreens();
        var projected = ToolbarGeometry.ProjectHome(screens, right, new(3830, 510));
        Assert.Equal(ScreenEdge.Right, projected.Position.Edge);
        Assert.Equal(.5, projected.Position.Ratio, 8);
        Assert.Equal(340, projected.Entrance.Center.Y, 8);
    }

    [Fact]
    public void EdgeAnchorRetainsScreenAcrossPreferenceRoundTripAndFallsBackWhenOffline()
    {
        using var directory = new TestDirectory();
        var store = new LocalPreferencesStore(new SilentLog(), directory.DirectoryPath);
        var anchor = new ToolbarAnchor(Edge: ScreenEdge.Right, DeviceHint: "right");
        store.Save(new()
        {
            Anchor = anchor
        });
        var preferences = store.Load();
        Assert.Equal(anchor, preferences.Anchor);
        var (left, right, screens) = ConnectedScreens();
        Assert.Equal(right, ToolbarGeometry.AnchorScreen(screens, preferences));
        var target = ToolbarGeometry.ResolveAnchor(screens, preferences, ToolbarOrientation.Vertical, true);
        Assert.Equal(right.WorkArea.Right - 8, target.Right);
        Assert.Equal(324, target.Height);
        Assert.Equal(left, ToolbarGeometry.AnchorScreen(new([left]), preferences));
    }

    private sealed class SilentLog : DeskNodes.Core.Services.IDeskNodesLog
    {
        public void Info(string message)
        {
        }
        public void Warn(string message)
        {
        }
        public void Error(string message, Exception exception) => throw new InvalidOperationException(message, exception);
    }
}
