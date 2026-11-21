using DeskNodes.Core.Storage;
using Microsoft.Win32;

namespace DeskNodes.App.Platform;

internal sealed class LoginItemService
{
    private const string RunPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "DeskNodes";
    private string? UnavailableReason => LoginItemAvailability.UnavailableReason(
        Environment.GetEnvironmentVariable(DataDirectory.OverrideVariable), Environment.ProcessPath);
    public bool Available => UnavailableReason is null;
    public bool Enabled { get; private set; }
    public string Status { get; private set; } = "";
    public void Refresh()
    {
        if (UnavailableReason is { } reason)
        {
            Status = reason;
            Enabled = false;
            return;
        }
        using var key = Registry.CurrentUser.OpenSubKey(RunPath);
        Enabled = key?.GetValue(ValueName) is string;
        Status = Enabled ? "已写入注册项（系统可能在任务管理器中禁用）。" : "未写入登录启动项。";
    }
    public void SetEnabled(bool enabled)
    {
        if (UnavailableReason is { } reason)
            throw new InvalidOperationException(reason);
        using var key = Registry.CurrentUser.CreateSubKey(RunPath, writable: true);
        if (enabled)
        {
            string path = Environment.ProcessPath!;
            key.SetValue(ValueName, $"\"{path}\"", RegistryValueKind.String);
        }
        else
            key.DeleteValue(ValueName, throwOnMissingValue: false);
        Refresh();
    }
}
