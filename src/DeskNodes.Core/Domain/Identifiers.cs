namespace DeskNodes.Core.Domain;

public readonly record struct NoteId(Guid Value)
{
    public static NoteId New() => new(Guid.NewGuid());
    public static NoteId Parse(string value) => new(Guid.Parse(value));
    public override string ToString() => Value.ToString("D");
}

public readonly record struct ItemId(Guid Value)
{
    public static ItemId New() => new(Guid.NewGuid());
    public static ItemId Parse(string value) => new(Guid.Parse(value));
    public override string ToString() => Value.ToString("D");
}
