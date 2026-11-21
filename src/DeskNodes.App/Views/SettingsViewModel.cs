using System.ComponentModel;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using DeskNodes.App.Themes;
using DeskNodes.Core.Presentation;

namespace DeskNodes.App.Views;

internal sealed class FontCardViewModel : INotifyPropertyChanged
{
    private readonly SettingsViewModel owner;
    public event PropertyChangedEventHandler? PropertyChanged;
    public void RefreshSelection() => PropertyChanged?.Invoke(this, new(nameof(IsSelected)));
    public NoteFont Value { get; }
    public string Label { get; }
    public FontFamily Family { get; }
    public string Status { get; }
    public string AccessibleName { get; }
    public bool IsSelected => owner.Font == Value;
    public ICommand Select { get; }
    public FontCardViewModel(SettingsViewModel owner, SettingsOption<NoteFont> option, NoteFonts fonts)
    {
        this.owner = owner;
        Value = option.Value;
        Label = option.Label;
        var mapping = fonts.Resolve(Value);
        Family = new(mapping.Family);
        Status = mapping.Available ? " " : Value == NoteFont.Wenkai ? "未包含" : "未安装";
        AccessibleName = string.IsNullOrWhiteSpace(Status) ? Label : $"{Label}，{Status.Trim()}";
        Select = new RelayCommand(() => owner.Font = Value);
    }
}

internal sealed partial class SettingsViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly AppCoordinator app;
    private readonly Dispatcher dispatcher;
    private bool disposed;
    private readonly NoteFonts fonts = new();
    private string rolloverText;
    public event PropertyChangedEventHandler? PropertyChanged;
    public string Error => app.LastError;
    public string RolloverError { get; private set; } = "";
    public string RolloverText
    {
        get => rolloverText;
        set
        {
            if (rolloverText == value)
                return;
            rolloverText = value;
            RolloverError = "";
            PropertyChanged?.Invoke(this, new(nameof(RolloverText)));
            PropertyChanged?.Invoke(this, new(nameof(RolloverError)));
        }
    }
    public ICommand CommitRollover { get; }
    public ICommand ResetHome { get; }
    public ICommand OpenLicense { get; }
    public IReadOnlyList<FontCardViewModel> FontCards { get; }
    public bool CanResetHome => new SettingsState(app.Preferences).CanResetHome;
    public double HomeX => SettingsState.HomePreview(app.Preferences.Home, 180, 96).X - 6;
    public double HomeY => SettingsState.HomePreview(app.Preferences.Home, 180, 96).Y - 6;
    public FontFamily SampleFamily => new(fonts.Resolve(Font).Family);
    public void RefreshTextScale() => PropertyChanged?.Invoke(this, new(nameof(SampleSize)));
    public double SampleSize => NoteTypography.For(TextSize, app.TextScale).Body;
    public Appearance Appearance
    {
        get => app.Preferences.Appearance;
        set => Apply(p => p with { Appearance = value });
    }
    public NoteTextSize TextSize
    {
        get => app.Preferences.TextSize;
        set => Apply(p => p with { TextSize = value });
    }
    public ToolbarOrientation Orientation
    {
        get => app.Preferences.Orientation;
        set => Apply(p => p with { Orientation = value });
    }
    public AutoShrink AutoShrink
    {
        get => app.Preferences.AutoShrink;
        set => Apply(p => p with { AutoShrink = value });
    }
    public int NewWidth
    {
        get => app.Preferences.NewWidth;
        set => Apply(p => p with { NewWidth = value });
    }
    public int NewHeight
    {
        get => app.Preferences.NewHeight;
        set => Apply(p => p with { NewHeight = value });
    }
    public NoteFont Font
    {
        get => app.Preferences.Font;
        set => Apply(p => p with { Font = value });
    }
    public bool KeepToolbarExpanded
    {
        get => app.Preferences.KeepToolbarExpanded;
        set => Apply(p => p with { KeepToolbarExpanded = value });
    }
    public bool ReduceMotion
    {
        get => app.Preferences.ReduceMotion;
        set => Apply(p => p with { ReduceMotion = value });
    }
    public SettingsViewModel(AppCoordinator app, Action openLicense, Dispatcher dispatcher)
    {
        this.app = app;
        this.dispatcher = dispatcher;
        InitializeSystemCommands();
        FontCards = SettingsOptions.Fonts.Select(o => new FontCardViewModel(this, o, fonts)).ToArray();
        rolloverText = SavedTime();
        CommitRollover = new RelayCommand(CommitTime);
        ResetHome = new RelayCommand(() => Apply(p => p with { Home = new() }));
        OpenLicense = new RelayCommand(() => Execute(openLicense));
        app.PreferencesChanged += Changed;
        app.ErrorChanged += Changed;
    }
    private string SavedTime() => $"{app.RolloverMinutes / 60:00}:{app.RolloverMinutes % 60:00}";
    private void CommitTime()
    {
        if (!SettingsState.TryParseTime(rolloverText, out int minutes))
            RolloverError = "请输入 00:00–23:59，格式 HH:mm。已恢复保存值。";
        else
        {
            if (minutes != app.RolloverMinutes)
            {
                RolloverError = "";
                Execute(() => app.SetRolloverMinutes(minutes));
            }
        }
        rolloverText = SavedTime();
        Changed(this, EventArgs.Empty);
    }
    private void Apply(Func<LocalPreferences, LocalPreferences> change)
    {
        var before = app.Preferences;
        var requested = change(before);
        Execute(() => app.SavePreferences(requested));
        if (requested != before && app.Preferences == before)
            QueueRejectedChange();
        Changed(this, EventArgs.Empty);
    }
    private void QueueRejectedChange()
    {
        if (disposed || dispatcher.HasShutdownStarted)
            return;
        dispatcher.BeginInvoke(DispatcherPriority.Background, () =>
        {
            if (!disposed)
                Changed(this, EventArgs.Empty);
        });
    }
    private void Execute(Action action)
    {
        try
        {
            action();
        }
        catch (Exception exception)
        {
            app.Log.Error("设置操作失败。", exception);
            app.RecordError("无法完成设置操作，请稍后重试。字体不可用或正在输入时，请先检查字体并结束输入。详细信息已记录到日志。");
        }
    }
    private void Changed(object? sender, EventArgs e)
    {
        foreach (var card in FontCards)
            card.RefreshSelection();
        PropertyChanged?.Invoke(this, new(null));
    }
    public void Dispose()
    {
        disposed = true;
        app.PropertyChanged -= DataOperationChanged;
        app.Hotkeys.Recorded -= CaptureRegisteredGesture;
        app.PreferencesChanged -= Changed;
        app.ErrorChanged -= Changed;
    }
}
