using System.IO;
using DeskNodes.Core.Services;
using DeskNodes.Core.Domain;
namespace DeskNodes.App.Platform;

internal sealed class FileLog(string directory, IClock clock) : IDeskNodesLog
{
    private readonly object writeLock = new();

    public void Info(string message) => Write("INFO", message);
    public void Warn(string message) => Write("WARN", message);
    public void Error(string message, Exception exception) => Write("ERROR", message + Environment.NewLine + exception);
    private void Write(string level, string message)
    {
        try
        {
            string entry = $"{clock.UtcNow:O} {level} {message}{Environment.NewLine}";
            string folder = Path.Combine(directory, "Logs");
            string path = Path.Combine(folder, "DeskNodes.log");
            lock (writeLock)
            {
                Directory.CreateDirectory(folder);
                if (File.Exists(path) && new FileInfo(path).Length >= 1_048_576)
                    File.Move(path, path + ".1", true);
                File.AppendAllText(path, entry);
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            System.Diagnostics.Trace.WriteLine(ex);
        }
    }
}
