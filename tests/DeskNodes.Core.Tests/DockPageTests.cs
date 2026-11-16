using DeskNodes.Core.Domain;
using DeskNodes.Core.Presentation;

namespace DeskNodes.Core.Tests;

public sealed class DockPageTests
{
    [Theory]
    [InlineData(DockEdge.Left)]
    [InlineData(DockEdge.Right)]
    [InlineData(DockEdge.Top)]
    public void PageLookupFindsNotesAcrossPagesWithHomeZone(DockEdge edge)
    {
        var screen = new ScreenInfo("screen", "screen", new(0, 0, 1000, 800), new(0, 0, 1000, 800));
        var items = Enumerable.Range(0, 12).Select(i => new DockItem(NoteId.New(), 11 - i, 120 + i * 25)).ToArray();
        var home = new RectD(0, 0, 64, 64);
        var layout = DockLayout.Arrange(screen, edge, items, home);
        Assert.True(layout.PageCount > 1);
        foreach (var item in items)
        {
            int? page = DockLayout.PageForNote(layout, item.Id);
            Assert.NotNull(page);
            Assert.Contains(DockLayout.Arrange(screen, edge, items, home, page.Value).Visible, n => n.Id == item.Id);
        }
        Assert.Null(DockLayout.PageForNote(layout, NoteId.New()));
    }

    [Theory]
    [InlineData(119)]
    [InlineData(120)]
    [InlineData(121)]
    [InlineData(128)]
    [InlineData(148)]
    [InlineData(215)]
    [InlineData(216)]
    [InlineData(239)]
    [InlineData(240)]
    public void NarrowStripReservesNoteMinimumBeforeLabel(double available)
    {
        foreach (var edge in Enum.GetValues<DockEdge>())
        foreach (int count in new[] { 1, 3 })
        foreach (bool reserve in new[] { false, true })
        {
            double width = edge == DockEdge.Top && !reserve ? available + 16 : 800;
            double height = edge != DockEdge.Top && !reserve ? available + 16 : 800;
            var screen = new ScreenInfo("s", "s", new(0, 0, width, height), new(0, 0, width, height));
            var items = Enumerable.Range(0, count).Select(i => new DockItem(NoteId.New(), i)).ToArray();
            RectD? home = reserve ? edge == DockEdge.Top
                ? new(available + 20, 0, 800, 800)
                : new(0, available + 20, 800, 800) : null;
            var layout = DockLayout.Arrange(screen, edge, items, home);
            foreach (var item in items)
            {
                int page = Assert.IsType<int>(DockLayout.PageForNote(layout, item.Id));
                var shown = DockLayout.Arrange(screen, edge, items, home, page);
                var bounds = Assert.Single(shown.Visible, note => note.Id == item.Id).Bounds;
                double length = edge == DockEdge.Top ? bounds.Width : bounds.Height;
                if (count > 1) Assert.NotNull(shown.OverflowBounds);
                Assert.True(length >= Math.Min(120, available));
                if (shown.OverflowBounds is { } label)
                {
                    Assert.True(label.Width > 0 && label.Height > 0);
                    double labelLength = edge == DockEdge.Top ? label.Width : label.Height;
                    Assert.Equal(available < 216 ? Math.Min(96, available / 2) : 96, labelLength);
                    if (available < 216) Assert.True(labelLength <= length / 2);
                    Assert.Equal(available < 216, bounds.Intersects(label));
                }
            }
        }
    }

    [Fact]
    public void EmptyHasNoPageButTinyReservedAreaStillMapsNotes()
    {
        var screen = new ScreenInfo("tiny", "tiny", new(0, 0, 50, 50), new(0, 0, 50, 50));
        var item = new DockItem(NoteId.New(), 0);
        Assert.Null(DockLayout.PageForNote(DockLayout.Arrange(screen, DockEdge.Left, []), item.Id));
        var layout = DockLayout.Arrange(screen, DockEdge.Left, [item], new(0, 0, 50, 50));
        Assert.Equal(0, DockLayout.PageForNote(layout, item.Id));
        Assert.Contains(layout.Visible, n => n.Id == item.Id && n.Bounds.Height > 0);
    }
    [Theory]
    [InlineData(800, 600, false)]
    [InlineData(800, 600, true)]
    [InlineData(50, 50, true)]
    [InlineData(20, 20, false)]
    [InlineData(10, 10, true)]
    public void OversizedNotesRemainReachableAndFitAvailableStrip(double width, double height, bool reserve)
    {
        var screen = new ScreenInfo("s", "s", new(0, 0, width, height), new(0, 0, width, height));
        var items = new[] { new DockItem(NoteId.New(), 0, 500), new DockItem(NoteId.New(), 1, 500) };
        RectD? home = reserve ? new(0, 0, 64, 300) : null;
        foreach (var edge in Enum.GetValues<DockEdge>())
        {
            var layout = DockLayout.Arrange(screen, edge, items, home);
            foreach (var id in layout.Overflow)
                Assert.NotNull(DockLayout.PageForNote(layout, id));
            foreach (var item in items)
            {
                int page = Assert.IsType<int>(DockLayout.PageForNote(layout, item.Id));
                var shown = DockLayout.Arrange(screen, edge, items, home, page);
                var entry = Assert.Single(shown.Visible, n => n.Id == item.Id);
                Assert.True(entry.Bounds.Width > 0 && entry.Bounds.Height > 0);
                Assert.Equal(entry.Bounds, entry.Bounds.Fit(screen.WorkArea));
                if (shown.OverflowBounds is { } label)
                {
                    double length = edge == DockEdge.Top ? screen.WorkArea.Width - 16 : screen.WorkArea.Height - 16;
                    Assert.Equal(length <= 120, entry.Bounds.Intersects(label));
                }
            }
        }
    }
    [Fact]
    public void TwoFiveHundredDipNotesUseSeparatePagesWithScrollableHeight()
    {
        var screen = new ScreenInfo("s", "s", new(0, 0, 800, 600), new(0, 0, 800, 600));
        var items = new[] { new DockItem(NoteId.New(), 0, 500), new DockItem(NoteId.New(), 1, 500) };
        var first = DockLayout.Arrange(screen, DockEdge.Left, items);
        Assert.Equal(2, first.PageCount);
        Assert.Equal(new RectD(8, 8, 288, 488), Assert.Single(first.Visible).Bounds);
        var second = DockLayout.Arrange(screen, DockEdge.Left, items, page: 1);
        Assert.Equal(items[1].Id, Assert.Single(second.Visible).Id);
    }
}
