using System.Globalization;

namespace DeskNodes.Core.Domain;

public readonly record struct HistoryDay(DateOnly Value)
{
    public static HistoryDay Parse(string value)
    {
        if (!TryParse(value, out HistoryDay day))
            throw new FormatException("业务日必须是有效的公历 YYYY-MM-DD 日期。");
        return day;
    }

    public static bool TryParse(string? value, out HistoryDay day)
    {
        day = default;
        if (value is not { Length: 10 } ||
            !DateOnly.TryParseExact(value, "yyyy-MM-dd", CultureInfo.InvariantCulture,
                DateTimeStyles.None, out DateOnly date))
            return false;
        day = new HistoryDay(date);
        return true;
    }

    public override string ToString() => Value.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
}
