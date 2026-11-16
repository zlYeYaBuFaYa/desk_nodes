namespace DeskNodes.Core.Domain;

public interface IClock
{
    DateTimeOffset UtcNow { get; }
    TimeZoneInfo TimeZone { get; }
}

public sealed class SystemClock(TimeProvider? timeProvider = null) : IClock
{
    private readonly TimeProvider provider = timeProvider ?? TimeProvider.System;
    public DateTimeOffset UtcNow => provider.GetUtcNow();
    public TimeZoneInfo TimeZone => provider.LocalTimeZone;
}
