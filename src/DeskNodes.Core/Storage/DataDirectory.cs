namespace DeskNodes.Core.Storage;

public static class DataDirectory
{
    public const string OverrideVariable = "DESKNODES_DATA_DIR";
    public const string DatabaseFileName = "DeskNodes.sqlite3";

    public static string Resolve() => Resolve(Environment.GetEnvironmentVariable(OverrideVariable),
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData));

    // Explicit inputs allow isolated configurations without mutating process-wide environment state.
    public static string Resolve(string? directoryOverride, string localApplicationData)
    {
        if (!string.IsNullOrWhiteSpace(directoryOverride))
            return Path.TrimEndingDirectorySeparator(Path.GetFullPath(directoryOverride));
        if (string.IsNullOrWhiteSpace(localApplicationData))
            throw new InvalidOperationException("无法解析本地应用数据目录，请设置 DESKNODES_DATA_DIR。");
        return Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.Combine(localApplicationData, "DeskNodes")));
    }
}
