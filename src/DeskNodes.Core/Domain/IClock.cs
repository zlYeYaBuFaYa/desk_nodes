namespace DeskNodes.Core.Domain;

public interface IClock
{
    DateTimeOffset UtcNow { get; }
    TimeZoneInfo TimeZone { get; }
}

public sealed class SystemClock : IClock
{
    public DateTimeOffset UtcNow => DateTimeOffset.UtcNow;
    public TimeZoneInfo TimeZone => TimeZoneInfo.Local;
}
