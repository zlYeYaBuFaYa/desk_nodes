using DeskNodes.Core.Presentation;
using DeskNodes.Core.Domain;
using DeskNodes.Core.Services;
using System.Globalization;

namespace DeskNodes.Core.Tests;

public sealed class HistoryRulesTests
{
    [Theory]
    [InlineData(true, false, false, false, true)]
    [InlineData(false, false, false, true, false)]
    [InlineData(true, true, false, true, false)]
    [InlineData(true, false, true, false, false)]
    [InlineData(true, false, true, true, true)]
    public void NavigationProtectsTextAndFocusedControls(bool calendar, bool text, bool control, bool modified, bool expected) =>
        Assert.Equal(expected, HistoryRules.HandlesNavigation(calendar, text, control, modified));

    [Theory]
    [InlineData(0, "刚刚移出列表")]
    [InlineData(60, "1 分钟前移出列表")]
    [InlineData(3600, "1 小时前移出列表")]
    [InlineData(86400, "1 天前移出列表")]
    [InlineData(604800, "2026年1月1日 00:00 移出列表")]
    [InlineData(-1, "2026年1月1日 00:00 移出列表")]
    public void DeletionLabelsUseElapsedTimeAndExplicitDates(int seconds, string expected)
    {
        var deleted = new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);
        Assert.Equal(expected, HistoryRules.DeletedTime(deleted, deleted.AddSeconds(seconds), TimeZoneInfo.Utc));
    }
}

public sealed class HistoryProjectionTests
{
    [Theory]
    [InlineData(false, false, true)]
    [InlineData(false, true, true)]
    [InlineData(true, false, false)]
    [InlineData(true, true, true)]
    public void RestoreEligibilityDependsOnEntryKindAndLiveParent(bool item, bool parentExists, bool expected)
    {
        var parent = NoteId.New();
        var entry = new DeletedEntry(
            item ? new(null, ItemId.New()) : new(parent, null), parent, "便签",
            NoteColor.Paper, DateTimeOffset.UnixEpoch, item ? "事项" : null, ["甲", "乙"], 2);
        var projection = HistoryRules.ProjectDeleted(entry, parentExists ? new HashSet<NoteId> { parent } : []);
        Assert.Equal(expected, projection.CanRestore);
        Assert.Equal(expected ? "" : "原便签已删除，请先恢复便签", projection.Explanation);
        Assert.Equal(item ? "事项" : "甲\n乙\n还有 2 项", projection.Preview);
    }

    [Fact]
    public void EmptyAndExactPreviewDoNotAddRemainingLine()
    {
        var parent = NoteId.New();
        var entry = new DeletedEntry(new(parent, null), parent, "",
            NoteColor.Mint, DateTimeOffset.UnixEpoch, null, [], 0);
        Assert.Equal("", HistoryRules.ProjectDeleted(entry, new HashSet<NoteId>()).Preview);
        Assert.Equal("一\n二", HistoryRules.ProjectDeleted(entry with { Preview = ["一", "二"] }, new HashSet<NoteId>()).Preview);
        Assert.Equal("", HistoryRules.ProjectDeleted(entry with { Text = "" }, new HashSet<NoteId>()).Preview);
    }

    [Theory]
    [InlineData(false, false, false, HistoryItemState.Pending)]
    [InlineData(false, false, true, HistoryItemState.Completed)]
    [InlineData(false, true, true, HistoryItemState.Struck)]
    [InlineData(true, true, true, HistoryItemState.Deleted)]
    public void StatusPriorityPreservesDeletionAndStrike(bool deleted, bool struck, bool completed, HistoryItemState expected)
    {
        var projection = HistoryRules.ProjectItem(deleted, struck, completed, null);
        Assert.Equal(expected, projection.State);
        Assert.Null(projection.Carry);
    }

    [Fact]
    public void CarryAndAbsoluteDateUseGregorianInvariantFormatting()
    {
        var original = CultureInfo.CurrentCulture;
        try
        {
            CultureInfo.CurrentCulture = new("ar-SA");
            Assert.Equal("顺延至 11月5日", HistoryRules.ProjectItem(false, false, false,
                new HistoryDay(new DateOnly(2026, 11, 5))).Carry);
            Assert.Equal("2026年11月5日 00:00 移出列表", HistoryRules.DeletedTime(
                new(2026, 11, 5, 0, 0, 0, TimeSpan.Zero), new(2026, 11, 15, 0, 0, 0, TimeSpan.Zero), TimeZoneInfo.Utc));
        }
        finally
        {
            CultureInfo.CurrentCulture = original;
        }
    }
}
