namespace DeskNodes.Core.Storage;

public enum DatabaseCompatibilityFailure { ForeignDatabase, FutureVersion, UnsupportedSchema }

public sealed class DatabaseCompatibilityException : Exception
{
    public DatabaseCompatibilityFailure Failure { get; }

    public DatabaseCompatibilityException(DatabaseCompatibilityFailure failure, string message) : base(message)
        => Failure = failure;
}
