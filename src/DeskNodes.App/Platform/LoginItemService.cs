using System.IO;
using Microsoft.Win32;

namespace DeskNodes.App.Platform;

internal sealed class LoginItemService
{
    private const string RunPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "DeskNodes";
    public bool Available => string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("DESKNODES_DATA_DIR"));
    public bool Enabled { get; private set; }
    public string Status { get; private set; } = "";
    public void Refresh()
    {
        if (!Available)
        {
            Status = "隔离数据实例不能修改登录启动项。";
            Enabled = false;
            return;
        }
        using var key = Registry.CurrentUser.OpenSubKey(RunPath);
        Enabled = key?.GetValue(ValueName) is string;
        Status = Enabled ? "已写入注册项（系统可能在任务管理器中禁用）。" : "未写入登录启动项。";
    }
    public void SetEnabled(bool enabled)
    {
        if (!Available)
            throw new InvalidOperationException("隔离数据实例不能修改登录启动项。");
        using var key = Registry.CurrentUser.CreateSubKey(RunPath, writable: true);
        if (enabled)
        {
            string path = Environment.ProcessPath ?? throw new InvalidOperationException("无法确定应用程序路径。");
            if (!Path.IsPathFullyQualified(path) || path.Contains('"') ||
                string.Equals(Path.GetFileNameWithoutExtension(path), "dotnet", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("请从稳定安装目录的 DeskNodes 可执行文件启用登录启动。");
            key.SetValue(ValueName, $"\"{path}\"", RegistryValueKind.String);
        }
        else
            key.DeleteValue(ValueName, throwOnMissingValue: false);
        Refresh();
    }
}
