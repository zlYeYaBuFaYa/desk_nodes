using DeskNodes.Core.Domain;
using DeskNodes.Core.Storage;

namespace DeskNodes.Core.Services;

public sealed class AutomaticBackupService(DeskNodesDatabase database, string dataDirectory, IDeskNodesLog log)
{
    public void Create(HistoryDay currentDay)
    {
        string? partial = null;
        try
        {
            database.Read(connection =>
            {
                string directory = Path.Combine(dataDirectory, "Backups");
                Directory.CreateDirectory(directory);
                partial = Path.Combine(directory, $".partial-{Guid.NewGuid():D}.sqlite3");
                using var command = connection.CreateCommand();
                command.CommandText = "VACUUM INTO $path;";
                command.Parameters.AddWithValue("$path", partial);
                command.ExecuteNonQuery();
                // The date identifies the newly entered business day represented by this post-rollover copy.
                string target = Path.Combine(directory, $"DeskNodes-{currentDay}.sqlite3");
                try { File.Move(partial, target, overwrite: false); }
                catch (IOException) when (File.Exists(target)) { File.Delete(partial); }
                var copies = Directory.EnumerateFiles(directory)
                    .Where(path => IsBackupName(Path.GetFileName(path)))
                    .OrderByDescending(Path.GetFileName, StringComparer.Ordinal).Skip(7).ToArray();
                foreach (string copy in copies)
                    File.Delete(copy);
                return 0;
            });
            log.Info($"Automatic backup checked for {currentDay}.");
        }
        catch (Exception exception)
        {
            log.Error("Automatic backup failed.", exception);
        }
        finally
        {
            try { if (partial is not null && File.Exists(partial)) File.Delete(partial); }
            catch (Exception exception) { log.Warn($"Cannot remove partial backup: {exception.Message}"); }
        }
    }

    private static bool IsBackupName(string name) => name.Length == 28 &&
        name.StartsWith("DeskNodes-", StringComparison.Ordinal) && name.EndsWith(".sqlite3", StringComparison.Ordinal) &&
        HistoryDay.TryParse(name.Substring(10, 10), out _);
}
