using DeskNodes.Core.Domain;

namespace DeskNodes.Core.Presentation;

public static class ToolbarRules
{
    public static RectD AnimationFrame(RectD start, RectD end)
    {
        double padding = Math.Max(Math.Abs(end.Width - start.Width), Math.Abs(end.Height - start.Height)) * .035;
        double left = Math.Min(start.X, end.X) - padding;
        double top = Math.Min(start.Y, end.Y) - padding;
        return new(left, top, Math.Max(start.Right, end.Right) + padding - left,
            Math.Max(start.Bottom, end.Bottom) + padding - top);
    }
    public static bool HandleAtEnd(ToolbarOrientation orientation, ScreenEdge edge) =>
        orientation == ToolbarOrientation.Vertical ? edge == ScreenEdge.Bottom : edge == ScreenEdge.Right;
    public static RectD HandleRound(RectD full, ToolbarOrientation orientation, ScreenEdge edge)
    {
        bool atEnd = HandleAtEnd(orientation, edge);
        return orientation == ToolbarOrientation.Vertical
            ? new(edge == ScreenEdge.Left ? full.X : edge == ScreenEdge.Right ? full.Right - 56 : full.Center.X - 28,
                atEnd ? full.Bottom - 56 : full.Y, 56, 56)
            : new(atEnd ? full.Right - 56 : full.X,
                edge == ScreenEdge.Top ? full.Y : edge == ScreenEdge.Bottom ? full.Bottom - 56 : full.Center.Y - 28, 56, 56);
    }
    public static ToolbarAnchor Anchor(ToolbarPlacement placement)
    {
        var bounds = placement.Bounds;
        var screen = placement.Screen;
        if (placement.Edge is not { } edge)
            return new(new(bounds.Center.X * screen.DpiScale, bounds.Center.Y * screen.DpiScale));
        var area = screen.WorkArea.Inset(8);
        double ratio = edge is ScreenEdge.Left or ScreenEdge.Right
            ? (area.Bottom - bounds.Bottom) / Math.Max(1, area.Height - bounds.Height)
            : (bounds.X - area.X) / Math.Max(1, area.Width - bounds.Width);
        return new(null, edge, Math.Clamp(ratio, 0, 1), screen.DeviceHint);
    }
    public static bool IsVisible(bool collapsed, int? notePage, int sharedPage, int screenLastPage) =>
        !collapsed && (notePage is null || notePage == Math.Min(sharedPage, screenLastPage));
    public static bool CanManage(int count) => count > 0;
    public static bool IsDrag(double x, double y) => Math.Max(Math.Abs(x), Math.Abs(y)) >= 4;
    public static double Spring(double seconds)
    {
        if (seconds <= 0) return 0;
        if (seconds >= .5) return 1;
        double frequency = Math.Sqrt(260 - 12 * 12);
        return 1 - Math.Exp(-12 * seconds) * (Math.Cos(frequency * seconds) + 12 / frequency * Math.Sin(frequency * seconds));
    }
    public static double ControlProgress(double seconds, int index) => Math.Clamp((seconds - .08 - index * .028) / .22, 0, 1);
}
