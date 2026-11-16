using DeskNodes.Core.Domain;
using DeskNodes.Core.Storage;

namespace DeskNodes.Core.Services;

public sealed record CreatedNote(Note Note, ItemId FirstItemId);
public sealed record Progress(int Completed, int Total)
{
    public double? Rate => Total == 0 ? null : (double)Completed / Total;
}

public sealed class NoteActions(DeskNodesDatabase database, IClock clock)
{
    private readonly NoteRepository repository = new(database);

    public CreatedNote CreateNote(Placement placement, bool automaticHeight, NoteLevel level = NoteLevel.Back)
        => database.Transaction(_ =>
        {
            var notes = repository.GetNotes(true);
            var colors = Enum.GetValues<NoteColor>();
            var counts = colors.ToDictionary(c => c, c => notes.Count(n => n.DeletedAt is null && n.Color == c));
            var last = notes.OrderBy(n => n.CreatedAt).ThenBy(n => n.SortOrder).LastOrDefault();
            int start = last is null ? 0 : ((int)last.Color + 1) % colors.Length;
            var color = Enumerable.Range(0, colors.Length).Select(i => colors[(start + i) % colors.Length])
                .First(c => counts[c] == counts.Values.Min());
            var now = clock.UtcNow;
            var note = new Note(NoteId.New(), "今日待办", color, repository.NextNoteOrder(),
                placement, level, null, automaticHeight, false, now, now);
            repository.Insert(note);
            var item = NewItem(note.Id, "", 0);
            repository.Insert(item);
            return new CreatedNote(note, item.Id);
        });

    public void EditTitle(NoteId id, string title) => database.Transaction(connection =>
    {
        ArgumentNullException.ThrowIfNull(title);
        if (ServiceSql.Run(connection, "UPDATE notes SET title=$text,updated_at=$now WHERE id=$id AND deleted_at IS NULL;",
            ("$text", title), ("$now", clock.UtcNow.ToUnixTimeMilliseconds()), ("$id", id.ToString())) != 1)
            throw new KeyNotFoundException();
    });

    public string CollapsedSummary(NoteId id)
    {
        var note = repository.GetNote(id) ?? throw new KeyNotFoundException();
        return !string.IsNullOrWhiteSpace(note.Title) ? note.Title : repository.GetItems(id).FirstOrDefault()?.Text ?? "";
    }

    public Progress GetProgress(NoteId id)
    {
        var items = repository.GetItems(id).Where(i => !i.Struck).ToArray();
        return new(items.Count(i => i.Completed), items.Length);
    }

    public ItemId InsertAfter(NoteId noteId, ItemId after, string text = "") => InsertFollowing(noteId, after, [text])[0];

    public IReadOnlyList<ItemId> InsertFollowing(NoteId noteId, ItemId after, IEnumerable<string> lines)
        => database.Transaction(_ =>
        {
            var items = repository.GetItems(noteId).ToList();
            int index = items.FindIndex(i => i.Id == after);
            if (index < 0) throw new KeyNotFoundException();
            var added = lines.Select(text => NewItem(noteId, text, 0)).ToArray();
            items.InsertRange(index + 1, added);
            foreach (var item in added) repository.Insert(item);
            Reorder(items);
            return (IReadOnlyList<ItemId>)added.Select(i => i.Id).ToArray();
        });

    public void EditText(ItemId id, string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        ChangeItem(id, item => Copy(item, text: text));
    }
    public void ToggleCompleted(ItemId id) => ChangeItem(id, item => Copy(item, completed: !item.Completed, struck: false));
    public void ToggleStruck(ItemId id) => ChangeItem(id, item => Copy(item, completed: false, struck: !item.Struck));

    public void MoveItem(NoteId noteId, ItemId id, int targetIndex) => database.Transaction(_ =>
    {
        var items = repository.GetItems(noteId).ToList();
        if (targetIndex < 0 || targetIndex >= items.Count) throw new ArgumentOutOfRangeException(nameof(targetIndex));
        var item = items.FirstOrDefault(i => i.Id == id) ?? throw new KeyNotFoundException();
        items.Remove(item);
        items.Insert(targetIndex, item);
        Reorder(items);
    });

    public int CleanupBlankItems(NoteId noteId) => database.Transaction(connection =>
    {
        if (repository.GetNote(noteId) is null) throw new KeyNotFoundException();
        var items = repository.GetItems(noteId);
        var blanks = items.Where(i => string.IsNullOrWhiteSpace(i.Text)).ToList();
        if (items.Count == blanks.Count && blanks.Count > 0) blanks.RemoveAt(0);
        foreach (var item in blanks)
        {
            // Frozen snapshots have no FK to live items. Remove pending membership before the live row.
            ServiceSql.Run(connection, "DELETE FROM pending_deleted_items WHERE item_id=$id; DELETE FROM items WHERE id=$id;",
                ("$id", item.Id.ToString()));
        }
        if (items.Count == 0) repository.Insert(NewItem(noteId, "", 0));
        return blanks.Count;
    });

    private void ChangeItem(ItemId id, Func<NoteItem, NoteItem> change) => database.Transaction(_ =>
    {
        var item = repository.GetItem(id) ?? throw new KeyNotFoundException();
        repository.Update(change(item));
    });
    private NoteItem NewItem(NoteId note, string text, long order) => new(ItemId.New(), note, text, false, false, order, null, clock.UtcNow, clock.UtcNow);
    private NoteItem Copy(NoteItem i, string? text = null, bool? completed = null, bool? struck = null, long? order = null)
        => new(i.Id, i.NoteId, text ?? i.Text, completed ?? i.Completed, struck ?? i.Struck, order ?? i.SortOrder,
            i.ArchivedDay, i.CreatedAt, clock.UtcNow, i.DeletedAt);
    private void Reorder(List<NoteItem> items)
    {
        for (int index = 0; index < items.Count; index++) repository.Update(Copy(items[index], order: index));
    }
}
