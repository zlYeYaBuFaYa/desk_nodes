namespace DeskNodes.Core.Presentation;

/// <summary>Publishes preferences only after durable storage succeeds.</summary>
public sealed class PreferencesState(LocalPreferences initial, Action<LocalPreferences> save)
{
    public LocalPreferences Value { get; private set; } = initial;
    public bool TrySave(LocalPreferences candidate, out Exception? failure)
    {
        try
        {
            candidate = candidate.Normalize();
            save(candidate);
            Value = candidate;
            failure = null;
            return true;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            failure = exception;
            return false;
        }
    }
}
