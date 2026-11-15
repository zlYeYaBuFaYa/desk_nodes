using System.Text.Json.Serialization;

namespace DeskNodes.Core.Backup;

// Windows protocol DTOs are independent of domain objects and SQLite storage types.
public sealed record WindowsBackup
{
    public required string Format { get; init; } = "desknodes.windows.backup";
    public required int Version { get; init; } = 1;
    public required int Schema { get; init; } = 1;
    [JsonPropertyName("exportedAt")]
    public required string ExportedAt { get; init; }
    public required List<NotesRow> Notes { get; init; }
    public required List<ItemsRow> Items { get; init; }
    public required List<SnapshotNotesRow> SnapshotNotes { get; init; }
    public required List<SnapshotItemsRow> SnapshotItems { get; init; }
    public required List<SnapshotsRow> Snapshots { get; init; }
    public required List<PendingDeletedNotesRow> PendingDeletedNotes { get; init; }
    public required List<PendingDeletedItemsRow> PendingDeletedItems { get; init; }
    public required List<NoteDeletionItemsRow> NoteDeletionItems { get; init; }
    public required List<BusinessSettingsRow> BusinessSettings { get; init; }
    public required List<BusinessPreferencesRow> BusinessPreferences { get; init; }
    public required List<CheckpointRow> Checkpoint { get; init; }
}

public sealed record NotesRow
{
    public required string Id { get; init; }
    public required string Title { get; init; }
    public required string Color { get; init; }
    public required long SortOrder { get; init; }
    public required double X { get; init; }
    public required double Y { get; init; }
    public required double Width { get; init; }
    public required double Height { get; init; }
    public required string DisplayDeviceHint { get; init; }
    public required string? DockEdge { get; init; }
    public required long? DockOrder { get; init; }
    public required string SavedLevel { get; init; }
    public required double? FreeX { get; init; }
    public required double? FreeY { get; init; }
    public required double? FreeWidth { get; init; }
    public required double? FreeHeight { get; init; }
    public required bool AutomaticHeight { get; init; }
    public required bool Collapsed { get; init; }
    public required string CreatedAt { get; init; }
    public required string UpdatedAt { get; init; }
    public required string? DeletedAt { get; init; }
}

public sealed record ItemsRow
{
    public required string Id { get; init; }
    public required string NoteId { get; init; }
    public required string Text { get; init; }
    public required bool Completed { get; init; }
    public required bool Struck { get; init; }
    public required long SortOrder { get; init; }
    public required string? ArchivedDay { get; init; }
    public required string CreatedAt { get; init; }
    public required string UpdatedAt { get; init; }
    public required string? DeletedAt { get; init; }
}

public sealed record SnapshotNotesRow
{
    public required string Day { get; init; }
    public required string NoteId { get; init; }
    public required string Title { get; init; }
    public required string Color { get; init; }
    public required long SortOrder { get; init; }
    public required double X { get; init; }
    public required double Y { get; init; }
    public required double Width { get; init; }
    public required double Height { get; init; }
    public required string DisplayDeviceHint { get; init; }
    public required string? DockEdge { get; init; }
    public required long? DockOrder { get; init; }
    public required string SavedLevel { get; init; }
    public required double? FreeX { get; init; }
    public required double? FreeY { get; init; }
    public required double? FreeWidth { get; init; }
    public required double? FreeHeight { get; init; }
    public required bool AutomaticHeight { get; init; }
    public required bool Collapsed { get; init; }
    public required string CreatedAt { get; init; }
    public required string UpdatedAt { get; init; }
    public required string? DeletedAt { get; init; }
    public required bool Deleted { get; init; }
}

public sealed record SnapshotItemsRow
{
    public required string Day { get; init; }
    public required string ItemId { get; init; }
    public required string NoteId { get; init; }
    public required string Text { get; init; }
    public required bool Completed { get; init; }
    public required bool Struck { get; init; }
    public required long SortOrder { get; init; }
    public required string? ArchivedDay { get; init; }
    public required string CreatedAt { get; init; }
    public required string UpdatedAt { get; init; }
    public required string? DeletedAt { get; init; }
    public required bool Deleted { get; init; }
    public required string? CarriedTo { get; init; }
}

public sealed record SnapshotsRow
{
    public required string Day { get; init; }
    public required string SealedAt { get; init; }
}

public sealed record PendingDeletedNotesRow
{
    public required string NoteId { get; init; }
    public required string DeletedAt { get; init; }
    public required string Day { get; init; }
}

public sealed record PendingDeletedItemsRow
{
    public required string ItemId { get; init; }
    public required string DeletedAt { get; init; }
    public required string Day { get; init; }
}

public sealed record NoteDeletionItemsRow
{
    public required string NoteId { get; init; }
    public required string ItemId { get; init; }
}

public sealed record BusinessSettingsRow
{
    public required long RolloverMinutes { get; init; }
}

public sealed record BusinessPreferencesRow
{
    public required string HotkeyNew { get; init; }
    public required string? HotkeyFloat { get; init; }
    public required bool LoginPromptAnswered { get; init; }
    public required bool LoginIntent { get; init; }
}

public sealed record CheckpointRow
{
    public required string ActiveDay { get; init; }
    public required string HighWater { get; init; }
}
