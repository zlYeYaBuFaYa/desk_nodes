using DeskNodes.App.Platform;

namespace DeskNodes.Core.Tests;

public sealed class LoginItemAvailabilityTests
{
    [Theory]
    [InlineData("dotnet")]
    [InlineData("dotnet.exe")]
    [InlineData("DOTNET.EXE")]
    public void DotnetHostCannotModifyLoginItem(string host)
    {
        string path = Path.GetFullPath(host);
        Assert.NotNull(LoginItemAvailability.UnavailableReason(null, path));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("DeskNodes.exe")]
    public void MissingOrRelativeExecutableCannotModifyLoginItem(string? path)
    {
        Assert.NotNull(LoginItemAvailability.UnavailableReason(null, path));
    }

    [Fact]
    public void InstalledExecutableIsAvailableUnlessDataIsIsolated()
    {
        string path = Path.GetFullPath(Path.Combine("Program Files", "DeskNodes", "DeskNodes.exe"));
        Assert.Null(LoginItemAvailability.UnavailableReason(null, path));
        Assert.Null(LoginItemAvailability.UnavailableReason("  ", path));
        Assert.NotNull(LoginItemAvailability.UnavailableReason(Path.GetFullPath("isolated"), path));
        Assert.NotNull(LoginItemAvailability.UnavailableReason(null, path + '"'));
    }
}
