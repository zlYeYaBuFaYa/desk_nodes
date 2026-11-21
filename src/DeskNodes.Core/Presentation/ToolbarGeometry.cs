using DeskNodes.Core.Domain;

namespace DeskNodes.Core.Presentation;

public enum ToolbarOrientation
{
    Vertical, Horizontal
}
public sealed record HomePosition(ScreenEdge Edge = ScreenEdge.Right, double Ratio = .4)
{
    public bool IsDefault => Edge == ScreenEdge.Right && Math.Abs(Ratio - .4) < 1e-9;
    public bool IsValid => Enum.IsDefined(Edge) && double.IsFinite(Ratio) && Ratio is >= 0 and <= 1;
}
public sealed record HomeGeometry(HomePosition Position, RectD Entrance, RectD HitZone)
{
    public RectD HomeZone => HitZone;
}
public sealed record ToolbarPlacement(ScreenInfo Screen, RectD Bounds, ScreenEdge? Edge);

public static class ToolbarGeometry
{
    public const double ShortSide = 64, Radius = 32, Inset = 6, EndCapExtra = 10, HandleLength = 24;
    public const double VerticalButtonLength = 52, VerticalCountLength = 32, HorizontalButtonLength = 60, HorizontalCountLength = 68;
    public const double RoundDiameter = 56, SnapMargin = 8, SnapThreshold = 81;
    public static SizeD FullSize(ToolbarOrientation orientation, bool hasPaging, double textScale = 1)
    {
        double scale = double.IsFinite(textScale) ? Math.Max(1, textScale) : 1;
        return orientation == ToolbarOrientation.Vertical
            ? new(64 * scale, (hasPaging ? 324 : 296) * scale)
            : new((hasPaging ? 428 : 364) * scale, 64 * scale);
    }
    private static ScreenEdge Opposite(ScreenEdge e) => e switch { ScreenEdge.Left => ScreenEdge.Right, ScreenEdge.Right => ScreenEdge.Left, ScreenEdge.Top => ScreenEdge.Bottom, _ => ScreenEdge.Top };
    private static bool Vertical(ScreenEdge e) => e is ScreenEdge.Left or ScreenEdge.Right;
    private static (double Min, double Max) Span(RectD w, ScreenEdge e)
    {
        double min = (Vertical(e) ? w.Y : w.X) + 8 + 28 + 40;
        double max = (Vertical(e) ? w.Bottom : w.Right) - 8 - 28 - 40;
        if (max < min)
            min = max = Vertical(e) ? w.Center.Y : w.Center.X;
        return (min, max);
    }
    public static HomeGeometry Home(ScreenSet screens, ScreenInfo screen, HomePosition position)
    {
        if (!position.IsValid)
            position = new();
        var edge = new[] { position.Edge, Opposite(position.Edge), ScreenEdge.Left, ScreenEdge.Right, ScreenEdge.Top, ScreenEdge.Bottom }
            .FirstOrDefault(e => screens.IsOuter(screen, e), position.Edge);
        var w = screen.WorkArea;
        var span = Span(w, edge);
        double along = Vertical(edge) ? span.Max - position.Ratio * (span.Max - span.Min) : span.Min + position.Ratio * (span.Max - span.Min);
        var r = edge switch
        {
            ScreenEdge.Left => new RectD(w.X + 8, along - 28, 56, 56),
            ScreenEdge.Right => new RectD(w.Right - 64, along - 28, 56, 56),
            ScreenEdge.Top => new RectD(along - 28, w.Y + 8, 56, 56),
            _ => new RectD(along - 28, w.Bottom - 64, 56, 56)
        };
        r = r.Fit(w);
        var hit = edge switch
        {
            ScreenEdge.Left => new RectD(w.X, r.Y - 4, r.Right - w.X, r.Height + 8),
            ScreenEdge.Right => new RectD(r.X, r.Y - 4, w.Right - r.X, r.Height + 8),
            ScreenEdge.Top => new RectD(r.X - 4, w.Y, r.Width + 8, r.Bottom - w.Y),
            _ => new RectD(r.X - 4, r.Y, r.Width + 8, w.Bottom - r.Y)
        };
        return new(new(edge, position.Ratio), r, hit.Fit(w));
    }
    // Pointer positions arrive in physical virtual-desktop pixels; projection uses destination-screen DIP.
    public static HomeGeometry ProjectHome(ScreenSet screens, ScreenInfo screen, PointD pointerPixels)
    {
        var pointer = new PointD(pointerPixels.X / screen.DpiScale, pointerPixels.Y / screen.DpiScale);
        var w = screen.WorkArea;
        var edge = Enum.GetValues<ScreenEdge>().Where(e => screens.IsOuter(screen, e)).OrderBy(e => e switch
        {
            ScreenEdge.Left => Math.Abs(pointer.X - w.X),
            ScreenEdge.Right => Math.Abs(pointer.X - w.Right),
            ScreenEdge.Top => Math.Abs(pointer.Y - w.Y),
            _ => Math.Abs(pointer.Y - w.Bottom)
        }).FirstOrDefault();
        var span = Span(w, edge);
        double ratio = span.Max == span.Min ? .5 : Vertical(edge)
            ? (span.Max - pointer.Y) / (span.Max - span.Min) : (pointer.X - span.Min) / (span.Max - span.Min);
        return Home(screens, screen, new(edge, Math.Clamp(ratio, 0, 1)));
    }
    // pointerPixels selects the screen; target is already expressed in that screen's DIP.
    public static ToolbarPlacement Release(ScreenSet screens, PointD pointerPixels, string lastScreen, RectD target, ScreenEdge? originalEdge = null)
    {
        var screen = screens.At(pointerPixels) ?? screens.Resolve(lastScreen);
        var w = screen.WorkArea;
        var candidates = Enum.GetValues<ScreenEdge>().Where(e => screens.IsOuter(screen, e) &&
            target.Width + 16 <= w.Width && target.Height + 16 <= w.Height)
            .Select(e => (Edge: e, Distance: e switch
            {
                ScreenEdge.Left => Math.Abs(target.X - w.X),
                ScreenEdge.Right => Math.Abs(target.Right - w.Right),
                ScreenEdge.Top => Math.Abs(target.Y - w.Y),
                _ => Math.Abs(target.Bottom - w.Bottom)
            })).Where(x => x.Distance <= SnapThreshold).OrderBy(x => x.Distance)
            .ThenBy(x => x.Edge == originalEdge ? -1 : (int)x.Edge).ToArray();
        ScreenEdge? edge = candidates.Length == 0 ? null : candidates[0].Edge;
        var r = target.Fit(w.Inset(8));
        r = edge switch
        {
            ScreenEdge.Left => new(w.X + 8, r.Y, r.Width, r.Height),
            ScreenEdge.Right => new(w.Right - 8 - r.Width, r.Y, r.Width, r.Height),
            ScreenEdge.Top => new(r.X, w.Y + 8, r.Width, r.Height),
            ScreenEdge.Bottom => new(r.X, w.Bottom - 8 - r.Height, r.Width, r.Height),
            _ => r
        };
        return new(screen, r, edge);
    }
    public static ScreenInfo AnchorScreen(ScreenSet screens, LocalPreferences preferences)
    {
        var anchor = preferences.Normalize().Anchor;
        if (anchor?.Center is { } pixels && screens.At(pixels) is { } screen)
            return screen;
        return screens.Resolve(anchor?.DeviceHint);
    }
    public static RectD ResolveAnchor(ScreenSet screens, LocalPreferences preferences, ToolbarOrientation orientation, bool hasPaging, double textScale = 1)
    {
        var p = preferences.Normalize();
        var size = FullSize(orientation, hasPaging, textScale);
        var screen = AnchorScreen(screens, p);
        if (p.Anchor?.Center is { } center)
        {
            return new RectD(center.X / screen.DpiScale - size.Width / 2,
                center.Y / screen.DpiScale - size.Height / 2, size.Width, size.Height)
                .Fit(screen.WorkArea.Inset(SnapMargin));
        }
        if (p.Anchor?.Edge is not { } edge)
            return Expand(Home(screens, screen, p.Home), screen.WorkArea, orientation, hasPaging, textScale);

        // Full-frame centers use the whole safe span, unlike the inset home entrance span.
        edge = Home(screens, screen, new(edge, p.Anchor.Ratio)).Position.Edge;
        var area = screen.WorkArea.Inset(SnapMargin);
        double width = Math.Min(size.Width, area.Width), height = Math.Min(size.Height, area.Height);
        double x = area.X + p.Anchor.Ratio * (area.Width - width);
        double y = area.Y + (1 - p.Anchor.Ratio) * (area.Height - height);
        return edge switch
        {
            ScreenEdge.Left => new(area.X, y, width, height),
            ScreenEdge.Right => new(area.Right - width, y, width, height),
            ScreenEdge.Top => new(x, area.Y, width, height),
            _ => new(x, area.Bottom - height, width, height)
        };
    }
    public static RectD Expand(HomeGeometry home, RectD workArea, ToolbarOrientation orientation, bool hasPaging, double textScale = 1)
    {
        var size = FullSize(orientation, hasPaging, textScale);
        var c = home.Entrance.Center;
        double x = c.X - size.Width / 2, y = c.Y - size.Height / 2;
        if (orientation == ToolbarOrientation.Vertical)
            y = home.Position.Edge == ScreenEdge.Bottom ? c.Y + 28 - size.Height : c.Y - 28;
        else
            x = home.Position.Edge == ScreenEdge.Right ? c.X + 28 - size.Width : c.X - 28;
        return new RectD(x, y, size.Width, size.Height).Fit(workArea.Inset(8));
    }
    public static TimeSpan ReturnDuration(double distance) => TimeSpan.FromSeconds(Math.Clamp(.30 + Math.Max(0, distance) / 3000, .30, .50));
}
