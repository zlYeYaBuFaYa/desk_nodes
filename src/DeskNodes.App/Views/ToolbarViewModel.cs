using System.ComponentModel;
using System.Windows.Controls;
using System.Windows.Input;
using DeskNodes.Core.Presentation;

namespace DeskNodes.App.Views;

internal sealed class RelayCommand(Action execute, Func<bool>? canExecute = null) : ICommand
{
    public event EventHandler? CanExecuteChanged;
    public void RaiseCanExecuteChanged() => CanExecuteChanged?.Invoke(this, EventArgs.Empty);
    public bool CanExecute(object? parameter) => canExecute?.Invoke() ?? true;
    public void Execute(object? parameter) => execute();
}

internal sealed record ToolbarActionViewModel(string Icon, string Label, bool IsEnabled, ICommand Command, string AutomationName);
internal sealed record ToolbarHandleViewModel;
internal sealed record ToolbarCountViewModel(string CountText, bool IsEnabled, ICommand Command);
internal sealed record ToolbarPagingViewModel(string PageText, bool CanPrev, bool CanNext, ICommand Prev, ICommand Next);

internal sealed class ToolbarViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    public Orientation Orientation { get; private set; }
    public bool HandleAtEnd { get; private set; }
    public IReadOnlyList<ToolbarActionViewModel> Actions { get; private set; } = [];
    public IReadOnlyList<object> Parts { get; private set; } = [];
    public int NoteCount { get; private set; }
    public string CountText => $"{NoteCount} 张";
    public ToolbarPagingViewModel Paging { get; private set; } = null!;
    public bool Round { get; set; }
    public bool Collapsed { get; private set; }
    public bool Raised { get; private set; }
    public string BadgeText => CollapseGeometry.Badge(NoteCount) ?? "";
    public bool BadgeVisible => Round && Collapsed && NoteCount > 0;
    public void Update(AppCoordinator app, bool atEnd, Action<Action> operate)
    {
        Orientation = app.Preferences.Orientation == ToolbarOrientation.Vertical ? Orientation.Vertical : Orientation.Horizontal;
        HandleAtEnd = atEnd;
        NoteCount = app.NoteCount;
        Collapsed = app.Preferences.DeskCollapsed;
        Raised = app.Raised;
        ICommand Command(Action action) => new RelayCommand(() => operate(action));
        ToolbarActionViewModel Action(string icon, string label, Action action, bool enabled) => new(icon, label, enabled, Command(action), label);
        bool manage = ToolbarRules.CanManage(NoteCount);
        Actions = [Action("\uE710", "新建", app.CreateNote, true), Action("\uE8F4", Raised ? "放回" : "浮起", app.ToggleRaised, manage),
            Action("\uE8A9", "整理", app.Arrange, manage), Action("\uE8B4", Collapsed ? "展开" : "收起", app.ToggleCollapsed, manage)];
        int last = app.Preferences.Pages.Values.DefaultIfEmpty().Max();
        var paging = ToolbarRules.PagingAvailability(NoteCount, app.Preferences.Page, last);
        Paging = new($"{app.Preferences.Page + 1}/{last + 1}", paging.Previous, paging.Next,
            Command(() => app.ChangePage(-1)), Command(() => app.ChangePage(1)));
        var parts = new List<object>();
        parts.AddRange(Actions);
        parts.Add(new ToolbarCountViewModel(CountText, manage, Command(app.ToggleCollapsed)));
        if (last > 0) parts.Add(Paging);
        Parts = atEnd ? parts.AsEnumerable().Reverse().ToArray() : parts;
        PropertyChanged?.Invoke(this, new(null));
    }
}
