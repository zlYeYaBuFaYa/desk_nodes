using DeskNodes.Core.Storage;

namespace DeskNodes.Core.Presentation;

/// <summary>Persists local preferences before database commit and compensates on rollback.</summary>
public sealed class CombinedCommitCoordinator(DeskNodesDatabase database)
{
    public void Commit(Action writeDatabase, Action savePreferences, Action restorePreferences, Action? publishPreferences = null)
    {
        database.Transaction(_ =>
        {
            writeDatabase();
            savePreferences();
            database.OnOuterRolledBack(restorePreferences);
            if (publishPreferences is not null)
                database.OnOuterCommitted(publishPreferences);
        });
    }
}
