using DeskNodes.App.Platform;

namespace DeskNodes.Core.Tests;

public sealed class FileLogTests
{
    [Theory]
    [InlineData(1_048_575)]
    [InlineData(1_048_576)]
    public void ConcurrentWritesAcrossRotationRetainEveryEntryOnce(int initialBytes)
    {
        using var directory = new TestDirectory();
        string folder = Path.Combine(directory.DirectoryPath, "Logs");
        Directory.CreateDirectory(folder);
        string path = Path.Combine(folder, "DeskNodes.log");
        string seed = new('s', initialBytes - 1);
        File.WriteAllText(path, seed + "\n");
        File.WriteAllText(path + ".1", "old backup\n");
        var log = new FileLog(directory.DirectoryPath, new ActionClock());
        string[] entries = Enumerable.Range(0, 256)
            .Select(index => $"{TestData.Now:O} INFO entry-{index:D4}")
            .ToArray();

        Parallel.For(0, entries.Length, new ParallelOptions { MaxDegreeOfParallelism = 8 },
            index => log.Info($"entry-{index:D4}"));

        string[] backup = File.ReadAllLines(path + ".1");
        string[] current = File.ReadAllLines(path);
        Assert.Equal(seed, backup[0]);
        Assert.NotEmpty(current);
        Assert.Equal(entries.Order(), backup.Skip(1).Concat(current).Order());
        Assert.Equal(2, Directory.GetFiles(folder).Length);
    }

    [Fact]
    public void ConcurrentFirstWritesCreateDirectoryAndRetainEveryEntry()
    {
        using var directory = new TestDirectory();
        var log = new FileLog(directory.DirectoryPath, new ActionClock());

        Parallel.For(0, 128, new ParallelOptions { MaxDegreeOfParallelism = 8 },
            index => log.Warn($"entry-{index:D4}"));

        string path = Path.Combine(directory.DirectoryPath, "Logs", "DeskNodes.log");
        Assert.Equal(Enumerable.Range(0, 128)
            .Select(index => $"{TestData.Now:O} WARN entry-{index:D4}").Order(),
            File.ReadAllLines(path).Order());
        Assert.False(File.Exists(path + ".1"));
    }
}
