using DeskNodes.Core.Domain;
using DeskNodes.Core.Presentation;

namespace DeskNodes.Core.Tests;
public sealed class PresentationRulesTests
{
    [Fact]
    public void RefreshCannotRemoveIndependentSuppressionReasons()
    {
        var reasons = PresentationRules.Suppressed(true, 0, 1, 2, true, false);
        Assert.Equal(SuppressionReason.Collapsed | SuppressionReason.ArrangementPage | SuppressionReason.DockOverflow | SuppressionReason.OtherDesktop, reasons);
        Assert.Equal(SuppressionReason.DockOverflow | SuppressionReason.OtherDesktop,
            PresentationRules.Suppressed(false, 1, 1, 2, true, false));
    }
    [Theory]
    [InlineData(null, 3, 1, true)]
    [InlineData(1, 3, 1, true)]
    [InlineData(0, 3, 1, false)]
    [InlineData(0, 0, 2, true)]
    public void PageMappingClampsPerScreenAndLeavesNewNotesVisible(int? page, int current, int last, bool visible) =>
        Assert.Equal(visible, PresentationRules.Suppressed(false, page, current, last, false, true) == SuppressionReason.None);
    [Fact]
    public void ReversingTransitionRejectsStaleCompletion()
    {
        var state = new PresentationState();
        long old = state.Request(true);
        long latest = state.Request(false);
        Assert.False(state.Complete(old));
        Assert.Equal(DeskTransition.Expanding, state.Transition);
        Assert.True(state.Complete(latest));
        Assert.Equal(DeskTransition.Expanded, state.Transition);
        Assert.True(state.Complete(latest));
        Assert.Equal(DeskTransition.Expanded, state.Transition);
    }
    [Fact]
    public void SelectionReplacesAppendsAndRetainsOnlyVisible()
    {
        var a = NoteId.New();
        var b = NoteId.New();
        var c = NoteId.New();
        var selection = new NoteSelection();
        Assert.False(selection.CanDelete);
        selection.Apply([a, b]);
        selection.Apply([c], true);
        Assert.Equal(3, selection.Picked.Count);
        selection.Apply([a]);
        Assert.Equal(a, Assert.Single(selection.Picked));
        selection.Apply([a, b]);
        selection.Retain([b, c]);
        Assert.Equal(b, Assert.Single(selection.Picked));
        selection.Toggle(b);
        Assert.False(selection.CanDelete);
    }
    [Fact]
    public void BoxIntersectionUsesPhysicalCoordinatesAcrossNegativeScreenOrigins()
    {
        var a = NoteId.New();
        var b = NoteId.New();
        var c = NoteId.New();
        var result = NoteSelection.Intersect(new(-30, 40, 100, 60),
            [(a, new(-200, 0, 180, 100)), (b, new(0, 0, 150, 150)), (c, new(70, 40, 100, 100))]);
        Assert.Equal(new[] { a, b }, result);
    }
    [Fact]
    public void EmptyDragDoesNotSelectContainingNote()
    {
        Assert.Empty(NoteSelection.Intersect(new(50, 50, 0, 0), [(NoteId.New(), new(0, 0, 100, 100))]));
    }
    [Fact]
    public void PromptsMoveApartAndClampToSmallWorkArea()
    {
        var work = new RectD(-1000, 20, 1000, 700);
        Assert.Equal(692, PresentationRules.DeletionPrompt(work, false).Bottom);
        Assert.Equal(628, PresentationRules.DeletionPrompt(work, true).Bottom);
        var tiny = new RectD(100, 100, 100, 30);
        Assert.Equal(tiny, PresentationRules.DeletionPrompt(tiny, true));
        Assert.Equal(tiny, PresentationRules.Prompt(tiny, 360, 72, 80));
    }
    [Theory]
    [InlineData(true, false, false, true)]
    [InlineData(true, true, false, false)]
    [InlineData(true, false, true, false)]
    [InlineData(false, false, false, false)]
    public void ForeignForegroundEndsRaiseExceptComposition(bool inactive, bool owned, bool composing, bool ends) =>
        Assert.Equal(ends, PresentationRules.EndsRaise(toggle: false, escape: false, collapsed: false, empty: false, appDeactivated: inactive, foregroundOwned: owned, composing: composing));
    [Fact]
    public void ExplicitRaiseEndDoesNotDependOnForeground()
    {
        Assert.True(PresentationRules.EndsRaise(toggle: true, escape: false, collapsed: false, empty: false, appDeactivated: false, foregroundOwned: true, composing: true));
        Assert.True(PresentationRules.EndsRaise(toggle: false, escape: true, collapsed: false, empty: false, appDeactivated: false, foregroundOwned: true, composing: false));
        Assert.True(PresentationRules.EndsRaise(toggle: false, escape: false, collapsed: true, empty: false, appDeactivated: false, foregroundOwned: true, composing: false));
        Assert.True(PresentationRules.EndsRaise(toggle: false, escape: false, collapsed: false, empty: true, appDeactivated: false, foregroundOwned: true, composing: false));
    }
}
