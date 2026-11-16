namespace DeskNodes.Core.Services;

/// <summary>Best-effort removal of abandoned staging databases, never the live database.</summary>
public static class AbandonedImportCleanup
{
    public static void Run(string directory, Action<Exception> report, Action<string>? delete = null)
    {
        if (!Directory.Exists(directory))
            return;
        delete ??= File.Delete;
        try
        {
            foreach (string path in Directory.EnumerateFiles(directory, ".import-*.sqlite3*"))
            {
                string name = Path.GetFileName(path);
                if (!name.EndsWith(".sqlite3", StringComparison.Ordinal) &&
                    !name.EndsWith(".sqlite3-wal", StringComparison.Ordinal) &&
                    !name.EndsWith(".sqlite3-shm", StringComparison.Ordinal))
                    continue;
                try
                {
                    delete(path);
                }
                catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
                {
                    report(exception);
                }
            }
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            report(exception);
        }
    }
}
