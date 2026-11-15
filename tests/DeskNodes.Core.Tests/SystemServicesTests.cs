using DeskNodes.Core.Services;
using DeskNodes.Core.Storage;

namespace DeskNodes.Core.Tests;

public sealed class SystemServicesTests
{
    [Theory]
    [InlineData("alt+ctrl+n", "Ctrl+Alt+N", 78u, true)]
    [InlineData("shift+ctrl+9", "Ctrl+Shift+9", 57u, false)]
    [InlineData("Ctrl+Space", "Ctrl+Space", 32u, false)]
    [InlineData("Ctrl+Alt+Shift+a", "Ctrl+Alt+Shift+A", 65u, true)]
    public void NormalizesAllowedGestures(string input, string expected, uint vk, bool altGr)
    {
        var gesture = HotkeyGesture.Parse(input);
        Assert.Equal(expected, gesture.ToString());
        Assert.Equal(vk, gesture.VirtualKey);
        Assert.Equal(altGr, gesture.HasAltGrRisk);
        Assert.Equal(gesture, HotkeyGesture.Parse(expected));
    }
    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("N")]
    [InlineData("Alt+N")]
    [InlineData("Ctrl+Win+N")]
    [InlineData("Ctrl+Ctrl+N")]
    [InlineData("Ctrl+Alt+Delete")]
    [InlineData("Alt+Tab")]
    [InlineData("Ctrl+Esc")]
    [InlineData("Ctrl+Shift+Esc")]
    [InlineData("Ctrl+F1")]
    [InlineData("Ctrl+é")]
    [InlineData("Ctrl++N")]
    public void RejectsUnsafeAndUnsupportedGestures(string? input) => Assert.False(HotkeyGesture.TryParse(input, out _));

    [Theory]
    [InlineData("Ctrl+Alt+F", HotkeyRegistrationStatus.Active, "Ctrl+Alt+F 已生效")]
    [InlineData("Ctrl+Alt+F", HotkeyRegistrationStatus.Conflict, "Ctrl+Alt+F 被占用，未生效，请更换")]
    [InlineData("Ctrl+Shift+N", HotkeyRegistrationStatus.Conflict, "Ctrl+Shift+N 被占用，未生效，请更换")]
    [InlineData(null, HotkeyRegistrationStatus.Cleared, "未设置快捷键")]
    public void RegistrationMessageReportsActualState(string? gesture, HotkeyRegistrationStatus status, string expected)
    {
        Assert.Equal(expected, new HotkeyRegistration(gesture, status).Message);
    }

    [Fact]
    public void BusinessPreferencesPersistNormalizedValuesAndRejectDuplicateWithoutWriting()
    {
        using var directory = new TestDirectory();
        using var database = directory.Open();
        var store = new BusinessPreferencesStore(database);
        Assert.Equal(new BusinessPreferences(), store.Load());
        var value = new BusinessPreferences("shift+ctrl+n", null, true, false);
        store.Save(value);
        Assert.Equal(value with { HotkeyNew = "Ctrl+Shift+N" }, store.Load());
        Assert.Throws<ArgumentException>(() => store.Save(new("Ctrl+N", "Ctrl+N")));
        Assert.Equal("Ctrl+Shift+N", store.Load().HotkeyNew);
    }
    [Fact]
    public void ResumeRestartsFullIdleDelayAndDoesNotExpandRoundToolbar()
    {
        var idle = new DeskNodes.Core.Presentation.ToolbarIdleMachine();
        var input = new DeskNodes.Core.Presentation.IdleInput();
        idle.Update(TimeSpan.Zero, input);
        idle.ResetIdle();
        Assert.Equal(DeskNodes.Core.Presentation.ToolbarIdleAction.None, idle.Update(TimeSpan.FromHours(1), input).Action);
        Assert.Equal(DeskNodes.Core.Presentation.ToolbarIdleAction.None, idle.Update(TimeSpan.FromHours(1).Add(TimeSpan.FromSeconds(14)), input).Action);
        var shrink = idle.Update(TimeSpan.FromHours(1).Add(TimeSpan.FromSeconds(15)), input);
        Assert.Equal(DeskNodes.Core.Presentation.ToolbarIdleAction.StartShrinkToHome, shrink.Action);
        idle.Update(TimeSpan.FromHours(1).Add(TimeSpan.FromSeconds(16)), input with { AnimationCompleted = true });
        idle.ResetIdle();
        Assert.Equal(DeskNodes.Core.Presentation.ToolbarIdleAction.None, idle.Update(TimeSpan.FromHours(2), input).Action);
        Assert.Equal(DeskNodes.Core.Presentation.ToolbarIdleState.Round, idle.State);
    }

}
