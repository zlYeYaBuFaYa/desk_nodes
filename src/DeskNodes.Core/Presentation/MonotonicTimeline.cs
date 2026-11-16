namespace DeskNodes.Core.Presentation;

public sealed class MonotonicTimeline(TimeProvider timeProvider)
{
    private readonly long origin = timeProvider.GetTimestamp();
    public TimeSpan Elapsed => timeProvider.GetElapsedTime(origin, timeProvider.GetTimestamp());
}
