using DeskNodes.Core.Domain;

namespace DeskNodes.Core.Presentation;

public enum ScreenEdge
{
    Left, Right, Top, Bottom
}
// Bounds/WorkArea are virtual pixel coordinates divided by this screen's scale.
// They are only meaningful within that screen; multiply by DpiScale to place a window.
// PixelBounds is the physical virtual-desktop rectangle used for topology and pointers.
public sealed record ScreenInfo(string Id, string DeviceHint, RectD Bounds, RectD WorkArea,
    bool IsPrimary = false, double DpiScale = 1)
{
    public RectD PixelBounds { get; init; } = new(Bounds.X * DpiScale, Bounds.Y * DpiScale,
        Bounds.Width * DpiScale, Bounds.Height * DpiScale);
}

// Cross-screen topology and point/rectangle ownership use physical virtual-desktop pixels.
// Once a screen is selected, its Bounds/WorkArea provide that screen's DIP layout space.
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
    // Pointer inputs are physical virtual-desktop pixels, never per-screen DIP.
    public ScreenInfo? At(PointD pixelPoint) => Screens.FirstOrDefault(s => s.PixelBounds.Contains(pixelPoint));
    // Rectangular cross-screen queries also use physical pixels.
    public ScreenInfo For(RectD pixelRect) => Screens.OrderByDescending(s => Intersection(pixelRect, s.PixelBounds))
        .FirstOrDefault(s => Intersection(pixelRect, s.PixelBounds) > 0) ?? Primary;
    public ScreenInfo Resolve(string? hint) => Screens.FirstOrDefault(s => s.DeviceHint == hint || s.Id == hint) ?? Primary;
    private static double Intersection(RectD a, RectD b) => Math.Max(0, Math.Min(a.Right, b.Right) - Math.Max(a.X, b.X)) * Math.Max(0, Math.Min(a.Bottom, b.Bottom) - Math.Max(a.Y, b.Y));

    // Any shared segment makes this whole edge ineligible: a predictable conservative snap policy.
    public bool IsOuter(ScreenInfo screen, ScreenEdge edge) => !Screens.Any(other => other.Id != screen.Id &&
        Touches(screen.PixelBounds, other.PixelBounds, edge));
    private static bool Touches(RectD a, RectD b, ScreenEdge edge) => edge switch
    {
        ScreenEdge.Left => Math.Abs(a.X - b.Right) < .01 && a.Y < b.Bottom && b.Y < a.Bottom,
        ScreenEdge.Right => Math.Abs(a.Right - b.X) < .01 && a.Y < b.Bottom && b.Y < a.Bottom,
        ScreenEdge.Top => Math.Abs(a.Y - b.Bottom) < .01 && a.X < b.Right && b.X < a.Right,
        _ => Math.Abs(a.Bottom - b.Y) < .01 && a.X < b.Right && b.X < a.Right
    };
}
