namespace DeskNodes.Core.Services;

public interface IDeskNodesLog
{
    void Info(string message);
    void Warn(string message);
    void Error(string message, Exception exception);
}

public enum CommitResult { Committed, Composing, Failed }

/// <summary>Called inside the outer transaction. Implementations may write valid edits through nested repository calls.</summary>
public interface ICommitBarrier
{
    CommitResult TryCommitPending();
}
