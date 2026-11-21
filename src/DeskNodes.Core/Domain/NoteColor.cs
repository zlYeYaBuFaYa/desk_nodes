namespace DeskNodes.Core.Domain;

public enum NoteColor { Paper, Lemon, Apricot, Cherry, Lavender, Mist, Mint }
public enum NoteLevel { Back, Normal, Topmost }

/// <summary>Stable storage identifiers; never persist enum ordinals or depend on member names.</summary>
public static class NoteColors
{
    public static string ToStorageId(this NoteColor color) => color switch
    {
        NoteColor.Paper => "paper",
        NoteColor.Lemon => "lemon",
        NoteColor.Apricot => "apricot",
        NoteColor.Cherry => "cherry",
        NoteColor.Lavender => "lavender",
        NoteColor.Mist => "mist",
        NoteColor.Mint => "mint",
        _ => throw new ArgumentOutOfRangeException(nameof(color))
    };

    public static NoteColor ParseStorageId(string value) => value switch
    {
        "paper" => NoteColor.Paper,
        "lemon" => NoteColor.Lemon,
        "apricot" => NoteColor.Apricot,
        "cherry" => NoteColor.Cherry,
        "lavender" => NoteColor.Lavender,
        "mist" => NoteColor.Mist,
        "mint" => NoteColor.Mint,
        _ => throw new FormatException($"未知便签颜色：{value}")
    };
}
