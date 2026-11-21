namespace DeskNodes.Core.Services;

public enum HotkeyAction { NewNote, Raise }

public enum HotkeyRegistrationStatus { Active, Conflict, Cleared }

/// <summary>The actual system registration, separate from the persisted preference.</summary>
public sealed record HotkeyRegistration(string? Gesture, HotkeyRegistrationStatus Status)
{
    public string Message => Status switch
    {
        HotkeyRegistrationStatus.Active => $"{Gesture} 已生效",
        HotkeyRegistrationStatus.Conflict => $"{Gesture} 被占用，未生效，请更换",
        _ => "未设置快捷键"
    };
}
