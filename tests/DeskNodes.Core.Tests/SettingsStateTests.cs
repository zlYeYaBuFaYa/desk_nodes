using DeskNodes.Core.Domain;
using DeskNodes.Core.Presentation;

namespace DeskNodes.Core.Tests;

public sealed class SettingsStateTests
{
    [Theory]
    [InlineData("00:00", true, 0)]
    [InlineData("23:59", true, 1439)]
    [InlineData("24:00", false, 0)]
    [InlineData("4:00", false, 0)]
    [InlineData("12:60", false, 0)]
    [InlineData("", false, 0)]
    [InlineData("0", false, 0)]
    [InlineData("08", false, 0)]
    [InlineData("08:30", true, 510)]
    [InlineData(" 08:30", false, 0)]
    [InlineData("08:30:00", false, 0)]
    public void TimeInputRequiresExactValidTime(string text, bool valid, int minutes)
    {
        Assert.Equal(valid, SettingsState.TryParseTime(text, out int actual));
        Assert.Equal(minutes, actual);
    }
    [Fact]
    public void SizeOptionsCoverSupportedValuesAndPreserveAutomaticHeight()
    {
        Assert.Equal(new[] { 240, 288, 340, 400 }, SettingsOptions.Widths.Select(o => o.Value));
        Assert.Equal(new[] { 0, 200, 240, 300, 400 }, SettingsOptions.Heights.Select(o => o.Value));
        Assert.Equal("随内容", SettingsOptions.Heights.Single(o => o.Value == 0).Label);
        foreach (var option in SettingsOptions.Widths)
            Assert.Equal(option.Value, new LocalPreferences { NewWidth = option.Value }.Normalize().NewWidth);
        foreach (var option in SettingsOptions.Heights)
            Assert.Equal(option.Value, new LocalPreferences { NewHeight = option.Value }.Normalize().NewHeight);
    }
    [Fact]
    public void ChoiceTablesCoverAllSupportedModesWithReadableLabels()
    {
        AssertOptions(SettingsOptions.Appearances);
        AssertOptions(SettingsOptions.TextSizes);
        AssertOptions(SettingsOptions.Fonts);
        AssertOptions(SettingsOptions.Orientations);
        AssertOptions(SettingsOptions.ShrinkDelays);
        Assert.Equal(new[] { AutoShrink.Off, AutoShrink.Seconds10, AutoShrink.Seconds15, AutoShrink.Seconds30 },
            SettingsOptions.ShrinkDelays.Select(o => o.Value));
        Assert.Equal("关闭", SettingsOptions.ShrinkDelays[0].Label);
    }
    private static void AssertOptions<T>(IReadOnlyList<SettingsOption<T>> options) where T : struct, Enum
    {
        Assert.Equal(Enum.GetValues<T>(), options.Select(o => o.Value));
        Assert.All(options, o => Assert.False(string.IsNullOrWhiteSpace(o.Label)));
        Assert.Equal(options.Count, options.Select(o => o.Label).Distinct().Count());
    }
    [Fact]
    public void GroupsAndResetStateReflectCurrentPreferences()
    {
        Assert.Equal(new[] { "通用", "便签", "工具条" }, SettingsState.Groups);
        Assert.False(new SettingsState(new()).CanResetHome);
        Assert.True(new SettingsState(new() { Home = new(ScreenEdge.Left, .5) }).CanResetHome);
    }
    [Theory]
    [InlineData(ScreenEdge.Left, 0, 12, 84)]
    [InlineData(ScreenEdge.Right, 1, 168, 12)]
    [InlineData(ScreenEdge.Top, 0, 12, 12)]
    [InlineData(ScreenEdge.Bottom, 1, 168, 84)]
    public void HomePreviewPreservesEdgeAndRatioDirection(ScreenEdge edge, double ratio, double x, double y)
        => Assert.Equal(new PointD(x, y), SettingsState.HomePreview(new(edge, ratio), 180, 96));
    [Theory]
    [InlineData(Appearance.System, false, false)]
    [InlineData(Appearance.System, true, true)]
    [InlineData(Appearance.Light, true, false)]
    [InlineData(Appearance.Dark, false, true)]
    [InlineData((Appearance)99, true, true)]
    public void AppearanceResolvesSystemAndUnknownValues(Appearance appearance, bool systemDark, bool expected)
        => Assert.Equal(expected, ThemeRules.Resolve(appearance, systemDark, false, false, false).EffectiveDark);
    [Fact]
    public void UnavailableFontsNeverClaimSuccessfulSelection()
    {
        foreach (var font in new[] { NoteFont.Rounded, NoteFont.Song, NoteFont.Wenkai })
            Assert.False(NoteFontRules.Resolve(font, _ => false).Available);
        Assert.True(NoteFontRules.Resolve(NoteFont.Rounded, family => family == "YouYuan").Available);
        Assert.True(NoteFontRules.Resolve(NoteFont.Wenkai, family => family == "LXGW WenKai").Available);
        Assert.Equal(Appearance.System, new LocalPreferences { Appearance = (Appearance)99 }.Normalize().Appearance);
    }
}
