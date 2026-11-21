using DeskNodes.Core.Domain;
using DeskNodes.Core.Presentation;

namespace DeskNodes.Core.Tests;
public sealed class PresentationRulesTests
{
    private static ScreenSet ReservationScreens => new([
        new("a", "a", new(0, 0, 1000, 800), new(0, 0, 1000, 760), true),
        new("b", "b", new(1000, 0, 1000, 800), new(1000, 0, 1000, 760), false, 1.5)]);

    [Fact]
    public void HomeChangesRequireDockReservationLayout()
    {
        var previous = new LocalPreferences();
        Assert.True(PresentationRules.DockReservationChanged(ReservationScreens, previous, previous with { Home = new(ScreenEdge.Left) }));
        Assert.True(PresentationRules.DockReservationChanged(ReservationScreens, previous, previous with { Home = new(previous.Home.Edge, .2) }));
    }
    [Fact]
    public void AnchorScreenChangesRequireDockReservationLayout()
    {
        var previous = new LocalPreferences { Anchor = new(new(100, 100)) };
        Assert.True(PresentationRules.DockReservationChanged(ReservationScreens, previous, previous with { Anchor = new(new(1800, 100)) }));
        Assert.True(PresentationRules.DockReservationChanged(ReservationScreens, previous, previous with { Anchor = new(Edge: ScreenEdge.Right, DeviceHint: "b") }));
    }
    [Fact]
    public void UnrelatedPreferencesDoNotRearrangeDock()
    {
        var previous = new LocalPreferences();
        Assert.False(PresentationRules.DockReservationChanged(ReservationScreens, previous,
            previous with { Appearance = Appearance.Dark, Orientation = ToolbarOrientation.Horizontal, DeskCollapsed = true }));
    }
    [Fact]
    public void FreeMovementOnSameScreenDoesNotRearrangeDock()
    {
        var previous = new LocalPreferences { Anchor = new(new(1600, 100)) };
        Assert.False(PresentationRules.DockReservationChanged(ReservationScreens, previous, previous with { Anchor = new(new(2900, 600)) }));
    }
    [Theory]
    [InlineData(DeskTransition.Expanding, false, false)]
    [InlineData(DeskTransition.Expanding, true, true)]
    [InlineData(DeskTransition.Expanded, false, true)]
    [InlineData(DeskTransition.Collapsing, true, true)]
    public void RefreshDefersHiddenExpansionToPresent(DeskTransition transition, bool visible, bool show) =>
        Assert.Equal(show, PresentationRules.ShouldShowOnRefresh(transition, visible));

    [Fact]
    public void OtherDesktopPromptRequiresEveryNoteOnOtherDesktop()
    {
        Assert.True(PresentationRules.NeedsOtherDesktopPrompt([SuppressionReason.OtherDesktop, SuppressionReason.OtherDesktop | SuppressionReason.ArrangementPage]));
        Assert.False(PresentationRules.NeedsOtherDesktopPrompt([SuppressionReason.OtherDesktop, SuppressionReason.None]));
        Assert.False(PresentationRules.NeedsOtherDesktopPrompt([SuppressionReason.ArrangementPage, SuppressionReason.DockOverflow]));
        Assert.False(PresentationRules.NeedsOtherDesktopPrompt([]));
        var fallback = PresentationRules.Suppressed(false, null, 0, 0, false, true);
        Assert.False(PresentationRules.NeedsOtherDesktopPrompt([SuppressionReason.OtherDesktop, fallback]));
    }
    [Theory]
    [InlineData(SuppressionReason.Collapsed)]
    [InlineData(SuppressionReason.ArrangementPage)]
    [InlineData(SuppressionReason.DockOverflow)]
    [InlineData(SuppressionReason.Collapsed | SuppressionReason.ArrangementPage | SuppressionReason.DockOverflow)]
    public void HiddenCurrentDesktopNotePreventsOtherDesktopPrompt(SuppressionReason currentDesktopReason)
    {
        Assert.False(PresentationRules.NeedsOtherDesktopPrompt([
            currentDesktopReason, SuppressionReason.OtherDesktop | SuppressionReason.Collapsed]));
    }
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
    public void SelectionFocusPrefersThePickedNoteThenTheFirstVisible()
    {
        var first = NoteId.New();
        var picked = NoteId.New();
        var other = NoteId.New();
        Assert.Null(PresentationRules.SelectionFocus([], new HashSet<NoteId>()));
        Assert.Equal(first, PresentationRules.SelectionFocus([first, picked], new HashSet<NoteId>()));
        Assert.Equal(picked, PresentationRules.SelectionFocus([first, picked, other], new HashSet<NoteId> { picked }));
    }
    [Fact]
    public void CollapseStaysOpenUntilTheLastNoteArrives()
    {
        var state = new PresentationState();
        long generation = state.Request(true);
        state.Expect(generation, 3);
        Assert.False(state.Complete(generation));
        Assert.Equal(DeskTransition.Collapsing, state.Transition);
        Assert.False(state.Complete(generation));
        Assert.True(state.Complete(generation));
        Assert.Equal(DeskTransition.Collapsed, state.Transition);
        long replaced = state.Request(true);
        state.Expect(replaced, 2);
        long newer = state.Request(false);
        Assert.False(state.Complete(replaced));
        Assert.Equal(DeskTransition.Expanding, state.Transition);
        Assert.True(state.Complete(newer));
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
