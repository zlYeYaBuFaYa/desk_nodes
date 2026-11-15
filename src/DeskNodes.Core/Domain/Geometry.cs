namespace DeskNodes.Core.Domain;

/// <summary>Monitor-relative DIP coordinates, with a top-left origin and Y increasing downward.</summary>
public readonly record struct RectD
{
    public double X { get; }
    public double Y { get; }
    public double Width { get; }
    public double Height { get; }

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
