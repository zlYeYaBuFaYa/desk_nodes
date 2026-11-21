using DeskNodes.Core.Domain;
using DeskNodes.Core.Storage;

namespace DeskNodes.Core.Services;

public enum CalendarShade { None, Weak, Low, Mid, Full }
public sealed record DayStatistics(HistoryDay Day, Progress Progress);
public sealed record MonthStatistics(int Year, int Month, Progress Progress, IReadOnlyList<DayStatistics> Days);
public sealed record FrozenItem(NoteItem Item, bool Deleted, HistoryDay? CarriedTo);
public sealed record FrozenNote(Note Note, bool Deleted, IReadOnlyList<FrozenItem> Items);
public sealed record FrozenDay(HistoryDay Day, bool HasSnapshot, IReadOnlyList<FrozenNote> Notes);

public sealed class HistoryQueries(DeskNodesDatabase database)
{
    private const string Statistics = """
        SELECT s.day,coalesce(sum(CASE WHEN i.struck=0 AND i.completed=1 THEN 1 ELSE 0 END),0),
        count(CASE WHEN i.struck=0 THEN 1 END)
        FROM snapshots s LEFT JOIN snapshot_items i ON i.day=s.day
        """;

    public IReadOnlyList<DayStatistics> RecentSealedDays(int limit = 7)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(limit);
        return ReadStatistics(Statistics + " GROUP BY s.day ORDER BY s.day DESC LIMIT $limit;", ("$limit", limit));
    }

    public MonthStatistics MonthStats(int year, int month)
    {
        var first = new DateOnly(year, month, 1);
        string prefix = first.ToString("yyyy-MM", System.Globalization.CultureInfo.InvariantCulture);
        var days = ReadStatistics(Statistics + " WHERE substr(s.day,1,7)=$month GROUP BY s.day ORDER BY s.day;", ("$month", prefix));
        return new(year, month, new(days.Sum(d => d.Progress.Completed), days.Sum(d => d.Progress.Total)), days);
    }

    public FrozenDay DaySnapshot(HistoryDay day) => database.Read(connection =>
    {
        using (var exists = connection.CreateCommand())
        {
            exists.CommandText = "SELECT count(*) FROM snapshots WHERE day=$day;";
            exists.Parameters.AddWithValue("$day", day.ToString());
            if (Convert.ToInt32(exists.ExecuteScalar()) == 0) return new FrozenDay(day, false, []);
        }
        var items = new List<FrozenItem>();
        using (var command = connection.CreateCommand())
        {
            command.CommandText = "SELECT *,item_id id FROM snapshot_items WHERE day=$day ORDER BY sort_order,item_id;";
            command.Parameters.AddWithValue("$day", day.ToString());
            using var reader = command.ExecuteReader();
            while (reader.Read()) items.Add(new(NoteRepository.ReadItem(reader), reader.GetBoolean(reader.GetOrdinal("deleted")),
                reader.IsDBNull(reader.GetOrdinal("carried_to")) ? null : HistoryDay.Parse(reader.GetString(reader.GetOrdinal("carried_to")))));
        }
        var itemsByNote = items.ToLookup(i => i.Item.NoteId);
        var notes = new List<FrozenNote>();
        using (var command = connection.CreateCommand())
        {
            command.CommandText = "SELECT *,note_id id FROM snapshot_notes WHERE day=$day ORDER BY sort_order,note_id;";
            command.Parameters.AddWithValue("$day", day.ToString());
            using var reader = command.ExecuteReader();
            while (reader.Read())
            {
                var note = NoteRepository.ReadNote(reader);
                notes.Add(new(note, reader.GetBoolean(reader.GetOrdinal("deleted")), itemsByNote[note.Id].ToArray()));
            }
        }
        return new FrozenDay(day, true, notes);
    });

    public static CalendarShade Shade(bool hasSnapshot, double? rate) => !hasSnapshot ? CalendarShade.None :
        rate is null or <= 0 ? CalendarShade.Weak : rate < .5 ? CalendarShade.Low : rate < 1 ? CalendarShade.Mid : CalendarShade.Full;
    public static double ShadeOpacity(CalendarShade shade) => shade switch
    {
        CalendarShade.Low => .18, CalendarShade.Mid => .38, CalendarShade.Full => .62,
        CalendarShade.None or CalendarShade.Weak => 0, _ => throw new ArgumentOutOfRangeException(nameof(shade))
    };
    public readonly record struct CalendarShadePaint(string Key, double Opacity);
    public static CalendarShadePaint Paint(CalendarShade shade, bool highContrast)
    {
        if (!highContrast)
            return new(shade == CalendarShade.Weak ? "HistoryWeak" : "HistoryProgress", shade == CalendarShade.Weak ? 1 : ShadeOpacity(shade));
        return shade switch
        {
            CalendarShade.Weak => new("HistoryShadeWeak", 1),
            CalendarShade.Low => new("HistoryShadeLow", 1),
            CalendarShade.Mid => new("HistoryShadeMid", 1),
            CalendarShade.Full => new("HistoryShadeFull", 1),
            _ => new("HistoryProgress", 0)
        };
    }

    public static string RelativeLabel(HistoryDay day, HistoryDay currentBusinessDay)
    {
        int elapsed = currentBusinessDay.Value.DayNumber - day.Value.DayNumber;
        if (elapsed == 0) return "今天";
        if (elapsed == 1) return "昨天";
        if (elapsed is >= 2 and < 7) return "周" + "日一二三四五六"[(int)day.Value.DayOfWeek];
        // Documents leave the exact long-date format open: Chinese month/day, year only across years.
        return day.Value.ToString(day.Value.Year == currentBusinessDay.Value.Year ? "M月d日" : "yyyy年M月d日", System.Globalization.CultureInfo.InvariantCulture);
    }

    private IReadOnlyList<DayStatistics> ReadStatistics(string sql, (string Name, object Value) parameter) => database.Read(connection =>
    {
        using var command = connection.CreateCommand();
        command.CommandText = sql;
        command.Parameters.AddWithValue(parameter.Name, parameter.Value);
        using var reader = command.ExecuteReader();
        var days = new List<DayStatistics>();
        while (reader.Read()) days.Add(new(HistoryDay.Parse(reader.GetString(0)), new(reader.GetInt32(1), reader.GetInt32(2))));
        return (IReadOnlyList<DayStatistics>)days;
    });
}
