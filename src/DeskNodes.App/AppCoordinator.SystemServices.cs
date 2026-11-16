using System.IO;
using System.Threading.Tasks;
using System.Windows;
using DeskNodes.App.Platform;
using DeskNodes.Core.Backup;
using DeskNodes.Core.Services;
using DeskNodes.Core.Storage;
using Microsoft.Win32;

namespace DeskNodes.App;

internal sealed partial class AppCoordinator
{
    private SystemServiceWindow? systemWindow;
    private BusinessPreferencesStore businessStore = null!;
    private bool dataOperation;
    public AnimationPolicy Animations { get; private set; } = null!;
    public HotkeyService Hotkeys { get; private set; } = null!;
    public LoginItemService Login { get; } = new();
    public BusinessPreferences BusinessPreferences { get; private set; } = new();
    public void ResetIdle() => toolbar?.ResetIdle();
    public void CheckSystemDay()
    {
        if (dataOperation)
            return;
        systemWindow?.RefreshTimeZone();
        var result = rollover.CheckAndAdvance();
        if (result.Status == RolloverStatus.Sealed)
        {
            Refresh();
            historyWindow?.Reload();
        }
        if (result.Status == RolloverStatus.Failed)
            Presentation.Error("跨天处理失败，当前内容已保留。稍后将重试。");
        Presentation.Refresh();
    }
    private void RegisterInitialHotkeys()
    {
        foreach (var action in Enum.GetValues<HotkeyAction>())
        {
            try
            {
                using var candidate = Hotkeys.Prepare(action, action == HotkeyAction.NewNote ? BusinessPreferences.HotkeyNew : BusinessPreferences.HotkeyFloat);
                candidate.Commit();
            }
            catch (Exception exception)
            {
                Hotkeys.MarkConflict(action, action == HotkeyAction.NewNote ? BusinessPreferences.HotkeyNew : BusinessPreferences.HotkeyFloat!);
                Log.Error("注册快捷键失败。", exception);
                RecordError("快捷键被占用，请在设置中更换组合；仍可使用工具条和托盘。");
            }
        }
    }
    public void SetHotkey(HotkeyAction action, string? text)
    {
        var value = (action == HotkeyAction.NewNote ? BusinessPreferences with { HotkeyNew = text ?? "" } :
            BusinessPreferences with { HotkeyFloat = text }).Validate();
        using var candidate = Hotkeys.Prepare(action, action == HotkeyAction.NewNote ? value.HotkeyNew : value.HotkeyFloat);
        businessStore.Save(value);
        candidate.Commit();
        BusinessPreferences = value;
        PreferencesChanged?.Invoke(this, EventArgs.Empty);
    }
    public void RefreshLoginStatus()
    {
        try
        {
            Login.Refresh();
        }
        catch (Exception exception)
        {
            Log.Error("读取登录启动状态失败。", exception);
            RecordError("无法读取登录启动状态，请检查当前用户的注册表权限。");
        }
    }
    public void SetLogin(bool enabled)
    {
        Login.SetEnabled(enabled);
        var value = BusinessPreferences with { LoginPromptAnswered = true, LoginIntent = enabled };
        businessStore.Save(value);
        BusinessPreferences = value;
        PreferencesChanged?.Invoke(this, EventArgs.Empty);
    }
    private void PromptLogin()
    {
        if (!Login.Available || BusinessPreferences.LoginPromptAnswered)
            return;
        ShowToolbar();
        var prompt = new Views.LoginPromptWindow(this);
        prompt.ShowDialog();
    }
    public void AnswerLogin(bool enabled)
    {
        if (enabled)
            SetLogin(true);
        else
        {
            var value = BusinessPreferences with { LoginPromptAnswered = true, LoginIntent = false };
            businessStore.Save(value);
            BusinessPreferences = value;
        }
    }
    private bool CommitForDataOperation()
    {
        if (Editors.TryCommitPending() == CommitResult.Committed)
            return true;
        RecordError("请先结束输入法组词并保存当前编辑，再导出或导入。");
        return false;
    }
    public void ExportData()
    {
        if (dataOperation || !CommitForDataOperation())
            return;
        dataOperation = true;
        try
        {
            var backup = WindowsBackupCodec.Export(database!, Clock);
            var dialog = new SaveFileDialog
            {
                Title = "导出 DeskNodes 数据",
                Filter = "DeskNodes JSON 备份 (*.json)|*.json",
                FileName = $"DeskNodes-{Clock.UtcNow:yyyy-MM-dd}.json",
                AddExtension = true,
                DefaultExt = ".json"
            };
            if (dialog.ShowDialog(settingsWindow!) == true)
                WindowsBackupCodec.Publish(dialog.FileName, backup);
        }
        catch (Exception exception)
        {
            Log.Error("导出数据失败。", exception);
            RecordError("导出失败，原文件已保留。请检查保存位置和可用磁盘空间。");
        }
        finally
        {
            dataOperation = false;
        }
    }
    public async void ImportData()
    {
        if (dataOperation || !CommitForDataOperation())
            return;
        dataOperation = true;
        bool replaced = false;
        string stagingPath = Path.Combine(DataDirectoryPath!, $".import-{Guid.NewGuid():N}.sqlite3");
        try
        {
            var dialog = new OpenFileDialog { Title = "导入 DeskNodes 数据", Filter = "DeskNodes JSON 备份 (*.json)|*.json" };
            if (dialog.ShowDialog(settingsWindow!) != true)
                return;
            string sourcePath = dialog.FileName;
            using var staging = await Task.Run(() =>
            {
                using var stream = File.OpenRead(sourcePath);
                var backup = WindowsBackupCodec.Parse(stream);
                return WindowsBackupCodec.Stage(backup, stagingPath);
            });
            if (database is null)
                return;
            var incoming = new BusinessPreferencesStore(staging).Load();
            if (MessageBox.Show(settingsWindow!, "替换全部本机数据？此操作无法撤销。系统登录启动项保持当前状态。",
                "导入 DeskNodes 数据", MessageBoxButton.OKCancel, MessageBoxImage.Warning, MessageBoxResult.Cancel) != MessageBoxResult.OK)
                return;
            if (!CommitForDataOperation())
                return;
            using var candidate = Hotkeys.Prepare(HotkeyAction.NewNote, incoming.HotkeyNew);
            database!.ReplaceFrom(staging);
            replaced = true;
            candidate.Commit();
            BusinessPreferences = incoming;
            Undo.Clear();
            Editors.InvalidateAll();
            Presentation.ExitSelection();
            EndRaised();
            foreach (var window in windows.Values)
            {
                window.CloseForImport();
            }
            windows.Clear();
            try
            {
                using var raise = Hotkeys.Prepare(HotkeyAction.Raise, incoming.HotkeyFloat);
                raise.Commit();
            }
            catch (Exception exception)
            {
                Hotkeys.MarkConflict(HotkeyAction.Raise, incoming.HotkeyFloat!);
                Log.Error("导入已完成，浮起快捷键注册失败。", exception);
                RecordError("数据已导入；浮起快捷键被占用，未生效，请在设置中更换。");
            }
            Refresh();
            historyWindow?.Reload();
            PreferencesChanged?.Invoke(this, EventArgs.Empty);
        }
        catch (Exception exception)
        {
            Log.Error("导入数据失败。", exception);
            RecordError(exception is BackupLimitException ? exception.Message : replaced ? "数据已导入，但窗口刷新失败。请重新启动 DeskNodes。" :
                "导入失败，原数据和快捷键已保留。请检查备份格式、数据完整性和快捷键是否被占用。");
        }
        finally
        {
            dataOperation = false;
            foreach (string suffix in new[] { "", "-wal", "-shm" })
            {
                try
                {
                    File.Delete(stagingPath + suffix);
                }
                catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
                {
                    Log.Error("清理导入临时文件失败。", exception);
                }
            }
        }
    }
}
