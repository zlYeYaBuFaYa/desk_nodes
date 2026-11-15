using DeskNodes.Core.Domain;
using DeskNodes.Core.Storage;
using Microsoft.Data.Sqlite;

namespace DeskNodes.Core.Services;

public enum RolloverStatus { Initialized, NoChange, Sealed, ClockRegressed, Deferred, Failed }
public sealed record RolloverResult(RolloverStatus Status, HistoryDay? Day = null,
    int CarriedCount = 0, int ArchivedCount = 0, Exception? Error = null);

public sealed class DayRolloverService(DeskNodesDatabase database, IClock clock,
    ICommitBarrier commitBarrier, AutomaticBackupService backup, IDeskNodesLog log)
{
    private bool clockRegressed;

    private sealed class CommitRejectedException(CommitResult result) : Exception
    {
        public CommitResult Result { get; } = result;
    }

    public RolloverResult CheckAndAdvance()
    {
        HistoryDay current = default;
        try
        {
            RolloverResult result = database.Transaction(connection =>
            {
                var now = clock.UtcNow;
                int minutes = Convert.ToInt32(Scalar(connection, "SELECT rollover_minutes FROM business_settings WHERE singleton=1;"));
                current = new BusinessDayCalculator().GetDay(now, clock.TimeZone, minutes);
                string? active = null;
                string? highWater = null;
                using (var command = connection.CreateCommand())
                {
                    command.CommandText = "SELECT active_day,high_water FROM checkpoint WHERE singleton=1;";
                    using var reader = command.ExecuteReader();
                    if (reader.Read()) { active = reader.GetString(0); highWater = reader.GetString(1); }
                }
                if (highWater is not null && string.CompareOrdinal(current.ToString(), highWater) < 0)
                {
                    if (!clockRegressed)
                        log.Warn("Business day regressed; checkpoint unchanged.");
                    clockRegressed = true;
                    return new RolloverResult(RolloverStatus.ClockRegressed);
                }
                clockRegressed = false;
                if (active == current.ToString())
                    return new RolloverResult(RolloverStatus.NoChange);
                if (active is null)
                {
                    Run(connection, "INSERT INTO checkpoint VALUES(1,$next,$next);", current, null, now);
                    return new RolloverResult(RolloverStatus.Initialized);
                }
                CommitResult commit = commitBarrier.TryCommitPending();
                if (commit != CommitResult.Committed)
                    throw new CommitRejectedException(commit);
                var day = HistoryDay.Parse(active);
                int carried = 0, archived = 0;
                bool exists = Convert.ToInt64(Scalar(connection, "SELECT count(*) FROM snapshots WHERE day=$day;", day)) != 0;
                if (!exists)
                {
                    // Include the parent of an individually deleted item even if the parent was deleted on another day.
                    Run(connection, """
                        INSERT INTO snapshot_notes (day, note_id, title, color, sort_order, x, y, width, height, display_device_hint,
                        dock_edge, dock_order, saved_level, free_x, free_y, free_width, free_height, automatic_height, collapsed,
                        created_at, updated_at, deleted_at, deleted)
                        SELECT $day, n.id, n.title, n.color, n.sort_order, n.x, n.y, n.width, n.height, n.display_device_hint,
                        n.dock_edge, n.dock_order, n.saved_level, n.free_x, n.free_y, n.free_width, n.free_height, n.automatic_height,
                        n.collapsed, n.created_at, n.updated_at, n.deleted_at, n.deleted_at IS NOT NULL FROM notes n
                        WHERE n.deleted_at IS NULL OR n.id IN (SELECT note_id FROM pending_deleted_notes WHERE day<=$day)
                        OR n.id IN (SELECT i.note_id FROM items i JOIN pending_deleted_items p ON p.item_id=i.id WHERE p.day<=$day AND i.archived_day IS NULL);
                        INSERT INTO snapshot_items (day, item_id, note_id, text, completed, struck, sort_order, archived_day,
                        created_at, updated_at, deleted_at, deleted, carried_to)
                        SELECT $day, i.id, i.note_id, i.text, i.completed, i.struck, i.sort_order, i.archived_day, i.created_at,
                        i.updated_at, i.deleted_at, i.deleted_at IS NOT NULL,
                        CASE WHEN i.deleted_at IS NULL AND n.deleted_at IS NULL AND NOT i.completed AND NOT i.struck THEN $next END
                        FROM items i JOIN notes n ON n.id=i.note_id WHERE i.archived_day IS NULL AND
                        ((i.deleted_at IS NULL AND n.deleted_at IS NULL) OR i.id IN (SELECT item_id FROM pending_deleted_items WHERE day<=$day));
                        """, current, day, now);
                    carried = Convert.ToInt32(Scalar(connection, "SELECT count(*) FROM snapshot_items WHERE day=$day AND carried_to IS NOT NULL;", day));
                    archived = Run(connection, """
                        UPDATE items SET archived_day=$day WHERE archived_day IS NULL AND (completed OR struck)
                        AND id IN (SELECT item_id FROM snapshot_items WHERE day=$day);
                        """, current, day, now);
                    Run(connection, "INSERT INTO snapshots VALUES($day,$now);", current, day, now);
                }
                Run(connection, """
                    DELETE FROM pending_deleted_items WHERE day<$next;
                    DELETE FROM pending_deleted_notes WHERE day<$next;
                    UPDATE checkpoint SET active_day=$next,high_water=$next WHERE singleton=1;
                    """, current, day, now);
                return new RolloverResult(RolloverStatus.Sealed, day, carried, archived);
            });
            if (result.Status == RolloverStatus.Sealed)
                backup.Create(current);
            return result;
        }
        catch (CommitRejectedException exception)
        {
            if (exception.Result == CommitResult.Failed)
                log.Warn("Business day rollover commit barrier failed; checkpoint unchanged.");
            return new(exception.Result == CommitResult.Composing ? RolloverStatus.Deferred : RolloverStatus.Failed);
        }
        catch (Exception exception)
        {
            log.Error("Business day rollover failed.", exception);
            return new(RolloverStatus.Failed, Error: exception);
        }
    }

    private static object? Scalar(SqliteConnection connection, string sql, HistoryDay? day = null)
    {
        using var command = connection.CreateCommand();
        command.CommandText = sql;
        command.Parameters.AddWithValue("$day", day?.ToString() ?? (object)DBNull.Value);
        return command.ExecuteScalar();
    }

    private static int Run(SqliteConnection connection, string sql, HistoryDay next, HistoryDay? day, DateTimeOffset now)
    {
        using var command = connection.CreateCommand();
        command.CommandText = sql;
        command.Parameters.AddWithValue("$next", next.ToString());
        command.Parameters.AddWithValue("$day", day?.ToString() ?? (object)DBNull.Value);
        command.Parameters.AddWithValue("$now", now.ToUnixTimeMilliseconds());
        return command.ExecuteNonQuery();
    }
}
