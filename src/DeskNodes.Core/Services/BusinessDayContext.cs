using DeskNodes.Core.Domain;
using DeskNodes.Core.Storage;

namespace DeskNodes.Core.Services;

public sealed class BusinessDayContext(DeskNodesDatabase database, IClock clock)
{
    public HistoryDay Current => GetDay(clock.UtcNow);
    public HistoryDay GetDay(DateTimeOffset now) => database.Read(connection =>
    {
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT rollover_minutes FROM business_settings WHERE singleton=1;";
        return new BusinessDayCalculator().GetDay(now, clock.TimeZone, Convert.ToInt32(command.ExecuteScalar()));
    });
}
