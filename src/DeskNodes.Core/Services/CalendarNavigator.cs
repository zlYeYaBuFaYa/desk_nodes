using DeskNodes.Core.Domain;

namespace DeskNodes.Core.Services;

public sealed class CalendarNavigator(HistoryDay selectedDay, HistoryDay currentBusinessDay)
{
    public HistoryDay SelectedDay { get; private set; } = selectedDay;
    public HistoryDay CurrentBusinessDay { get; private set; } = currentBusinessDay;
    public bool IsTodayDisabled => SelectedDay == CurrentBusinessDay;
    public void ReloadToday(HistoryDay day) => CurrentBusinessDay = day;
    public void Select(HistoryDay day) => SelectedDay = day;
    public void Today() => SelectedDay = CurrentBusinessDay;
    public void MoveDay(int direction) => Move(direction, 1);
    public void MoveWeek(int direction) => Move(direction, 7);
    private void Move(int direction, int days)
    {
        ValidateDirection(direction);
        int current = CurrentBusinessDay.Value.DayNumber;
        int selected = SelectedDay.Value.DayNumber;
        if (direction > 0 && selected > current) return;
        int candidate = selected + direction * days;
        if (direction > 0 && candidate > current) candidate = current;
        int number = Math.Clamp(candidate, DateOnly.MinValue.DayNumber, DateOnly.MaxValue.DayNumber);
        SelectedDay = new(DateOnly.FromDayNumber(number));
    }
    public void MoveMonth(int direction)
    {
        ValidateDirection(direction);
        var first = new DateOnly(SelectedDay.Value.Year, SelectedDay.Value.Month, 1);
        if (direction < 0 && first.Year == 1 && first.Month == 1 || direction > 0 && first.Year == 9999 && first.Month == 12) return;
        SelectedDay = new(first.AddMonths(direction));
    }
    public IReadOnlyList<HistoryDay?> MonthGrid(bool sixWeeks = true)
    {
        var first = new DateOnly(SelectedDay.Value.Year, SelectedDay.Value.Month, 1);
        int offset = ((int)first.DayOfWeek + 6) % 7;
        int cells = sixWeeks ? 42 : ((offset + DateTime.DaysInMonth(first.Year, first.Month) + 6) / 7) * 7;
        return Enumerable.Range(0, cells).Select(i =>
        {
            int number = first.DayNumber - offset + i;
            return number < 0 || number > DateOnly.MaxValue.DayNumber ? (HistoryDay?)null : new HistoryDay(DateOnly.FromDayNumber(number));
        }).ToArray();
    }
    private static void ValidateDirection(int direction)
    {
        if (direction is not (-1 or 1)) throw new ArgumentOutOfRangeException(nameof(direction));
    }
}
