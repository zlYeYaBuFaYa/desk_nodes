using DeskNodes.Core.Storage;

namespace DeskNodes.Core.Services;

/// <summary>Serialized editor ownership and debounce policy. Scheduling runs on the caller's context.</summary>
public sealed class EditorSession(IDeskNodesLog log, DeskNodesDatabase database) : ICommitBarrier
{
    public static readonly TimeSpan CommitDelay = TimeSpan.FromMilliseconds(400);
    public sealed class Owner
    {
        internal Action<string> Save { get; init; } = null!;
        internal Action<TimeSpan, Action> Schedule { get; init; } = null!;
        internal long Revision;
        internal long Generation;
        public required string Id { get; init; }
        public string Text { get; internal set; } = "";
        public string Committed { get; internal set; } = "";
        public bool Composing { get; internal set; }
        public bool Valid { get; internal set; } = true;
        public bool Dirty => Text != Committed;
    }
    private readonly HashSet<Owner> owners = [];
    public event EventHandler? SaveFailed;
    public bool HasComposition => owners.Any(o => o.Composing);
    public CommitResult Status { get; private set; } = CommitResult.Committed;
    public Owner Register(string id, string text, Action<string> save, Action<TimeSpan, Action> schedule)
    {
        var owner = new Owner { Id = id, Text = text, Committed = text, Save = save, Schedule = schedule };
        owners.Add(owner);
        return owner;
    }
    public void Change(Owner owner, string text)
    {
        if (!owner.Valid)
            return;
        owner.Text = text;
        owner.Revision++;
        Arrange(owner);
    }
    public void SetComposition(Owner owner, bool composing)
    {
        if (!owner.Valid)
            return;
        owner.Composing = composing;
        owner.Generation++;
    }
    public void Reschedule(Owner owner) => Arrange(owner);
    private void Arrange(Owner owner)
    {
        long generation = ++owner.Generation;
        if (!owner.Valid || owner.Composing)
            return;
        owner.Schedule(CommitDelay, () =>
        {
            if (owner.Valid && generation == owner.Generation)
                Commit(owner);
        });
    }
    public bool Refresh(Owner owner, string text, bool active)
    {
        if (!owner.Valid || active || owner.Composing || owner.Dirty)
            return false;
        owner.Text = text;
        owner.Committed = text;
        return true;
    }
    public bool Commit(Owner owner)
    {
        if (!owner.Valid)
            return true;
        if (owner.Composing)
        {
            Status = CommitResult.Composing;
            return false;
        }
        if (!owner.Dirty)
            return true;
        long revision = owner.Revision;
        string text = owner.Text;
        try
        {
            new PendingCommitTracker(database).Save(() => owner.Save(text), () =>
            {
                if (owner.Valid && revision == owner.Revision)
                    owner.Committed = text;
            }, () =>
            {
                if (!owner.Valid)
                    return;
                Status = CommitResult.Failed;
                Arrange(owner);
            });
            Status = CommitResult.Committed;
            return true;
        }
        catch (Exception exception)
        {
            Status = CommitResult.Failed;
            Arrange(owner);
            SaveFailed?.Invoke(this, EventArgs.Empty);
            log.Error($"保存编辑失败：{owner.Id}，保留缓冲。", exception);
            return false;
        }
    }
    public CommitResult TryCommitPending()
    {
        if (HasComposition)
            return Status = CommitResult.Composing;
        bool success = true;
        foreach (var owner in owners)
        {
            owner.Generation++;
            success &= Commit(owner);
        }
        return Status = success ? CommitResult.Committed : CommitResult.Failed;
    }
    public void Remove(Owner owner)
    {
        owner.Valid = false;
        owner.Generation++;
        owners.Remove(owner);
    }
    public void InvalidateAll()
    {
        foreach (var owner in owners.ToArray())
            Remove(owner);
        Status = CommitResult.Committed;
    }
}
