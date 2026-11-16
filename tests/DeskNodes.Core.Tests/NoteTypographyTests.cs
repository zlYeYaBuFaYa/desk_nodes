using DeskNodes.Core.Presentation;

namespace DeskNodes.Core.Tests;

public sealed class NoteTypographyTests
{
    [Theory]
    [InlineData(NoteTextSize.Small, 1.5, 22.5, 19.5, 16.5, 45)]
    [InlineData(NoteTextSize.Standard, 2, 32, 28, 24, 64)]
    [InlineData(NoteTextSize.Large, 1.5, 27, 24, 21, 55)]
    [InlineData(NoteTextSize.ExtraLarge, 2, 40, 36, 30, 82)]
    public void SystemTextScaleCombinesWithEachPreferenceAndRemeasuresRhythm(
        NoteTextSize size, double scale, double title, double body, double secondary, double row)
    {
        var typography = NoteTypography.For(size, scale);
        Assert.Equal((title, body, secondary), (typography.Title, typography.Body, typography.Secondary));
        Assert.Equal(row, typography.Scale(32));
        Assert.Equal(Math.Min(480, typography.Scale(94) + row + 18), typography.AutomaticHeight(row, 1000));
        Assert.Equal(184, typography.AutomaticHeight(1000, 200));
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(double.NaN)]
    [InlineData(double.PositiveInfinity)]
    public void InvalidSystemTextScaleFallsBackToOne(double scale)
        => Assert.Equal(NoteTypography.For(NoteTextSize.Standard), NoteTypography.For(NoteTextSize.Standard, scale));

    [Theory]
    [InlineData(NoteTextSize.Small, 15, 13, 11, 30)]
    [InlineData(NoteTextSize.Standard, 16, 14, 12, 32)]
    [InlineData(NoteTextSize.Large, 18, 16, 14, 37)]
    [InlineData(NoteTextSize.ExtraLarge, 20, 18, 15, 41)]
    public void TypographyUsesSpecifiedSizesAndRoundedRhythm(NoteTextSize size, double title, double body, double secondary, double row)
    {
        var typography = NoteTypography.For(size);
        Assert.Equal((title, body, secondary), (typography.Title, typography.Body, typography.Secondary));
        Assert.Equal(row, typography.Scale(32));
    }
    [Theory]
    [InlineData(0, 1000, 120)]
    [InlineData(1000, 1000, 480)]
    [InlineData(1000, 200, 184)]
    [InlineData(1000, 10, 0)]
    public void HeightHonorsMinimumContentCapAndSmallWorkArea(double rows, double work, double expected)
        => Assert.Equal(expected, NoteTypography.For(NoteTextSize.Standard).AutomaticHeight(rows, work));
    [Theory]
    [InlineData(NoteFont.Rounded)] [InlineData(NoteFont.Song)] [InlineData(NoteFont.Wenkai)]
    public void MissingOptionalFontsFallBackWithoutLosingAvailabilityInformation(NoteFont font)
    {
        var result = NoteFontRules.Resolve(font, _ => false);
        Assert.False(result.Available); Assert.Equal(NoteFontRules.DefaultFamily, result.Family);
    }
    [Fact]
    public void SongCanUseNewSongAndDefaultRequiresNoOptionalFont()
    {
        Assert.Equal("Sitka Text, Georgia, NSimSun", NoteFontRules.Resolve(NoteFont.Song, name => name == "NSimSun").Family);
        Assert.True(NoteFontRules.Resolve(NoteFont.Default, _ => false).Available);
    }
    [Theory]
    [InlineData("", false, true)] [InlineData(" ", false, false)] [InlineData("", true, false)]
    public void BackspaceOnlyDeletesExactlyEmptyNonComposingRows(string text, bool composing, bool expected)
        => Assert.Equal(expected, EditorRules.CanDeleteEmptyRow(text, composing));
    [Theory]
    [InlineData(false, 0, 0, 3, true, true)]
    [InlineData(false, 0, 1, 3, true, false)]
    [InlineData(false, 0, 2, 3, false, true)]
    [InlineData(false, 1, 2, 3, false, false)]
    [InlineData(true, 0, 0, 1, true, false)]
    [InlineData(false, 0, -1, 0, true, false)]
    public void ArrowNavigationPreservesSelectionCompositionAndInnerLines(bool composing, int selection, int line, int count, bool up, bool expected)
        => Assert.Equal(expected, EditorRules.CanMoveBetweenItems(composing, selection, line, count, up));
}
