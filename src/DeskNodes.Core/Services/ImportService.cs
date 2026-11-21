using DeskNodes.Core.Storage;

namespace DeskNodes.Core.Services;

public interface IHotkeyCandidate : IDisposable
{
    /// <summary>Transfers the prepared binding after persistence succeeds.</summary>
    void Commit();
}

public interface IHotkeyRegistrationService
{
    IHotkeyCandidate Prepare(HotkeyAction action, string? text);
    void MarkConflict(HotkeyAction action, string text);
}

/// <summary>Publishes a validated staging database before discarding old editing state.</summary>
public sealed class ImportService(DeskNodesDatabase database, IHotkeyRegistrationService hotkeys,
    Action clearUndo, Action invalidateAll)
{
    public void Apply(DeskNodesDatabase staging, Action onReplaced, Action<BusinessPreferences> published,
        Action<Exception> raiseConflict, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var incoming = new BusinessPreferencesStore(staging).Load();
        using var candidate = hotkeys.Prepare(HotkeyAction.NewNote, incoming.HotkeyNew);
        cancellationToken.ThrowIfCancellationRequested();
        database.ReplaceFrom(staging);
        onReplaced();
        candidate.Commit();
        clearUndo();
        invalidateAll();
        published(incoming);
        try
        {
            using var raise = hotkeys.Prepare(HotkeyAction.Raise, incoming.HotkeyFloat);
            raise.Commit();
        }
        catch (Exception exception)
        {
            hotkeys.MarkConflict(HotkeyAction.Raise, incoming.HotkeyFloat!);
            raiseConflict(exception);
        }
    }
}
