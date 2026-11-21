namespace DeskNodes.Core.Presentation;

public readonly record struct ThemeState(bool EffectiveDark, bool TransparencyEnabled, bool HighContrast, bool SolidFallback);

public static class ThemeRules
{
    public static ThemeState Resolve(Appearance appearance, bool systemDark, bool transparencyEnabled, bool highContrast, bool remoteSession) =>
        new(appearance == Appearance.Dark || (!Enum.IsDefined(appearance) || appearance == Appearance.System) && systemDark,
            transparencyEnabled, highContrast, highContrast || !transparencyEnabled || remoteSession);
}
