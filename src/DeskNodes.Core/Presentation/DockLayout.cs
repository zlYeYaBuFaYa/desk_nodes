using DeskNodes.Core.Domain;

namespace DeskNodes.Core.Presentation;

public sealed record DockItem(NoteId Id, int Order, double Height = 240);
public sealed record DockedNote(NoteId Id, RectD Bounds);
public sealed record DockResult(IReadOnlyList<DockedNote> Visible, IReadOnlyList<NoteId> Overflow, int Page, int PageCount, RectD? OverflowBounds)
{
    public IReadOnlyDictionary<NoteId, int> Pages { get; init; } = new Dictionary<NoteId, int>();
}
public static class DockLayout
{
    public static DockResult Arrange(ScreenInfo screen, DockEdge edge, IEnumerable<DockItem> items,
        RectD? homeZone = null, int page = 0)
    {
        var w = screen.WorkArea.Inset(Math.Min(8, Math.Min(screen.WorkArea.Width, screen.WorkArea.Height) / 4));
        bool top = edge == DockEdge.Top;
        double start = top ? w.X : w.Y, end = top ? w.Right : w.Bottom;
        double cross = top ? Math.Min(screen.WorkArea.Height < 700 ? 200 : 260, w.Height) : Math.Min(288, w.Width);
        if (homeZone is { } zone)
        {
            var strip = top ? new RectD(w.X, w.Y, w.Width, cross) : new RectD(edge == DockEdge.Left ? w.X : w.Right - cross, w.Y, cross, w.Height);
            if (strip.Intersects(zone))
            {
                double before = Math.Clamp((top ? zone.X : zone.Y) - 12, start, end);
                double after = Math.Clamp((top ? zone.Right : zone.Bottom) + 12, start, end);
                if (before - start >= end - after) end = before; else start = after;
            }
        }
        var ordered = items.OrderBy(i => i.Order).ToArray();
        double Length(DockItem i) => top ? Math.Min(220, w.Width) : Math.Min(Math.Clamp(i.Height, 120, 600), w.Height);
        // If the reservation consumes the entire strip, keep notes reachable on the strip.
        if (end <= start)
        {
            start = top ? w.X : w.Y;
            end = top ? w.Right : w.Bottom;
        }
        double available = end - start;
        bool overflow = ordered.Sum(i => Length(i) + 12) - 12 > available;
        double overflowLength = Math.Min(96, Math.Max(0, available - Math.Min(120, available / 2)));
        RectD? overflowBounds = overflow
            ? top ? new(end - overflowLength, w.Y, overflowLength, cross)
                : new(edge == DockEdge.Left ? w.X : w.Right - cross, end - overflowLength, cross, overflowLength)
            : null;
        if (overflow) available = Math.Max(0, available - overflowLength);
        var groups = new List<List<DockItem>> { new() };
        double used = 0;
        foreach (var item in ordered)
        {
            double length = Math.Min(Length(item), available);
            if (groups[^1].Count > 0 && used + length > available)
            {
                groups.Add(new());
                used = 0;
            }
            groups[^1].Add(item);
            used += length + 12;
        }
        page = Math.Clamp(page, 0, groups.Count - 1);
        var visible = new List<DockedNote>();
        double cursor = start;
        foreach (var item in groups[page])
        {
            double length = Math.Min(Length(item), available);
            visible.Add(new(item.Id, top ? new(cursor, w.Y, length, cross) : new(edge == DockEdge.Left ? w.X : w.Right - cross, cursor, cross, length)));
            cursor += length + 12;
        }
        var ids = visible.Select(v => v.Id).ToHashSet();
        return new(visible.AsReadOnly(), Array.AsReadOnly(ordered.Where(i => !ids.Contains(i.Id)).Select(i => i.Id).ToArray()), page, groups.Count, overflowBounds)
        {
            Pages = groups.SelectMany((group, index) => group.Select(item => (item.Id, Page: index)))
                .ToDictionary(item => item.Id, item => item.Page)
        };
    }
    public static int? PageForNote(DockResult layout, NoteId id) =>
        layout.Pages.TryGetValue(id, out int page) ? page : null;

    public static bool ShouldDetach(DockEdge edge, RectD workArea, PointD pointer) => edge switch
    {
        DockEdge.Left => pointer.X > workArea.X + 288 + 48,
        DockEdge.Right => pointer.X < workArea.Right - 288 - 48,
        _ => pointer.Y > workArea.Y + (workArea.Height < 700 ? 200 : 260) + 48
    };
}
public static class CollapseGeometry
{
    public static string? Badge(int count) => count <= 0 ? null : count > 99 ? "99+" : count.ToString(System.Globalization.CultureInfo.InvariantCulture);
    public static RectD Target(RectD toolbar, RectD workArea, int index)
    {
        // 24×32 DIP miniature sheets, offset by 3 DIP for at most three visible layers.
        int layer = Math.Clamp(index, 0, 2);
        double x = toolbar.Right + 8 + layer * 3;
        if (x + 24 > workArea.Right) x = toolbar.X - 8 - 24 - layer * 3;
        return new RectD(x, toolbar.Center.Y - 16 + layer * 3, 24, 32).Fit(workArea);
    }
}
