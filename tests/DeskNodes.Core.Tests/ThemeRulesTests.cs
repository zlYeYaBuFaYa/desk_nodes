using DeskNodes.Core.Presentation;

namespace DeskNodes.Core.Tests;

public sealed class ThemeRulesTests
{
    [Theory]
    [InlineData(Appearance.System, false, false)]
    [InlineData(Appearance.System, true, true)]
    [InlineData(Appearance.Light, false, false)]
    [InlineData(Appearance.Light, true, false)]
    [InlineData(Appearance.Dark, false, true)]
    [InlineData(Appearance.Dark, true, true)]
    public void ExplicitAppearanceOverridesSystem(Appearance appearance, bool systemDark, bool expected)
    {
        var theme = ThemeRules.Resolve(appearance, systemDark, true, false, false);
        Assert.Equal(expected, theme.EffectiveDark);
        Assert.False(theme.SolidFallback);
    }

    [Theory]
    [InlineData(true, false, false, false)]
    [InlineData(false, false, false, true)]
    [InlineData(true, true, false, true)]
    [InlineData(true, false, true, true)]
    [InlineData(false, true, true, true)]
    public void AccessibilityAndSessionDetermineMaterialFallback(bool transparency, bool contrast, bool remote, bool fallback)
    {
        var theme = ThemeRules.Resolve(Appearance.Dark, false, transparency, contrast, remote);
        Assert.True(theme.EffectiveDark);
        Assert.Equal(transparency, theme.TransparencyEnabled);
        Assert.Equal(contrast, theme.HighContrast);
        Assert.Equal(fallback, theme.SolidFallback);
    }
}
