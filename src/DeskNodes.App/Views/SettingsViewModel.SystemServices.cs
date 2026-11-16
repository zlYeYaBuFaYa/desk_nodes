using System.Windows.Input;
using DeskNodes.Core.Services;

namespace DeskNodes.App.Views;

internal sealed partial class SettingsViewModel
{
    private HotkeyAction? recording;
    private string recorded = "";
    public string NewHotkey => recording == HotkeyAction.NewNote ? recorded : app.BusinessPreferences.HotkeyNew;
    public string FloatHotkey => recording == HotkeyAction.Raise ? recorded : app.BusinessPreferences.HotkeyFloat ?? "未设置";
    public string HotkeyError { get; private set; } = "";
    public string NewHotkeyStatus => app.Hotkeys.GetRegistration(HotkeyAction.NewNote).Message;
    public string FloatHotkeyStatus => app.Hotkeys.GetRegistration(HotkeyAction.Raise).Message;
    public string AltGrWarning => HotkeyGesture.AltGrWarning;
    public bool CanChangeLogin => app.Login.Available;
    public string LoginStatus => app.Login.Status;
    public bool LoginEnabled
    {
        get => app.Login.Enabled;
        set
        {
            Execute(() => app.SetLogin(value));
            Changed(this, EventArgs.Empty);
            if (LoginEnabled != value)
                QueueRejectedChange();
        }
    }
    public ICommand RecordNew { get; private set; } = null!;
    public ICommand RecordFloat { get; private set; } = null!;
    public ICommand ClearFloat { get; private set; } = null!;
    public ICommand ResetNew { get; private set; } = null!;
    public ICommand ResetFloat { get; private set; } = null!;
    public bool IsDataOperationBusy => app.IsDataOperationBusy;
    public RelayCommand Export { get; private set; } = null!;
    public RelayCommand Import { get; private set; } = null!;
    private void InitializeSystemCommands()
    {
        app.PropertyChanged += DataOperationChanged;
        app.RefreshLoginStatus();
        app.Hotkeys.Recorded += CaptureRegisteredGesture;
        RecordNew = new RelayCommand(() => BeginRecording(HotkeyAction.NewNote));
        RecordFloat = new RelayCommand(() => BeginRecording(HotkeyAction.Raise));
        ClearFloat = new RelayCommand(() => SaveHotkey(HotkeyAction.Raise, null));
        ResetNew = new RelayCommand(() => SaveHotkey(HotkeyAction.NewNote, HotkeyGesture.DefaultNew));
        ResetFloat = new RelayCommand(() => SaveHotkey(HotkeyAction.Raise, HotkeyGesture.DefaultFloat));
        Export = new RelayCommand(() =>
        {
            CancelRecording();
            app.ExportData();
        }, () => !IsDataOperationBusy);
        Import = new RelayCommand(async () =>
        {
            CancelRecording();
            try
            {
                await app.ImportDataAsync();
            }
            catch (Exception exception)
            {
                app.Log.Error("导入命令失败。", exception);
                app.RecordError("导入失败，请重试。");
            }
        }, () => !IsDataOperationBusy);
    }
    private void DataOperationChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(AppCoordinator.IsDataOperationBusy))
            return;
        Export.RaiseCanExecuteChanged();
        Import.RaiseCanExecuteChanged();
        PropertyChanged?.Invoke(this, new(nameof(IsDataOperationBusy)));
    }
    private void BeginRecording(HotkeyAction action)
    {
        recording = action;
        recorded = "请按组合键（Esc 取消）";
        HotkeyError = "";
        app.Hotkeys.Recording = true;
        Changed(this, EventArgs.Empty);
    }
    public void CancelRecording()
    {
        recording = null;
        app.Hotkeys.Recording = false;
        Changed(this, EventArgs.Empty);
    }
    private void CaptureRegisteredGesture(string gesture)
    {
        if (recording is { } action)
            SaveHotkey(action, gesture);
    }
    public void CaptureKey(KeyEventArgs e)
    {
        if (recording is not { } action)
            return;
        e.Handled = true;
        if (e.IsRepeat)
            return;
        Key key = e.Key == Key.System ? e.SystemKey : e.Key == Key.ImeProcessed ? e.ImeProcessedKey : e.Key;
        if (key == Key.Escape)
        {
            CancelRecording();
            return;
        }
        string modifiers = ((Keyboard.Modifiers & ModifierKeys.Control) != 0 ? "Ctrl+" : "") +
            ((Keyboard.Modifiers & ModifierKeys.Alt) != 0 ? "Alt+" : "") +
            ((Keyboard.Modifiers & ModifierKeys.Shift) != 0 ? "Shift+" : "") +
            ((Keyboard.Modifiers & ModifierKeys.Windows) != 0 ? "Win+" : "");
        bool modifier = key is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt or
            Key.LeftShift or Key.RightShift or Key.LWin or Key.RWin;
        string name = key is >= Key.D0 and <= Key.D9 ? ((int)(key - Key.D0)).ToString() : key.ToString();
        recorded = modifiers + (modifier ? "…" : name);
        if (!modifier)
        {
            if (HotkeyGesture.TryParse(recorded, out var gesture))
            {
                // Registered combinations are captured by WM_HOTKEY, never by both input paths.
                if (!app.Hotkeys.IsRegistered(gesture!))
                    SaveHotkey(action, gesture!.ToString());
            }
            else
                HotkeyError = "请使用包含 Ctrl 的字母、数字或空格组合，不支持 Win 键及系统保留键。";
        }
        Changed(this, EventArgs.Empty);
    }
    private void SaveHotkey(HotkeyAction action, string? value)
    {
        try
        {
            app.SetHotkey(action, value);
            HotkeyError = "";
            CancelRecording();
        }
        catch (Exception exception)
        {
            app.Log.Error("更改快捷键失败。", exception);
            HotkeyError = exception is FormatException ? "快捷键格式无效，请重新录制。" :
                "快捷键被占用或与另一快捷键相同，原快捷键已保留。请换一个组合。";
        }
        Changed(this, EventArgs.Empty);
    }
}
