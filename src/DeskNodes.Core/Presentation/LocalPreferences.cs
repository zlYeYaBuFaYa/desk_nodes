using System.Collections.Immutable;
using System.Text.Json;
using System.Text.Json.Serialization;
using DeskNodes.Core.Domain;
using DeskNodes.Core.Services;
using DeskNodes.Core.Storage;

namespace DeskNodes.Core.Presentation;

public enum Appearance { System, Light, Dark }
public enum NoteTextSize { Small, Standard, Large, ExtraLarge }
public enum NoteFont { Default, Rounded, Song, Wenkai }
public enum AutoShrink { Off = 0, Seconds10 = 10, Seconds15 = 15, Seconds30 = 30 }
// Free centers use physical virtual-desktop pixels, so mixed-DPI screen selection is unambiguous.
// Edge anchors carry a device hint; old preferences without one retain the primary-screen fallback.
public sealed record ToolbarAnchor(PointD? Center = null, ScreenEdge? Edge = null, double Ratio = .5,
    string? DeviceHint = null)
{
    public bool IsValid => double.IsFinite(Ratio) && Ratio is >= 0 and <= 1 &&
        ((Center is { } c && double.IsFinite(c.X) && double.IsFinite(c.Y) && Edge is null) ||
         (Center is null && Edge is { } edge && Enum.IsDefined(edge)));
}
public sealed record LocalPreferences
{
    [JsonPropertyName("desk.collapsed")] public bool DeskCollapsed { get; init; }
    [JsonPropertyName("toolbar.anchor")] public ToolbarAnchor? Anchor { get; init; }
    [JsonPropertyName("toolbar.orientation")] public ToolbarOrientation Orientation { get; init; } = ToolbarOrientation.Vertical;
    [JsonPropertyName("toolbar.autoShrink")] public AutoShrink AutoShrink { get; init; } = AutoShrink.Seconds15;
    [JsonPropertyName("toolbar.home")] public HomePosition Home { get; init; } = new();
    [JsonPropertyName("app.appearance")] public Appearance Appearance { get; init; }
    [JsonPropertyName("note.newWidth")] public int NewWidth { get; init; } = 288;
    [JsonPropertyName("note.newHeight")] public int NewHeight { get; init; } = 240;
    [JsonPropertyName("note.textSize")] public NoteTextSize TextSize { get; init; } = NoteTextSize.Standard;
    [JsonPropertyName("note.font")] public NoteFont Font { get; init; }
    [JsonPropertyName("arrange.pages")] public ImmutableDictionary<string, int> Pages { get; init; } = ImmutableDictionary<string, int>.Empty;
    [JsonPropertyName("arrange.page")] public int Page { get; init; }
    [JsonPropertyName("keepToolbarExpanded")] public bool KeepToolbarExpanded { get; init; }
    [JsonPropertyName("reduceMotion")] public bool ReduceMotion { get; init; }

    public LocalPreferences Normalize() => this with
    {
        Anchor = Anchor is { IsValid: true } ? Anchor : null,
        Home = Home is { IsValid: true } ? Home : new(),
        Orientation = Enum.IsDefined(Orientation) ? Orientation : ToolbarOrientation.Vertical,
        AutoShrink = Enum.IsDefined(AutoShrink) ? AutoShrink : AutoShrink.Seconds15,
        Appearance = Enum.IsDefined(Appearance) ? Appearance : Appearance.System,
        TextSize = Enum.IsDefined(TextSize) ? TextSize : NoteTextSize.Standard,
        Font = Enum.IsDefined(Font) ? Font : NoteFont.Default,
        NewWidth = NewWidth is 240 or 288 or 340 or 400 ? NewWidth : 288,
        NewHeight = NewHeight is 0 or 200 or 240 or 300 or 400 ? NewHeight : 240,
        Pages = (Pages ?? ImmutableDictionary<string, int>.Empty)
            .Where(p => p.Value >= 0).ToImmutableDictionary(),
        Page = Math.Max(0, Page)
    };
}
public sealed class LocalPreferencesStore
{
    private readonly string path;
    private readonly IDeskNodesLog log;
    public LocalPreferencesStore(IDeskNodesLog log, string? dataDirectory = null)
    {
        this.log = log;
        path = Path.Combine(dataDirectory ?? DataDirectory.Resolve(), "LocalPreferences.json");
    }
    public LocalPreferences Load()
    {
        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(path));
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object) throw new JsonException("偏好必须是对象。");
            return new LocalPreferences
            {
                DeskCollapsed = ReadBool(root, "desk.collapsed"),
                Anchor = ReadAnchor(root),
                Orientation = ReadEnum(root, "toolbar.orientation", Orientations, ToolbarOrientation.Vertical),
                AutoShrink = ReadShrink(root),
                Home = ReadHome(root),
                Appearance = ReadEnum(root, "app.appearance", Appearances, Appearance.System),
                NewWidth = ReadInt(root, "note.newWidth", 288),
                NewHeight = ReadInt(root, "note.newHeight", 240),
                TextSize = ReadEnum(root, "note.textSize", TextSizes, NoteTextSize.Standard),
                Font = ReadEnum(root, "note.font", Fonts, NoteFont.Default),
                Pages = ReadPages(root),
                Page = ReadInt(root, "arrange.page", 0),
                KeepToolbarExpanded = ReadBool(root, "keepToolbarExpanded"),
                ReduceMotion = ReadBool(root, "reduceMotion")
            }.Normalize();
        }
        catch (FileNotFoundException) { return new(); }
        catch (DirectoryNotFoundException) { return new(); }
        catch (JsonException ex)
        {
            string preserved = path + ".corrupt-" + DateTimeOffset.UtcNow.ToString("yyyyMMddHHmmssfffffff", System.Globalization.CultureInfo.InvariantCulture) + "-" + Guid.NewGuid().ToString("N");
            try
            {
                File.Move(path, preserved);
                log.Error($"本机偏好损坏，已保留到 {preserved}，恢复默认。", ex);
            }
            catch (Exception moveError) when (moveError is IOException or UnauthorizedAccessException)
            {
                log.Error("本机偏好损坏且无法重命名，保留原文件并恢复默认。", moveError);
            }
            return new();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            log.Error("无法读取本机偏好，恢复默认。", ex);
            return new();
        }
    }

    private static readonly (string Id, ToolbarOrientation Value)[] Orientations = [("vertical", ToolbarOrientation.Vertical), ("horizontal", ToolbarOrientation.Horizontal)];
    private static readonly (string Id, Appearance Value)[] Appearances = [("system", Appearance.System), ("light", Appearance.Light), ("dark", Appearance.Dark)];
    private static readonly (string Id, NoteTextSize Value)[] TextSizes = [("small", NoteTextSize.Small), ("standard", NoteTextSize.Standard), ("large", NoteTextSize.Large), ("extraLarge", NoteTextSize.ExtraLarge)];
    private static readonly (string Id, NoteFont Value)[] Fonts = [("default", NoteFont.Default), ("rounded", NoteFont.Rounded), ("song", NoteFont.Song), ("wenkai", NoteFont.Wenkai)];
    private static readonly (string Id, ScreenEdge Value)[] Edges = [("left", ScreenEdge.Left), ("right", ScreenEdge.Right), ("top", ScreenEdge.Top), ("bottom", ScreenEdge.Bottom)];

    private static bool TryReadEnum<T>(JsonElement root, string key, (string Id, T Value)[] values, out T value)
    {
        if (root.TryGetProperty(key, out var element) && element.ValueKind == JsonValueKind.String)
            foreach (var entry in values)
                if (element.GetString() == entry.Id) { value = entry.Value; return true; }
        value = default!;
        return false;
    }
    private static T ReadEnum<T>(JsonElement root, string key, (string Id, T Value)[] values, T fallback) =>
        TryReadEnum(root, key, values, out var value) ? value : fallback;
    private static string Identifier<T>(T value, (string Id, T Value)[] values) =>
        values.Single(entry => EqualityComparer<T>.Default.Equals(entry.Value, value)).Id;
    private static bool ReadBool(JsonElement root, string key) =>
        root.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.True;
    private static int ReadInt(JsonElement root, string key, int fallback) =>
        root.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out int number) ? number : fallback;
    private static bool TryReadDouble(JsonElement root, string key, out double number)
    {
        number = 0;
        return root.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.Number && value.TryGetDouble(out number) && double.IsFinite(number);
    }
    private static AutoShrink ReadShrink(JsonElement root) => ReadInt(root, "toolbar.autoShrink", 15) switch
    {
        0 => AutoShrink.Off, 10 => AutoShrink.Seconds10, 30 => AutoShrink.Seconds30, _ => AutoShrink.Seconds15
    };
    private static HomePosition ReadHome(JsonElement root) =>
        root.TryGetProperty("toolbar.home", out var value) && value.ValueKind == JsonValueKind.Object &&
        TryReadEnum(value, "edge", Edges, out var edge) && TryReadDouble(value, "ratio", out var ratio) && ratio is >= 0 and <= 1
            ? new(edge, ratio) : new();
    private static ToolbarAnchor? ReadAnchor(JsonElement root)
    {
        if (!root.TryGetProperty("toolbar.anchor", out var value) || value.ValueKind != JsonValueKind.Object) return null;
        double ratio = .5;
        if (value.TryGetProperty("ratio", out _) && !TryReadDouble(value, "ratio", out ratio)) return null;
        PointD? center = null;
        if (value.TryGetProperty("center", out var point) && point.ValueKind != JsonValueKind.Null)
        {
            if (point.ValueKind != JsonValueKind.Object || !TryReadDouble(point, "x", out var x) || !TryReadDouble(point, "y", out var y)) return null;
            center = new(x, y);
        }
        ScreenEdge? edge = null;
        if (value.TryGetProperty("edge", out var edgeValue) && edgeValue.ValueKind != JsonValueKind.Null)
        {
            if (!TryReadEnum(value, "edge", Edges, out var parsed)) return null;
            edge = parsed;
        }
        string? hint = value.TryGetProperty("deviceHint", out var device) && device.ValueKind == JsonValueKind.String
            ? device.GetString() : null;
        var anchor = new ToolbarAnchor(center, edge, ratio, hint);
        return anchor.IsValid ? anchor : null;
    }
    private static ImmutableDictionary<string, int> ReadPages(JsonElement root)
    {
        var pages = ImmutableDictionary.CreateBuilder<string, int>();
        if (root.TryGetProperty("arrange.pages", out var value) && value.ValueKind == JsonValueKind.Object)
            foreach (var entry in value.EnumerateObject())
                if (entry.Value.ValueKind == JsonValueKind.Number && entry.Value.TryGetInt32(out int page) && page >= 0) pages[entry.Name] = page;
        return pages.ToImmutable();
    }

    private static void Write(Utf8JsonWriter writer, LocalPreferences p)
    {
        writer.WriteStartObject();
        writer.WriteBoolean("desk.collapsed", p.DeskCollapsed);
        writer.WritePropertyName("toolbar.anchor");
        if (p.Anchor is not { } anchor) writer.WriteNullValue();
        else
        {
            writer.WriteStartObject();
            if (anchor.Center is { } center)
            {
                writer.WriteStartObject("center"); writer.WriteNumber("x", center.X); writer.WriteNumber("y", center.Y); writer.WriteEndObject();
            }
            if (anchor.Edge is { } edge) writer.WriteString("edge", Identifier(edge, Edges));
            if (anchor.DeviceHint is not null) writer.WriteString("deviceHint", anchor.DeviceHint);
            writer.WriteNumber("ratio", anchor.Ratio);
            writer.WriteEndObject();
        }
        writer.WriteString("toolbar.orientation", Identifier(p.Orientation, Orientations));
        writer.WriteNumber("toolbar.autoShrink", (int)p.AutoShrink);
        writer.WriteStartObject("toolbar.home");
        writer.WriteString("edge", Identifier(p.Home.Edge, Edges)); writer.WriteNumber("ratio", p.Home.Ratio); writer.WriteEndObject();
        writer.WriteString("app.appearance", Identifier(p.Appearance, Appearances));
        writer.WriteNumber("note.newWidth", p.NewWidth); writer.WriteNumber("note.newHeight", p.NewHeight);
        writer.WriteString("note.textSize", Identifier(p.TextSize, TextSizes)); writer.WriteString("note.font", Identifier(p.Font, Fonts));
        writer.WriteStartObject("arrange.pages");
        foreach (var page in p.Pages) writer.WriteNumber(page.Key, page.Value);
        writer.WriteEndObject();
        writer.WriteNumber("arrange.page", p.Page);
        writer.WriteBoolean("keepToolbarExpanded", p.KeepToolbarExpanded); writer.WriteBoolean("reduceMotion", p.ReduceMotion);
        writer.WriteEndObject();
    }
    public void Save(LocalPreferences preferences)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        string temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                using (var writer = new Utf8JsonWriter(stream, new() { Indented = true })) Write(writer, preferences.Normalize());
                stream.Flush(true);
            }
            File.Move(temporary, path, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
