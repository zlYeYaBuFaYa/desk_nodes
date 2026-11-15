using System.IO;
using DeskNodes.Core.Storage;

namespace DeskNodes.App;

/// <summary>Owns the startup store lifetime and releases it on explicit application shutdown.</summary>
internal sealed class AppCoordinator
{
    private DeskNodesDatabase? database;
    public string? DataDirectoryPath { get; private set; }

    public void Start()
    {
        if (database is not null)
            throw new InvalidOperationException("DeskNodes 已启动。");
        DataDirectoryPath = DataDirectory.Resolve();
        database = DeskNodesDatabase.Open(Path.Combine(DataDirectoryPath, DataDirectory.DatabaseFileName));
    }

    public void Stop()
    {
        database?.Dispose();
        database = null;
    }
}
