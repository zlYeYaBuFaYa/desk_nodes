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

    [Fact]
    public void EmptyAndUnplaceableNotesHaveNoPage()
    {
        var screen = new ScreenInfo("tiny", "tiny", new(0, 0, 50, 50), new(0, 0, 50, 50));
        var item = new DockItem(NoteId.New(), 0);
        Assert.Null(DockLayout.PageForNote(DockLayout.Arrange(screen, DockEdge.Left, []), item.Id));
        Assert.Null(DockLayout.PageForNote(DockLayout.Arrange(screen, DockEdge.Left, [item], new(0, 0, 50, 50)), item.Id));
    }
}
