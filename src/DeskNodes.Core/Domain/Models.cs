namespace DeskNodes.Core.Domain;

public sealed record Note
{
    public NoteId Id { get; }
    public string Title { get; }
    public NoteColor Color { get; }
    public long SortOrder { get; }
    public Placement Placement { get; }
    public NoteLevel SavedLevel { get; }
    public RectD? FreeRestore { get; }
    public bool AutomaticHeight { get; }
    public bool Collapsed { get; }
    public DateTimeOffset CreatedAt { get; }
    public DateTimeOffset UpdatedAt { get; }
    public DateTimeOffset? DeletedAt { get; }

    public Note(NoteId id, string title, NoteColor color, long sortOrder, Placement placement,
        NoteLevel savedLevel, RectD? freeRestore, bool automaticHeight, bool collapsed,
        DateTimeOffset createdAt, DateTimeOffset updatedAt, DateTimeOffset? deletedAt = null)
    {
        ArgumentNullException.ThrowIfNull(title);
        ArgumentNullException.ThrowIfNull(placement);
        if (!Enum.IsDefined(color) || !Enum.IsDefined(savedLevel))
            throw new ArgumentOutOfRangeException(nameof(color));
        (Id, Title, Color, SortOrder, Placement, SavedLevel, FreeRestore, AutomaticHeight, Collapsed,
            CreatedAt, UpdatedAt, DeletedAt) = (id, title, color, sortOrder, placement, savedLevel,
            freeRestore, automaticHeight, collapsed, createdAt, updatedAt, deletedAt);
    }
}

public sealed record NoteItem
{
    public ItemId Id { get; }
    public NoteId NoteId { get; }
    public string Text { get; }
    public bool Completed { get; }
    public bool Struck { get; }
    public long SortOrder { get; }
    public HistoryDay? ArchivedDay { get; }
    public DateTimeOffset CreatedAt { get; }
    public DateTimeOffset UpdatedAt { get; }
    public DateTimeOffset? DeletedAt { get; }

    public NoteItem(ItemId id, NoteId noteId, string text, bool completed, bool struck, long sortOrder,
        HistoryDay? archivedDay, DateTimeOffset createdAt, DateTimeOffset updatedAt,
        DateTimeOffset? deletedAt = null)
    {
        ArgumentNullException.ThrowIfNull(text);
        if (completed && struck)
            throw new ArgumentException("事项不能同时完成和划掉。");
        (Id, NoteId, Text, Completed, Struck, SortOrder, ArchivedDay, CreatedAt, UpdatedAt, DeletedAt) =
            (id, noteId, text, completed, struck, sortOrder, archivedDay, createdAt, updatedAt, deletedAt);
    }
}
