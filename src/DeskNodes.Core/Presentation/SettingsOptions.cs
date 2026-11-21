namespace DeskNodes.Core.Presentation;

public sealed record SettingsOption<T>(string Label, T Value);

public static class SettingsOptions
{
    public static IReadOnlyList<SettingsOption<Appearance>> Appearances { get; } = Array.AsReadOnly<SettingsOption<Appearance>>(
    [
        new("跟随系统", Appearance.System),
        new("浅色", Appearance.Light),
        new("深色", Appearance.Dark)
    ]);
    public static IReadOnlyList<SettingsOption<NoteTextSize>> TextSizes { get; } = Array.AsReadOnly<SettingsOption<NoteTextSize>>(
    [
        new("小", NoteTextSize.Small),
        new("标准", NoteTextSize.Standard),
        new("大", NoteTextSize.Large),
        new("特大", NoteTextSize.ExtraLarge)
    ]);
    public static IReadOnlyList<SettingsOption<NoteFont>> Fonts { get; } = Array.AsReadOnly<SettingsOption<NoteFont>>(
    [
        new("默认", NoteFont.Default),
        new("圆体", NoteFont.Rounded),
        new("宋体", NoteFont.Song),
        new("文楷", NoteFont.Wenkai)
    ]);
    public static IReadOnlyList<SettingsOption<ToolbarOrientation>> Orientations { get; } = Array.AsReadOnly<SettingsOption<ToolbarOrientation>>(
    [
        new("竖向", ToolbarOrientation.Vertical),
        new("横向", ToolbarOrientation.Horizontal)
    ]);
    public static IReadOnlyList<SettingsOption<AutoShrink>> ShrinkDelays { get; } = Array.AsReadOnly<SettingsOption<AutoShrink>>(
    [
        new("关闭", AutoShrink.Off),
        new("10 秒", AutoShrink.Seconds10),
        new("15 秒", AutoShrink.Seconds15),
        new("30 秒", AutoShrink.Seconds30)
    ]);
    public static IReadOnlyList<SettingsOption<int>> Widths { get; } = Array.AsReadOnly<SettingsOption<int>>(
    [
        new("240", 240),
        new("288", 288),
        new("340", 340),
        new("400", 400)
    ]);
    public static IReadOnlyList<SettingsOption<int>> Heights { get; } = Array.AsReadOnly<SettingsOption<int>>(
    [
        new("随内容", 0),
        new("200", 200),
        new("240", 240),
        new("300", 300),
        new("400", 400)
    ]);
}
