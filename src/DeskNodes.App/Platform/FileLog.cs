using System.IO;
using DeskNodes.Core.Services;
using DeskNodes.Core.Domain;
namespace DeskNodes.App.Platform;

internal sealed class FileLog(string directory, IClock clock) : IDeskNodesLog
{
    public void Info(string message) => Write("INFO", message);
    public void Warn(string message) => Write("WARN", message);
    public void Error(string message, Exception exception) => Write("ERROR", message + Environment.NewLine + exception);
    private void Write(string level, string message)
    {
        try
        {
            string folder = Path.Combine(directory, "Logs");
            Directory.CreateDirectory(folder);
            string path = Path.Combine(folder, "DeskNodes.log");
            if (File.Exists(path) && new FileInfo(path).Length >= 1_048_576)
                File.Move(path, path + ".1", true);
            File.AppendAllText(path, $"{clock.UtcNow:O} {level} {message}{Environment.NewLine}");
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            System.Diagnostics.Trace.WriteLine(ex);
        }
    }
}
