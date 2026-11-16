using DeskNodes.Core.Domain;
using DeskNodes.Core.Presentation;

namespace DeskNodes.Core.Tests;

public sealed class LayoutInteractionTests
{
    private static readonly ScreenInfo Screen = new("s", "s", new(0, 0, 638, 600), new(0, 0, 638, 600));
    private static Note Note(int order, double height) => new(NoteId.New(), "", NoteColor.Paper, order,
        new(new(0, 0, 288, height), "s"), NoteLevel.Back, null, false, false, TestData.Now, TestData.Now);

    [Fact]
    public void ObstacleAdjustedColumnsUseRemainingSpaceBeforeNewPage()
    {
        var result = Arranger.Arrange(new([Screen]), [Note(0, 120), Note(1, 400)], (_, _) => 0,
            new(328, 22, 64, 296), "s");
        Assert.All(result.Notes, n => Assert.Equal(0, n.Page));
        Assert.Equal(new RectD(22, 160, 288, 400), result.Notes[1].Bounds);
    }

    [Fact]
    public void ObstacleAcrossColumnsUsesLeftTieThenRightAndOnlyThenNewPage()
    {
        var result = Arranger.Arrange(new([Screen]), [Note(0, 240), Note(1, 240), Note(2, 240)], (_, _) => 0,
            new(22, 22, 594, 200), "s");
        Assert.Equal(new RectD(22, 240, 288, 240), result.Notes[0].Bounds);
        Assert.Equal(new RectD(328, 240, 288, 240), result.Notes[1].Bounds);
        Assert.Equal(0, result.Notes[1].Page);
        Assert.Equal(1, result.Notes[2].Page);
        Assert.Equal(2, result.PageCounts["s"]);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void CapturingMovedPlacementStoresScreenRelativePositionAndExpandedSize(bool collapsed)
    {
        var screen = new ScreenInfo("other", "device", new(-1200, -100, 1200, 900), new(-1200, -100, 1200, 860));
        var previous = new Placement(new(20, 30, 320, 480), "old");
        var captured = NoteLayout.Capture(previous, new(-1100, 50, 288, collapsed ? 32 : 240), screen, collapsed);
        Assert.Equal("device", captured.DisplayDeviceHint);
        Assert.Equal(new RectD(100, 150, collapsed ? 320 : 288, collapsed ? 480 : 240), captured.Bounds);
        Assert.Null(captured.DockEdge);
    }

    [Fact]
    public void CollapsedMovementClampsVisibleHeaderWithoutClampingExpandedSize()
    {
        var captured = NoteLayout.Capture(new(new(0, 0, 320, 480), "s"), new(620, 590, 320, 32), Screen, true);
        Assert.Equal(new RectD(310, 560, 320, 480), captured.Bounds);
        Assert.Equal(captured, NoteLayout.Restore(captured, new([Screen]), collapsed: true));
    }
}
