namespace DeskNodes.Core.Domain;

/// <summary>DIP coordinates (monitor-relative in persisted placements, virtual-screen in presentation), with a top-left origin and Y increasing downward.</summary>
public readonly record struct RectD
{
    public double X { get; }
    public double Y { get; }
    public double Width { get; }
    public double Height { get; }

    public double Right => X + Width;
    public double Bottom => Y + Height;
    public PointD Center => new(X + Width / 2, Y + Height / 2);
    public bool Contains(PointD p) => p.X >= X && p.X < Right && p.Y >= Y && p.Y < Bottom;
    public bool Intersects(RectD r) => X < r.Right && Right > r.X && Y < r.Bottom && Bottom > r.Y;
    public RectD Inset(double margin) => new(X + Math.Min(margin, Width / 2), Y + Math.Min(margin, Height / 2),
        Math.Max(0, Width - margin * 2), Math.Max(0, Height - margin * 2));
    public RectD Fit(RectD area) => new(Math.Clamp(X, area.X, area.Right - Math.Min(Width, area.Width)),
        Math.Clamp(Y, area.Y, area.Bottom - Math.Min(Height, area.Height)), Math.Min(Width, area.Width), Math.Min(Height, area.Height));

    public RectD(double x, double y, double width, double height)
    {
        if (!double.IsFinite(x) || !double.IsFinite(y) || !double.IsFinite(width) ||
            !double.IsFinite(height) || width < 0 || height < 0)
            throw new ArgumentOutOfRangeException(nameof(width), "矩形必须使用有限坐标及非负尺寸。");
        (X, Y, Width, Height) = (x, y, width, height);
    }
}

public enum DockEdge { Top, Left, Right }

public sealed record Placement
{
    public RectD Bounds { get; }
    public string DisplayDeviceHint { get; }
    public DockEdge? DockEdge { get; }
    public int? DockOrder { get; }

    public Placement(RectD bounds, string displayDeviceHint, DockEdge? dockEdge = null, int? dockOrder = null)
    {
        ArgumentNullException.ThrowIfNull(displayDeviceHint);
        if (dockEdge.HasValue != dockOrder.HasValue || dockOrder < 0 ||
            (dockEdge.HasValue && !Enum.IsDefined(dockEdge.Value)))
            throw new ArgumentException("停靠边和非负序号必须同时指定。");
        (Bounds, DisplayDeviceHint, DockEdge, DockOrder) = (bounds, displayDeviceHint, dockEdge, dockOrder);
    }
}

public readonly record struct PointD(double X, double Y);
public readonly record struct SizeD(double Width, double Height);
