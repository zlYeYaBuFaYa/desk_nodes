using DeskNodes.Core.Storage;

namespace DeskNodes.Core.Services;

/// <summary>Confirms a saved buffer only when its enclosing transaction is durable.</summary>
public sealed class PendingCommitTracker(DeskNodesDatabase database)
{
    public void Save(Action save, Action committed, Action rolledBack)
    {
        database.Transaction(_ =>
        {
            save();
            database.OnOuterCommitted(committed);
            database.OnOuterRolledBack(rolledBack);
        });
    }
}
