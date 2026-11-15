using DeskNodes.Core.Domain;

namespace DeskNodes.Core.Presentation;

public enum ScreenEdge { Left, Right, Top, Bottom }
public sealed record ScreenInfo(string Id, string DeviceHint, RectD Bounds, RectD WorkArea,
    bool IsPrimary = false, double DpiScale = 1);

public sealed class ScreenSet
{
    public IReadOnlyList<ScreenInfo> Screens { get; }
    public ScreenInfo Primary => Screens.FirstOrDefault(s => s.IsPrimary) ?? Screens[0];
    public ScreenSet(IEnumerable<ScreenInfo> screens)
    {
        var list = screens.ToArray();
        if (list.Length == 0 || list.Any(s => !double.IsFinite(s.DpiScale) || s.DpiScale <= 0) ||
            list.Select(s => s.Id).Distinct().Count() != list.Length)
            throw new ArgumentException("需要非空、标识唯一且 DPI 有效的屏幕集合。", nameof(screens));
        Screens = Array.AsReadOnly(list);
    }
    public ScreenInfo? At(PointD point) => Screens.FirstOrDefault(s => s.Bounds.Contains(point));
    public ScreenInfo For(RectD rect) => Screens.OrderByDescending(s => Intersection(rect, s.Bounds)).FirstOrDefault(s => Intersection(rect, s.Bounds) > 0) ?? Primary;
    public ScreenInfo Resolve(string? hint) => Screens.FirstOrDefault(s => s.DeviceHint == hint || s.Id == hint) ?? Primary;
    private static double Intersection(RectD a, RectD b) => Math.Max(0, Math.Min(a.Right, b.Right) - Math.Max(a.X, b.X)) * Math.Max(0, Math.Min(a.Bottom, b.Bottom) - Math.Max(a.Y, b.Y));

    // Any shared segment makes this whole edge ineligible: a predictable conservative snap policy.
    public bool IsOuter(ScreenInfo screen, ScreenEdge edge) => !Screens.Any(other => other.Id != screen.Id &&
        (Touches(screen.Bounds, other.Bounds, edge) || Touches(screen.WorkArea, other.WorkArea, edge)));
    private static bool Touches(RectD a, RectD b, ScreenEdge edge) => edge switch
    {
        ScreenEdge.Left => Math.Abs(a.X - b.Right) < .01 && a.Y < b.Bottom && b.Y < a.Bottom,
        ScreenEdge.Right => Math.Abs(a.Right - b.X) < .01 && a.Y < b.Bottom && b.Y < a.Bottom,
        ScreenEdge.Top => Math.Abs(a.Y - b.Bottom) < .01 && a.X < b.Right && b.X < a.Right,
        _ => Math.Abs(a.Bottom - b.Y) < .01 && a.X < b.Right && b.X < a.Right
    };
}
