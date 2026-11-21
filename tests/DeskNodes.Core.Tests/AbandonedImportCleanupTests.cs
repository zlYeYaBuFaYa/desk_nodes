using DeskNodes.Core.Services;

namespace DeskNodes.Core.Tests;

public sealed class AbandonedImportCleanupTests
{
    [Fact]
    public void MissingDirectoryIsNotCreatedAndEmptyDirectoryIsUntouched()
    {
        using var directory = new TestDirectory();
        string missing = Path.Combine(directory.DirectoryPath, "missing");
        var errors = new List<Exception>();
        AbandonedImportCleanup.Run(missing, errors.Add);
        Assert.False(Directory.Exists(missing));
        AbandonedImportCleanup.Run(directory.DirectoryPath, errors.Add);
        Assert.Empty(Directory.GetFileSystemEntries(directory.DirectoryPath));
        Assert.Empty(errors);
    }

    [Theory]
    [InlineData(false, false)]
    [InlineData(true, false)]
    [InlineData(true, true)]
    public void OnlyStagingFilesAreDeletedAndDeniedDeletionDoesNotStopCleanup(bool denied, bool ioFailure)
    {
        using var directory = new TestDirectory();
        string[] staging = [".import-a.sqlite3", ".import-a.sqlite3-wal", ".import-a.sqlite3-shm"];
        string[] retained = ["DeskNodes.sqlite3", "DeskNodes.sqlite3-wal", "other.txt", ".import-a.sqlite3.backup"];
        foreach (string name in staging.Concat(retained))
            File.WriteAllText(Path.Combine(directory.DirectoryPath, name), "keep");
        var errors = new List<Exception>();
        AbandonedImportCleanup.Run(directory.DirectoryPath, errors.Add, path =>
        {
            if (denied && Path.GetFileName(path) == staging[0])
                throw ioFailure ? new IOException("locked") : new UnauthorizedAccessException("denied");
            File.Delete(path);
        });
        Assert.Equal(retained.Concat(denied ? [staging[0]] : Array.Empty<string>()).Order(),
            Directory.GetFiles(directory.DirectoryPath).Select(Path.GetFileName).Order());
        Assert.Equal(denied ? 1 : 0, errors.Count);
    }
}
