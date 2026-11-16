using System.IO;

namespace DeskNodes.App.Platform;

internal static class LoginItemAvailability
{
    internal static string? UnavailableReason(string? directoryOverride, string? processPath)
    {
        if (!string.IsNullOrWhiteSpace(directoryOverride))
            return "隔离数据实例不能修改登录启动项。";
        if (string.IsNullOrWhiteSpace(processPath) || !Path.IsPathFullyQualified(processPath) ||
            processPath.Contains('"') ||
            string.Equals(Path.GetFileNameWithoutExtension(processPath), "dotnet", StringComparison.OrdinalIgnoreCase))
            return "请从稳定安装目录的 DeskNodes 可执行文件修改登录启动。";
        return null;
    }
}
