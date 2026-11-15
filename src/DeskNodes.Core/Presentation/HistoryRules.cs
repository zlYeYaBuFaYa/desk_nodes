using System.Globalization;

using DeskNodes.Core.Domain;
using DeskNodes.Core.Services;

namespace DeskNodes.Core.Presentation;

public enum HistoryItemState { Pending, Completed, Struck, Deleted }
public sealed record DeletedProjection(string Preview, bool CanRestore, string Explanation);
public sealed record HistoryItemProjection(HistoryItemState State, string? Carry);

public static class HistoryRules
{
    public static string ColorKey(NoteColor color) => "History" + color;

    public static DeletedProjection ProjectDeleted(DeletedEntry entry, IReadOnlySet<NoteId> existingNotes)
    {
        bool canRestore = entry.Member.ItemId is null || existingNotes.Contains(entry.ParentId);
        var lines = entry.Preview.AsEnumerable();
        if (entry.RemainingCount > 0)
            lines = lines.Append(FormattableString.Invariant($"还有 {entry.RemainingCount} 项"));
        return new(entry.Text ?? string.Join("\n", lines), canRestore,
            canRestore ? "" : "原便签已删除，请先恢复便签");
    }

    public static HistoryItemProjection ProjectItem(bool deleted, bool struck, bool completed, HistoryDay? carriedTo) =>
        new(deleted ? HistoryItemState.Deleted : struck ? HistoryItemState.Struck : completed ? HistoryItemState.Completed : HistoryItemState.Pending,
            carriedTo is { } day ? "顺延至 " + day.Value.ToString("M月d日", CultureInfo.InvariantCulture) : null);

    public static bool HandlesNavigation(bool calendar, bool textFocus, bool controlFocus, bool modified) =>
        calendar && !textFocus && (modified || !controlFocus);

    public static string DeletedTime(DateTimeOffset deletedAt, DateTimeOffset now, TimeZoneInfo zone)
    {
        var elapsed = now - deletedAt;
        if (elapsed < TimeSpan.Zero || elapsed >= TimeSpan.FromDays(7))
            return TimeZoneInfo.ConvertTime(deletedAt, zone).ToString("yyyy年M月d日 HH:mm", CultureInfo.InvariantCulture) + " 移出列表";
        if (elapsed.TotalMinutes < 1) return "刚刚移出列表";
        if (elapsed.TotalHours < 1) return $"{(int)elapsed.TotalMinutes} 分钟前移出列表";
        if (elapsed.TotalDays < 1) return $"{(int)elapsed.TotalHours} 小时前移出列表";
        return $"{(int)elapsed.TotalDays} 天前移出列表";
    }
}
