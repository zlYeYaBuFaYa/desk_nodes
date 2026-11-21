using DeskNodes.Core.Domain;

namespace DeskNodes.Core.Presentation;

public static class NoteLayout
{
    public static SizeD Constrain(SizeD size, RectD workArea, bool automaticHeight = false)
    {
        var safe = workArea.Inset(8);
        return new(Math.Min(safe.Width, Math.Clamp(size.Width, 200, 400)),
            Math.Min(safe.Height, Math.Clamp(size.Height, 120, automaticHeight ? 480 : 600)));
    }

    public static double ClampedTop(double top, double height, RectD workArea)
    {
        var safe = workArea.Inset(8);
        return Math.Clamp(top, safe.Y, Math.Max(safe.Y, safe.Bottom - height));
    }
    public static SizeD NewSize(LocalPreferences preferences, RectD workArea, Func<double, double> measure)
    {
        var p = preferences.Normalize();
        double width = Constrain(new(p.NewWidth, 240), workArea).Width;
        return Constrain(new(width, p.NewHeight == 0 ? measure(width) : p.NewHeight), workArea, p.NewHeight == 0);
    }
    public static RectD New(ScreenSet screens, string? preferredScreen, RectD fullToolbarTarget,
        IEnumerable<RectD> displayed, SizeD? requestedSize = null)
    {
        var w = screens.Resolve(preferredScreen).WorkArea.Inset(8);
        var size = Constrain(requestedSize ?? new(288, 240), screens.Resolve(preferredScreen).WorkArea);
        var visible = displayed.ToArray();
        var occupied = visible.Append(fullToolbarTarget).ToArray();
        // Obstacle edges form a compact, deterministic search; no pixel-by-pixel scan.
        var xs = occupied.Select(r => r.Right + 8).Append(w.X).Distinct().Order().ToArray();
        var ys = occupied.Select(r => r.Bottom + 8).Append(w.Y).Distinct().Order().ToArray();
        foreach (double y in ys)
        foreach (double x in xs)
        {
            var candidate = new RectD(x, y, size.Width, size.Height);
            if (candidate.X >= w.X && candidate.Y >= w.Y && candidate.Right <= w.Right && candidate.Bottom <= w.Bottom && !occupied.Any(candidate.Intersects)) return candidate;
        }
        // A 24 DIP cascade keeps title bars distinguishable; wrap when either axis fills.
        int steps = Math.Max(1, (int)(Math.Min(w.Width - size.Width, w.Height - size.Height) / 24) + 1);
        double offset = visible.Length % steps * 24;
        return new RectD(w.X + offset, w.Y + offset, size.Width, size.Height).Fit(w);
    }
    public static Placement Capture(Placement previous, RectD visibleBounds, ScreenInfo screen, bool collapsed)
    {
        var visible = visibleBounds.Fit(screen.WorkArea.Inset(8));
        var size = collapsed ? previous.Bounds : visible;
        return new(new(visible.X - screen.Bounds.X, visible.Y - screen.Bounds.Y, size.Width, size.Height), screen.DeviceHint);
    }

    public static Placement Restore(Placement placement, ScreenSet screens, bool collapsed = false)
    {
        var screen = screens.Resolve(placement.DisplayDeviceHint);
        var r = placement.Bounds;
        // Persisted placement is monitor-relative, never a virtual-screen pixel coordinate.
        var global = new RectD(screen.Bounds.X + r.X, screen.Bounds.Y + r.Y, r.Width, collapsed ? 32 : r.Height).Fit(screen.WorkArea.Inset(8));
        return new(new(global.X - screen.Bounds.X, global.Y - screen.Bounds.Y, collapsed ? r.Width : global.Width, collapsed ? r.Height : global.Height),
            screen.DeviceHint, placement.DockEdge, placement.DockOrder);
    }
}

public sealed record ArrangedNote(NoteId Id, string ScreenId, RectD Bounds, SizeD ExpandedSize, int Page)
{
    public Placement ToPlacement(ScreenInfo screen) => new(new(Bounds.X - screen.Bounds.X, Bounds.Y - screen.Bounds.Y,
        ExpandedSize.Width, ExpandedSize.Height), screen.DeviceHint);
}
public sealed record Arrangement(IReadOnlyList<ArrangedNote> Notes, IReadOnlyDictionary<string, int> PageCounts)
{
    public int PageFor(string screenId, int sharedPage) => Math.Clamp(sharedPage, 0, Math.Max(0, PageCounts.GetValueOrDefault(screenId, 1) - 1));
}
public static class Arranger
{
    public static Arrangement Arrange(ScreenSet screens, IEnumerable<Note> notes, Func<Note, double, double> measure,
        RectD? fullToolbarTarget = null, string? toolbarScreen = null)
    {
        var input = notes.ToArray();
        var result = new List<ArrangedNote>();
        var pages = new Dictionary<string, int>();
        foreach (var screen in screens.Screens)
        {
            var area = screen.WorkArea.Inset(22);
            double width = Math.Min(288, area.Width);
            int count = Math.Max(1, (int)((area.Width + 18) / (288 + 18)));
            var bottoms = Enumerable.Repeat(area.Y, count).ToArray();
            int page = 0;
            bool pageUsed = false;
            foreach (var note in input.Where(n => screens.Resolve(n.Placement.DisplayDeviceHint).Id == screen.Id).OrderBy(n => n.SortOrder))
            {
                double expanded = Math.Min(area.Height, Math.Clamp(note.AutomaticHeight ? measure(note, width) : note.Placement.Bounds.Height,
                    120, note.AutomaticHeight ? 480 : 600));
                double height = note.Collapsed ? Math.Min(32, area.Height) : expanded;
                double NextY(int column)
                {
                    double start = bottoms[column];
                    double columnX = area.X + column * 306;
                    if (toolbarScreen == screen.Id && fullToolbarTarget is { } obstacle && new RectD(columnX, start, width, height).Intersects(obstacle))
                        return obstacle.Bottom + 18;
                    return start;
                }
                int AvailableColumn() => Enumerable.Range(0, count)
                    .Where(column => NextY(column) + height <= area.Bottom)
                    .OrderBy(NextY).ThenBy(column => column).DefaultIfEmpty(-1).First();
                int col = AvailableColumn();
                if (col < 0)
                {
                    if (pageUsed) page++;
                    Array.Fill(bottoms, area.Y);
                    col = AvailableColumn();
                }
                // An obstacle covering every column cannot be avoided even on an empty page.
                double y = col < 0 ? area.Y : NextY(col);
                if (col < 0) col = 0;
                double x = area.X + col * 306;
                result.Add(new(note.Id, screen.Id, new(x, y, width, height), new(width, expanded), page));
                bottoms[col] = y + height + 18;
                pageUsed = true;
            }
            pages[screen.Id] = page + 1;
        }
        return new(result.AsReadOnly(), pages);
    }
}
