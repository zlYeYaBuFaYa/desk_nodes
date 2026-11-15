namespace DeskNodes.Core.Presentation;

public sealed record NoteTypography(double Title, double Body, double Secondary)
{
    public double Scale(double value) => Math.Round(value * Body / 14, MidpointRounding.AwayFromZero);
    public double AutomaticHeight(double rowsHeight, double workHeight) => Math.Min(Math.Max(0, workHeight - 16), Math.Clamp(Scale(94) + rowsHeight + 18, 120, 480));
    public static NoteTypography For(NoteTextSize size) => size switch
    {
        NoteTextSize.Small => new(15, 13, 11), NoteTextSize.Large => new(18, 16, 14),
        NoteTextSize.ExtraLarge => new(20, 18, 15), _ => new(16, 14, 12)
    };
}

public sealed record NoteFontMapping(string Family, string TitleWeight, bool Available);
public static class NoteFontRules
{
    public const string DefaultFamily = "Segoe UI, Microsoft YaHei UI";
    public static NoteFontMapping Resolve(NoteFont font, Func<string, bool> installed) => font switch
    {
        NoteFont.Rounded when installed("YouYuan") => new("Segoe UI, YouYuan", "Bold", true),
        NoteFont.Song when installed("SimSun") => new("Georgia, SimSun", "Bold", true),
        NoteFont.Song when installed("NSimSun") => new("Georgia, NSimSun", "Bold", true),
        NoteFont.Wenkai when installed("LXGW WenKai") => new("LXGW WenKai", "Medium", true),
        NoteFont.Default => new(DefaultFamily, "SemiBold", true),
        _ => new(DefaultFamily, "SemiBold", false)
    };
}
