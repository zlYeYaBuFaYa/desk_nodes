using System.ComponentModel;
using System.Globalization;
using System.Windows;
using DeskNodes.Core.Domain;
using DeskNodes.Core.Services;
using DeskNodes.Core.Presentation;

namespace DeskNodes.App.Views;

internal sealed record CalendarCell(HistoryDay? Day, string Label, string ShadeKey, double Opacity, bool Selected, bool Today, bool InMonth, string Status)
{
    public string AccessibleName => Day?.Value.ToString("yyyy年M月d日", CultureInfo.InvariantCulture) ?? "";
}
internal sealed record HistoryItemView(string Text, HistoryItemState State, bool Struck, string? Carry);
internal sealed record HistoryNoteView(string Title, string ColorKey, bool Deleted, IReadOnlyList<HistoryItemView> Items);
internal sealed record DeletedEntryView(DeletedEntry Entry, string ColorKey, string Time, string Preview, bool CanRestore, string Explanation);
internal sealed class HistoryViewModel(AppCoordinator app) : INotifyPropertyChanged
{
    private readonly HistoryMonthCache months = new(app.History.MonthStats);
    private long generation;
    public event PropertyChangedEventHandler? PropertyChanged;
    public CalendarNavigator Navigator { get; } = new(app.BusinessDays.Current, app.BusinessDays.Current);
    public string MonthTitle => Navigator.SelectedDay.Value.ToString("yyyy年M月", CultureInfo.InvariantCulture);
    public string DayTitle => Navigator.SelectedDay.Value.ToString("yyyy年M月d日", CultureInfo.InvariantCulture);
    public bool CanToday => !Navigator.IsTodayDisabled;
    public string MonthRate { get; private set; } = "—";
    public IReadOnlyList<CalendarCell> Cells { get; private set; } = [];
    public IReadOnlyList<HistoryNoteView> Notes { get; private set; } = [];
    public IReadOnlyList<DeletedEntryView> DeletedNotes { get; private set; } = [];
    public IReadOnlyList<DeletedEntryView> DeletedItems { get; private set; } = [];
    public Visibility Empty { get; private set; } = Visibility.Collapsed;
    public Visibility Failure { get; private set; } = Visibility.Collapsed;
    public Visibility DeletedEmpty { get; private set; } = Visibility.Collapsed;
    public string Error { get; private set; } = "";
    public void Invalidate() => generation++;
    public void Reload(bool deleted)
    {
        long request = ++generation;
        long dataGeneration = app.HistoryGeneration;
        months.Invalidate(dataGeneration);
        var MonthRate = this.MonthRate;
        var Cells = this.Cells;
        var Notes = this.Notes;
        var DeletedNotes = this.DeletedNotes;
        var DeletedItems = this.DeletedItems;
        var Empty = this.Empty;
        var Failure = this.Failure;
        var DeletedEmpty = this.DeletedEmpty;
        var Error = this.Error;
        Failure = Visibility.Collapsed;
        Empty = Visibility.Collapsed;
        DeletedEmpty = Visibility.Collapsed;
        Error = "";
        try
        {
            Navigator.ReloadToday(app.BusinessDays.Current);
            if (deleted)
            {
                var existingNotes = app.Repository.GetNotes().Select(n => n.Id).ToHashSet();
                var entries = app.Deleted.List().Select(entry =>
                {
                    var projection = HistoryRules.ProjectDeleted(entry, existingNotes);
                    return new DeletedEntryView(entry, HistoryRules.ColorKey(entry.Color),
                        HistoryRules.DeletedTime(entry.DeletedAt, app.Clock.UtcNow, app.Clock.TimeZone),
                        projection.Preview, projection.CanRestore, projection.Explanation);
                }).ToArray();
                DeletedNotes = entries.Where(e => e.Entry.Member.NoteId is not null).ToArray();
                DeletedItems = entries.Where(e => e.Entry.Member.ItemId is not null).ToArray();
                DeletedEmpty = entries.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
            }
            else
            {
                var date = Navigator.SelectedDay.Value;
                var stats = months.Get(date.Year, date.Month) ?? throw new InvalidOperationException("历史数据已更新，请重试。");
                MonthRate = stats.Progress.Total == 0 ? "—" : $"{100.0 * stats.Progress.Completed / stats.Progress.Total:0}%";
                var grid = Navigator.MonthGrid();
                var gridStats = grid.Where(d => d is not null).Select(d => (d!.Value.Value.Year, d.Value.Value.Month))
                    .Distinct().SelectMany(m => m.Year == date.Year && m.Month == date.Month ? stats.Days : (months.Get(m.Year, m.Month) ?? throw new InvalidOperationException("历史数据已更新，请重试。")).Days)
                    .ToDictionary(s => s.Day);
                Cells = grid.Select(day =>
                {
                    var stat = day is { } cellDay ? gridStats.GetValueOrDefault(cellDay) : null;
                    var shade = HistoryQueries.Shade(stat is not null, stat?.Progress.Rate);
                    var paint = HistoryQueries.Paint(shade, SystemParameters.HighContrast);
                    return new CalendarCell(day, day?.Value.Day.ToString(CultureInfo.InvariantCulture) ?? "", paint.Key,
                        paint.Opacity, day == Navigator.SelectedDay, day == Navigator.CurrentBusinessDay, day?.Value.Month == date.Month,
                        HistoryQueries.DayStatus(day == Navigator.CurrentBusinessDay, stat is not null, stat?.Progress.Rate));
                }).ToArray();
                var snapshot = app.History.DaySnapshot(Navigator.SelectedDay);
                Notes = snapshot.Notes.Select(n => new HistoryNoteView(n.Note.Title, HistoryRules.ColorKey(n.Note.Color), n.Deleted,
                    n.Items.Select(i =>
                    {
                        var projection = HistoryRules.ProjectItem(i.Deleted, i.Item.Struck, i.Item.Completed, i.CarriedTo);
                        return new HistoryItemView(i.Item.Text, projection.State, i.Item.Struck, projection.Carry);
                    }).ToArray())).ToArray();
                Empty = !snapshot.HasSnapshot ? Visibility.Visible : Visibility.Collapsed;
            }
        }
        catch (Exception ex)
        {
            Notes = [];
            DeletedNotes = [];
            DeletedItems = [];
            Cells = [];
            MonthRate = "—";
            Error = "无法读取历史记录，请重试。";
            Failure = Visibility.Visible;
            app.Log.Error("无法读取历史窗口。", ex);
        }
        if (request != generation || dataGeneration != app.HistoryGeneration)
            return;
        this.MonthRate = MonthRate;
        this.Cells = Cells;
        this.Notes = Notes;
        this.DeletedNotes = DeletedNotes;
        this.DeletedItems = DeletedItems;
        this.Empty = Empty;
        this.Failure = Failure;
        this.DeletedEmpty = DeletedEmpty;
        this.Error = Error;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(null));
    }
}
