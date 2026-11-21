using DeskNodes.Core.Domain;
using DeskNodes.Core.Storage;

namespace DeskNodes.Core.Services;

public enum UndoDecision { StructuralUndo, TextUndo }
public sealed record DeletionMember(NoteId? NoteId, ItemId? ItemId);
public sealed record DeletionHint(DateTimeOffset DeletedAt, TimeSpan Remaining, int MemberCount);

/// <summary>Session-local structural undo. Use one instance per database session; Clear after successful import.</summary>
public sealed class DeletionUndoQueue(DeskNodesDatabase database, IClock clock)
{
    private sealed record Member(DeletionMember Key, Note? Note, IReadOnlyList<NoteItem> Items);
    private sealed record Entry(DateTimeOffset At, List<Member> Members)
    {
        public List<ItemId> BlankPlaceholders { get; } = [];
    }
    private readonly List<Entry> entries = [];
    private readonly NoteRepository repository = new(database);

    public bool DeleteNote(NoteId id) => DeleteNotes([id]);
    public bool DeleteNotes(IEnumerable<NoteId> ids)
    {
        var at = clock.UtcNow;
        Prune(at);
        var members = database.Transaction(_ =>
        {
            var result = new List<Member>();
            var day = new BusinessDayContext(database, clock).GetDay(at);
            foreach (var id in ids.Distinct())
            {
                var note = repository.GetNote(id);
                if (note is null) continue;
                var items = repository.GetItems(id);
                if (repository.SoftDelete(id, at, day)) result.Add(new(new(id, null), note, items));
            }
            return result;
        });
        if (members.Count == 0) return false;
        entries.Add(new(at, members));
        return true;
    }

    public bool DeleteItem(ItemId id)
    {
        var at = clock.UtcNow;
        Prune(at);
        var member = database.Transaction(_ =>
        {
            var item = repository.GetItem(id);
            if (item is null) return null;
            repository.SoftDelete(id, at, new BusinessDayContext(database, clock).GetDay(at));
            return new Member(new(null, id), null, [item]);
        });
        if (member is null) return false;
        entries.Add(new(at, [member]));
        return true;
    }

    /// <summary>The blank row inserted so the note stays editable. Undo removes it when it is still blank.</summary>
    public void AssociateBlankPlaceholder(ItemId deleted, ItemId placeholder)
    {
        var entry = entries.LastOrDefault();
        if (entry is null || placeholder == deleted) return;
        if (!entry.Members.Any(member => member.Items.Any(item => item.Id == deleted))) return;
        entry.BlankPlaceholders.Add(placeholder);
    }

    private static bool Valid(Entry entry, DateTimeOffset now) => now >= entry.At && now - entry.At < TimeSpan.FromSeconds(5);
    private void Prune(DateTimeOffset now) => entries.RemoveAll(e => now >= e.At && now - e.At >= TimeSpan.FromSeconds(5));
    public IReadOnlyList<DeletionHint> Hints(DateTimeOffset now)
    {
        Prune(now);
        return entries.Where(e => Valid(e, now))
            .Select(e => new DeletionHint(e.At, TimeSpan.FromSeconds(5) - (now - e.At), e.Members.Count)).ToArray();
    }
    public int PromptCount(DateTimeOffset now)
    {
        Prune(now);
        return entries.Count(e => Valid(e, now));
    }
    public bool HasUndoableDeletion(DateTimeOffset now)
    {
        Prune(now);
        return entries.Any(e => Valid(e, now));
    }
    public UndoDecision DecideUndo(DateTimeOffset now, bool hasNewTextInputSinceDeletion)
    {
        Prune(now);
        return !hasNewTextInputSinceDeletion && entries.Any(e => Valid(e, now)) ? UndoDecision.StructuralUndo : UndoDecision.TextUndo;
    }

    public bool Undo(DateTimeOffset now)
    {
        Prune(now);
        var entry = entries.LastOrDefault(e => Valid(e, now));
        if (entry is null) return false;
        database.Transaction(connection =>
        {
            foreach (var member in entry.Members)
            {
                if (member.Note is { } note)
                {
                    repository.Update(note);
                    ServiceSql.Run(connection, "DELETE FROM note_deletion_items WHERE note_id=$id; DELETE FROM pending_deleted_notes WHERE note_id=$id;", ("$id", note.Id.ToString()));
                }
                foreach (var item in member.Items)
                {
                    // Do not reactivate items archived by a rollover while the toast was visible.
                    var current = repository.GetItem(item.Id, true, true) ?? throw new KeyNotFoundException();
                    if (current.ArchivedDay is not null) continue;
                    repository.Update(item);
                    ServiceSql.Run(connection, "DELETE FROM pending_deleted_items WHERE item_id=$id;", ("$id", item.Id.ToString()));
                }
            }
            var restored = entry.Members.SelectMany(member => member.Items).Select(item => item.Id).ToHashSet();
            foreach (var placeholder in entry.BlankPlaceholders)
            {
                if (restored.Contains(placeholder)) continue;
                var current = repository.GetItem(placeholder, true, true);
                if (current is null || current.DeletedAt is not null || current.ArchivedDay is not null
                    || !string.IsNullOrWhiteSpace(current.Text))
                    continue;
                ServiceSql.Run(connection,
                    "DELETE FROM pending_deleted_items WHERE item_id=$id; DELETE FROM note_deletion_items WHERE item_id=$id; DELETE FROM items WHERE id=$id;",
                    ("$id", placeholder.ToString()));
            }
        });
        entries.Remove(entry);
        return true;
    }

    public void RemoveMember(DeletionMember member)
    {
        Prune(clock.UtcNow);
        foreach (var entry in entries) entry.Members.RemoveAll(m => m.Key == member);
        entries.RemoveAll(e => e.Members.Count == 0);
    }
    public void Clear() => entries.Clear();
}
