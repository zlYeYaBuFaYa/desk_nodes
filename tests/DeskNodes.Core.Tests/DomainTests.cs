using System.Globalization;
using DeskNodes.Core.Domain;
using DeskNodes.Core.Storage;

namespace DeskNodes.Core.Tests;

public sealed class DomainTests
{
    [Fact]
    public void IdentifiersRoundTripAndRemainDistinct()
    {
        NoteId note = NoteId.New();
        ItemId item = ItemId.New();
        Assert.NotEqual(Guid.Empty, note.Value);
        Assert.NotEqual(Guid.Empty, item.Value);
        Assert.NotEqual(note, NoteId.New());
        Assert.NotEqual(item, ItemId.New());
        Assert.Equal(note, NoteId.Parse(note.ToString()));
        Assert.Equal(item, ItemId.Parse(item.ToString()));
        Assert.Throws<FormatException>(() => NoteId.Parse("bad"));
        Assert.Throws<FormatException>(() => ItemId.Parse("bad"));
    }

    [Theory]
    [InlineData("2024-02-29")]
    [InlineData("0001-01-01")]
    [InlineData("9999-12-31")]
    public void HistoryDayRoundTripsStrictGregorianDate(string value)
    {
        using var culture = new CultureScope("ar-SA");
        HistoryDay day = HistoryDay.Parse(value);
        Assert.Equal(value, day.ToString());
        Assert.Equal(DateOnly.ParseExact(value, "yyyy-MM-dd", CultureInfo.InvariantCulture), day.Value);
    }

    [Theory]
    [InlineData("2023-02-29")]
    [InlineData("2026-04-31")]
    [InlineData("2026-1-01")]
    [InlineData("26-01-01")]
    [InlineData("2026/01/01")]
    [InlineData("2026-01-01 ")]
    [InlineData(" 2026-01-01")]
    [InlineData("2026-01-01T00:00:00Z")]
    [InlineData("0000-01-01")]
    [InlineData("")]
    [InlineData(null)]
    public void HistoryDayRejectsInvalidOrNonCanonicalInput(string? value)
    {
        Assert.False(HistoryDay.TryParse(value, out _));
        Assert.Throws<FormatException>(() => HistoryDay.Parse(value!));
    }

    [Theory]
    [InlineData(false, false)]
    [InlineData(true, false)]
    [InlineData(false, true)]
    public void ItemAcceptsExclusiveStates(bool completed, bool struck)
    {
        NoteItem item = TestData.Item(NoteId.New(), completed: completed, struck: struck);
        Assert.Equal(completed, item.Completed);
        Assert.Equal(struck, item.Struck);
    }

    [Fact]
    public void ItemRejectsCompletedAndStruck()
        => Assert.Throws<ArgumentException>(() => TestData.Item(NoteId.New(), completed: true, struck: true));

    [Theory]
    [InlineData(NoteColor.Paper, "paper")]
    [InlineData(NoteColor.Lemon, "lemon")]
    [InlineData(NoteColor.Apricot, "apricot")]
    [InlineData(NoteColor.Cherry, "cherry")]
    [InlineData(NoteColor.Lavender, "lavender")]
    [InlineData(NoteColor.Mist, "mist")]
    [InlineData(NoteColor.Mint, "mint")]
    public void ColorsHaveStableStorageIds(NoteColor color, string id)
    {
        Assert.Equal(id, color.ToStorageId());
        Assert.Equal(color, NoteColors.ParseStorageId(id));
    }

    [Fact]
    public void UnknownColorsAreRejected()
    {
        Assert.Throws<FormatException>(() => NoteColors.ParseStorageId("Paper"));
        Assert.Throws<ArgumentOutOfRangeException>(() => ((NoteColor)100).ToStorageId());
    }

    [Fact]
    public void GeometryAllowsNegativeOriginsButRejectsInvalidDimensionsAndDocking()
    {
        var bounds = new RectD(-100, -200, 288, 240);
        Assert.Equal(-100, bounds.X);
        Assert.Equal(bounds, new Placement(bounds, "", DockEdge.Left, 0).Bounds);
        Assert.Throws<ArgumentOutOfRangeException>(() => new RectD(0, 0, -1, 20));
        Assert.Throws<ArgumentOutOfRangeException>(() => new RectD(double.NaN, 0, 1, 20));
        Assert.Throws<ArgumentOutOfRangeException>(() => new RectD(0, 0, 1, double.PositiveInfinity));
        Assert.Throws<ArgumentException>(() => new Placement(bounds, "", DockEdge.Left));
        Assert.Throws<ArgumentException>(() => new Placement(bounds, "", dockOrder: 0));
        Assert.Throws<ArgumentException>(() => new Placement(bounds, "", DockEdge.Left, -1));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("  ")]
    public void DataDirectoryUsesKnownLocalFolderWhenOverrideIsEmpty(string? value)
    {
        using var directory = new TestDirectory();
        Assert.Equal(Path.Combine(directory.DirectoryPath, "DeskNodes"),
            DataDirectory.Resolve(value, directory.DirectoryPath));
    }

    [Fact]
    public void DataDirectoryOverrideWinsEvenWhenKnownFolderIsMissing()
    {
        using var directory = new TestDirectory();
        Assert.Equal(directory.DirectoryPath, DataDirectory.Resolve(directory.DirectoryPath, ""));
        Assert.Throws<InvalidOperationException>(() => DataDirectory.Resolve(null, ""));
        Assert.Equal("DeskNodes.sqlite3", DataDirectory.DatabaseFileName);
    }

    [Fact]
    public void DataDirectoryReadsEnvironmentOverrideAndRestoresItAfterward()
    {
        using var directory = new TestDirectory();
        string? previous = Environment.GetEnvironmentVariable(DataDirectory.OverrideVariable);
        try
        {
            Environment.SetEnvironmentVariable(DataDirectory.OverrideVariable, directory.DirectoryPath);
            Assert.Equal(directory.DirectoryPath, DataDirectory.Resolve());
            Environment.SetEnvironmentVariable(DataDirectory.OverrideVariable, null);
            Assert.Equal(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "DeskNodes"), DataDirectory.Resolve());
        }
        finally
        {
            Environment.SetEnvironmentVariable(DataDirectory.OverrideVariable, previous);
        }
    }

    [Fact]
    public void DataDirectoryTrailingSeparatorPreservesCanonicalPathAndInstanceIdentity()
    {
        using var directory = new TestDirectory();
        string plain = DataDirectory.Resolve(directory.DirectoryPath, "");
        string trailing = DataDirectory.Resolve(directory.DirectoryPath + Path.DirectorySeparatorChar, "");
        Assert.Equal(plain, trailing);
        Assert.Equal(DeskNodes.App.Platform.SingleInstance.Identity(plain),
            DeskNodes.App.Platform.SingleInstance.Identity(trailing));
        string other = DataDirectory.Resolve(Path.Combine(directory.DirectoryPath, "other"), "");
        Assert.NotEqual(plain, other);
        Assert.NotEqual(DeskNodes.App.Platform.SingleInstance.Identity(plain),
            DeskNodes.App.Platform.SingleInstance.Identity(other));
    }

    [Fact]
    public void DataDirectoryPreservesRoot()
    {
        string root = Path.GetPathRoot(Path.GetFullPath("."))!;
        Assert.Equal(root, DataDirectory.Resolve(root, ""));
        if (OperatingSystem.IsWindows())
        {
            Assert.Equal(@"C:\", DataDirectory.Resolve(@"C:\", ""));
            const string uncRoot = @"\\server\share\";
            Assert.Equal(Path.TrimEndingDirectorySeparator(Path.GetFullPath(uncRoot)),
                DataDirectory.Resolve(uncRoot, ""));
            Assert.Equal(Path.GetPathRoot(uncRoot), Path.GetPathRoot(DataDirectory.Resolve(uncRoot, "")));
        }
    }

    [Fact]
    public void SystemClockReturnsUtcAndLocalTimeZone()
    {
        var provider = new FixedTimeProvider();
        var clock = new SystemClock(provider);
        Assert.Equal(provider.GetUtcNow(), clock.UtcNow);
        Assert.Equal(TimeSpan.Zero, clock.UtcNow.Offset);
        Assert.Equal(provider.LocalTimeZone, clock.TimeZone);
        Assert.Equal(TimeSpan.Zero, new SystemClock().UtcNow.Offset);
        Assert.Equal(TimeZoneInfo.Local, new SystemClock().TimeZone);
    }

    private sealed class FixedTimeProvider : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => new(2026, 11, 15, 12, 0, 0, TimeSpan.Zero);
        public override TimeZoneInfo LocalTimeZone => TimeZoneInfo.Utc;
    }

    private sealed class CultureScope : IDisposable
    {
        private readonly CultureInfo previous = CultureInfo.CurrentCulture;
        public CultureScope(string name) => CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo(name);
        public void Dispose() => CultureInfo.CurrentCulture = previous;
    }
}
