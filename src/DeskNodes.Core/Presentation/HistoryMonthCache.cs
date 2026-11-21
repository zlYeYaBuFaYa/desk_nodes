using DeskNodes.Core.Services;

namespace DeskNodes.Core.Presentation;

/// <summary>A data generation invalidates all cached months and rejects reentrant stale reads.</summary>
public sealed class HistoryMonthCache(Func<int, int, MonthStatistics> read)
{
    private readonly Dictionary<(int Year, int Month), MonthStatistics> months = [];
    public long Generation { get; private set; } = -1;
    public void Invalidate(long generation)
    {
        if (Generation == generation)
            return;
        Generation = generation;
        months.Clear();
    }
    public MonthStatistics? Get(int year, int month)
    {
        var key = (year, month);
        if (months.TryGetValue(key, out var cached))
            return cached;
        long generation = Generation;
        var result = read(year, month);
        if (generation != Generation)
            return null;
        months.Add(key, result);
        return result;
    }
}
