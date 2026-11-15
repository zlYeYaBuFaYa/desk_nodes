namespace DeskNodes.Core.Domain;

public sealed class BusinessDayCalculator
{
    public HistoryDay GetDay(DateTimeOffset utc, TimeZoneInfo zone, int rolloverMinutes = 240)
    {
        var date = DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(utc, zone).DateTime);
        var day = new HistoryDay(date);
        return utc < GetStartUtc(day, zone, rolloverMinutes) ? new(date.AddDays(-1)) : day;
    }

    public DateTimeOffset GetStartUtc(HistoryDay day, TimeZoneInfo zone, int rolloverMinutes = 240)
    {
        ArgumentNullException.ThrowIfNull(zone);
        ArgumentOutOfRangeException.ThrowIfNegative(rolloverMinutes);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(rolloverMinutes, 1439);
        var local = day.Value.ToDateTime(TimeOnly.MinValue, DateTimeKind.Unspecified).AddMinutes(rolloverMinutes);
        // Boundaries have minute precision. Advance through a DST gap to the first valid minute.
        while (zone.IsInvalidTime(local))
            local = local.AddMinutes(1);
        var offset = zone.IsAmbiguousTime(local) ? zone.GetAmbiguousTimeOffsets(local).Max() : zone.GetUtcOffset(local);
        return new DateTimeOffset(local, offset).ToUniversalTime();
    }

    /// <summary>Exclusive end; identical to the following business day's start.</summary>
    public DateTimeOffset GetEndUtc(HistoryDay day, TimeZoneInfo zone, int rolloverMinutes = 240)
        => GetStartUtc(new(day.Value.AddDays(1)), zone, rolloverMinutes);
}
