using DeskNodes.Core.Domain;

namespace DeskNodes.Core.Presentation;

public sealed record SettingsState(LocalPreferences Preferences)
{
    public static IReadOnlyList<string> Groups { get; } = ["通用", "便签", "工具条"];
    public bool CanResetHome => !Preferences.Home.IsDefault;
    public static PointD HomePreview(HomePosition home, double width, double height, double inset = 12)
    {
        double x = inset + Math.Max(0, width - 2 * inset) * home.Ratio;
        double y = height - inset - Math.Max(0, height - 2 * inset) * home.Ratio;
        return home.Edge switch
        {
            ScreenEdge.Left => new(inset, y),
            ScreenEdge.Right => new(Math.Max(inset, width - inset), y),
            ScreenEdge.Top => new(x, inset),
            _ => new(x, Math.Max(inset, height - inset))
        };
    }
    public static bool TryParseTime(string text, out int minutes)
    {
        minutes = 0;
        if (!TimeOnly.TryParseExact(text, "HH:mm", System.Globalization.CultureInfo.InvariantCulture,
            System.Globalization.DateTimeStyles.None, out var time)) return false;
        minutes = time.Hour * 60 + time.Minute;
        return true;
    }
}
