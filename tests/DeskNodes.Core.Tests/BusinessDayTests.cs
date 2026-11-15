using DeskNodes.Core.Domain;

namespace DeskNodes.Core.Tests;

public sealed class BusinessDayTests
{
    private readonly BusinessDayCalculator calculator = new();

    [Theory]
    [InlineData("America/Los_Angeles", "2026-03-08", 150, "2026-03-08T10:00:00Z", 23.5)]
    [InlineData("America/Los_Angeles", "2026-11-01", 90, "2026-11-01T08:30:00Z", 25)]
    [InlineData("Europe/London", "2026-03-29", 90, "2026-03-29T01:00:00Z", 23.5)]
    [InlineData("Europe/London", "2026-10-25", 90, "2026-10-25T00:30:00Z", 25)]
    [InlineData("America/Los_Angeles", "2026-03-08", 0, "2026-03-08T08:00:00Z", 23)]
    [InlineData("America/Los_Angeles", "2026-11-01", 0, "2026-11-01T07:00:00Z", 25)]
    [InlineData("Europe/London", "2026-03-28", 1439, "2026-03-28T23:59:00Z", 23)]
    [InlineData("Europe/London", "2026-10-24", 1439, "2026-10-24T22:59:00Z", 25)]
    public void BoundariesResolveGapsAndFirstOccurrence(string id, string date, int minute, string startUtc, double hours)
    {
        var zone = TimeZoneInfo.FindSystemTimeZoneById(id);
        var day = HistoryDay.Parse(date);
        var start = calculator.GetStartUtc(day, zone, minute);
        var end = calculator.GetEndUtc(day, zone, minute);
        Assert.Equal(DateTimeOffset.Parse(startUtc), start);
        Assert.Equal(hours, (end - start).TotalHours);
        Assert.Equal(new HistoryDay(day.Value.AddDays(-1)), calculator.GetDay(start.AddTicks(-1), zone, minute));
        Assert.Equal(day, calculator.GetDay(start, zone, minute));
        Assert.Equal(day, calculator.GetDay(end.AddTicks(-1), zone, minute));
        Assert.Equal(new HistoryDay(day.Value.AddDays(1)), calculator.GetDay(end, zone, minute));
    }

    [Theory]
    [InlineData("America/Los_Angeles", "2026-11-01T09:15:00Z")]
    [InlineData("Europe/London", "2026-10-25T01:15:00Z")]
    public void SecondOccurrenceBeforeWallBoundaryStillBelongsToNewDay(string id, string utc)
    {
        var instant = DateTimeOffset.Parse(utc);
        var zone = TimeZoneInfo.FindSystemTimeZoneById(id);
        Assert.Equal(new HistoryDay(DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(instant, zone).DateTime)),
            calculator.GetDay(instant, zone, 90));
    }

    [Theory]
    [InlineData(-1)]
    [InlineData(1440)]
    public void InvalidMinutesRejected(int minute) => Assert.Throws<ArgumentOutOfRangeException>(() =>
        calculator.GetDay(DateTimeOffset.UtcNow, TimeZoneInfo.Utc, minute));

    [Fact]
    public void DefaultBoundaryIsFourAm()
    {
        var at = DateTimeOffset.Parse("2026-01-01T04:00:00Z");
        Assert.Equal(HistoryDay.Parse("2025-12-31"), calculator.GetDay(at.AddTicks(-1), TimeZoneInfo.Utc));
        Assert.Equal(HistoryDay.Parse("2026-01-01"), calculator.GetDay(at, TimeZoneInfo.Utc));
    }
}
