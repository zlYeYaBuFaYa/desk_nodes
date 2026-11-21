using System.Text.RegularExpressions;

namespace DeskNodes.Core.Services;

public sealed record PasteResult(bool KeepNativePaste, string? FirstLine, IReadOnlyList<string> FollowingLines);

public static partial class PasteParser
{
    [GeneratedRegex(@"^\s*(?:(?:[-*•·]\s+)?\[[ xX]\]\s*|[-*•·]\s+|\d+[.)](?!\d)\s*|[（(]\d+[）)]\s*)")]
    private static partial Regex Prefix();

    public static PasteResult Parse(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        if (!text.Contains('\r') && !text.Contains('\n')) return new(true, null, []);
        var lines = text.Split(["\r\n", "\n", "\r"], StringSplitOptions.None)
            .Select(line => Prefix().Replace(line, "", 1).Trim()).Where(line => line.Length > 0).ToArray();
        return new(false, lines.FirstOrDefault(), lines.Skip(1).ToArray());
    }
}
