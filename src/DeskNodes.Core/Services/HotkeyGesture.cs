namespace DeskNodes.Core.Services;

[Flags]
public enum HotkeyModifiers { None = 0, Alt = 1, Ctrl = 2, Shift = 4 }

public sealed record HotkeyGesture
{
    public const string DefaultNew = "Ctrl+Alt+N";
    public const string DefaultFloat = "Ctrl+Alt+F";
    public const string AltGrWarning = "Ctrl+Alt 在部分键盘布局中与 AltGr 重叠，可改用 Ctrl+Shift。";
    public HotkeyModifiers Modifiers { get; }
    public string Key { get; }
    public bool HasAltGrRisk => Modifiers.HasFlag(HotkeyModifiers.Alt);
    public uint VirtualKey => Key == "Space" ? 0x20u : Key[0];
    private HotkeyGesture(HotkeyModifiers modifiers, string key) => (Modifiers, Key) = (modifiers, key);
    public static HotkeyGesture Parse(string text) => TryParse(text, out var value) ? value! :
        throw new FormatException("快捷键须包含 Ctrl，仅支持 Ctrl、Alt、Shift 与字母、数字或空格。");
    public static bool TryParse(string? text, out HotkeyGesture? gesture)
    {
        gesture = null;
        if (string.IsNullOrWhiteSpace(text))
            return false;
        string[] parts = text.Split('+', StringSplitOptions.TrimEntries);
        if (parts.Length < 2)
            return false;
        HotkeyModifiers modifiers = HotkeyModifiers.None;
        foreach (string part in parts[..^1])
        {
            var modifier = part.ToUpperInvariant() switch
            {
                "CTRL" => HotkeyModifiers.Ctrl, "ALT" => HotkeyModifiers.Alt,
                "SHIFT" => HotkeyModifiers.Shift, _ => HotkeyModifiers.None
            };
            if (modifier == HotkeyModifiers.None || modifiers.HasFlag(modifier))
                return false;
            modifiers |= modifier;
        }
        if (!modifiers.HasFlag(HotkeyModifiers.Ctrl))
            return false;
        string key = parts[^1].ToUpperInvariant();
        if (key == "SPACE")
            key = "Space";
        else if (key.Length != 1 || !(key[0] is >= 'A' and <= 'Z' or >= '0' and <= '9'))
            return false;
        gesture = new(modifiers, key);
        return true;
    }
    public override string ToString() => "Ctrl+" + (Modifiers.HasFlag(HotkeyModifiers.Alt) ? "Alt+" : "") +
        (Modifiers.HasFlag(HotkeyModifiers.Shift) ? "Shift+" : "") + Key;
}
