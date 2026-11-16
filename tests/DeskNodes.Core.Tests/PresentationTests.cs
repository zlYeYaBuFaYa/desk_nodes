using DeskNodes.Core.Domain;
using DeskNodes.Core.Presentation;
using DeskNodes.Core.Services;

namespace DeskNodes.Core.Tests;

public sealed class PresentationTests
{
    private static ScreenInfo Screen(double width = 1000, double height = 800, double x = 0, string id = "a", bool primary = true) =>
        new(id, id, new(x, 0, width, height), new(x, 0, width, height), primary);
    private static Note Note(int order, double height = 240, bool collapsed = false, bool auto = false, string screen = "a", bool docked = false) =>
        new(NoteId.New(), "n", NoteColor.Paper, order, new(new(0, 0, 288, height), screen, docked ? DockEdge.Left : null, docked ? order : null),
            NoteLevel.Back, null, auto, collapsed, TestData.Now, TestData.Now);
    private static TimeSpan T(double seconds) => TimeSpan.FromSeconds(seconds);

    [Theory]
    [InlineData(DockEdge.Left, false, 8, 696, 288, 96)]
    [InlineData(DockEdge.Right, false, 704, 696, 288, 96)]
    [InlineData(DockEdge.Top, false, 896, 8, 96, 260)]
    [InlineData(DockEdge.Left, true, 8, 392, 288, 96)]
    [InlineData(DockEdge.Right, true, 704, 392, 288, 96)]
    [InlineData(DockEdge.Top, true, 596, 8, 96, 260)]
    public void OverflowOccupiesEndOfReservedDockSide(DockEdge edge, bool reserve,
        double x, double y, double width, double height)
    {
        RectD? home = reserve ? edge switch
        {
            DockEdge.Left => new(0, 500, 64, 64),
            DockEdge.Right => new(936, 500, 64, 64),
            _ => new(704, 0, 64, 64)
        } : null;
        var items = Enumerable.Range(0, 10).Select(i => new DockItem(NoteId.New(), i));
        var result = DockLayout.Arrange(Screen(), edge, items, home);
        var overflow = Assert.IsType<RectD>(result.OverflowBounds);
        Assert.Equal(new RectD(x, y, width, height), overflow);
        Assert.NotEmpty(result.Overflow);
        Assert.All(result.Visible, note => Assert.False(note.Bounds.Intersects(overflow)));
        if (home is { } zone) Assert.False(overflow.Intersects(zone));
    }
    [Fact]
    public void DockWithoutOverflowDoesNotReserveLabel()
    {
        var result = DockLayout.Arrange(Screen(), DockEdge.Left, [new(NoteId.New(), 0)]);
        Assert.Empty(result.Overflow);
        Assert.Null(result.OverflowBounds);
    }
    [Fact]
    public void OverflowIsClampedToShortReservedSide()
    {
        var screen = Screen(width: 100, height: 70);
        var result = DockLayout.Arrange(screen, DockEdge.Left, [new(NoteId.New(), 0), new(NoteId.New(), 1)]);
        Assert.Equal(new RectD(8, 35, 84, 27), result.OverflowBounds);
        Assert.Equal(new RectD(8, 8, 84, 54), Assert.Single(result.Visible).Bounds);
        Assert.Single(result.Visible);
        Assert.Single(result.Overflow);
    }
    [Fact]
    public void ScreensResolveNegativeCoordinatesIntersectionAndFallback()
    {
        var left = Screen(x: -1000, id: "left", primary: false);
        var main = Screen();
        var set = new ScreenSet([left, main]);
        Assert.Equal(left, set.At(new(-1, 20)));
        Assert.Equal(left, set.For(new(-500, 10, 510, 20)));
        Assert.Equal(main, set.Resolve("offline"));
        Assert.False(set.IsOuter(left, ScreenEdge.Right));
        Assert.False(set.IsOuter(main, ScreenEdge.Left));
        Assert.True(set.IsOuter(left, ScreenEdge.Left));
    }
    [Theory]
    [InlineData(81, true)]
    [InlineData(82, false)]
    public void SnapThresholdUsesOuterFrame(double distance, bool snaps)
    {
        var s = Screen();
        var r = ToolbarGeometry.Release(new([s]), new(100, 400), "a", new(distance, 200, 64, 296));
        Assert.Equal(snaps ? ScreenEdge.Left : null, r.Edge);
        if (snaps) Assert.Equal(8, r.Bounds.X);
    }
    [Fact]
    public void SnapTiesPreferOriginalThenLeftAndSeamsNeverSnap()
    {
        var s = Screen(); var set = new ScreenSet([s]);
        var r = new RectD(50, 50, 64, 296);
        Assert.Equal(ScreenEdge.Top, ToolbarGeometry.Release(set, new(100, 100), "a", r, ScreenEdge.Top).Edge);
        Assert.Equal(ScreenEdge.Left, ToolbarGeometry.Release(set, new(100, 100), "a", r).Edge);
        var left = Screen(x: -1000, id: "left", primary: false);
        Assert.Null(ToolbarGeometry.Release(new([left, s]), new(10, 400), "a", new(1, 200, 64, 296)).Edge);
        Assert.Equal(left, ToolbarGeometry.Release(new([left, s]), new(-3000, 400), "left", r).Screen);
    }
    [Fact]
    public void HomeDefaultSpanHitZoneSeamFallbackAndProjection()
    {
        var s = Screen(); var set = new ScreenSet([s]);
        var home = ToolbarGeometry.Home(set, s, new());
        Assert.True(home.Position.IsDefault);
        Assert.Equal(724 - .4 * 648, home.Entrance.Center.Y, 6);
        Assert.Equal(new SizeD(64, 64), new(home.HitZone.Width, home.HitZone.Height));
        Assert.Equal(home.HitZone, home.HomeZone);
    }
    [Fact]
    public void SmallHomeUsesMidpointAndExpandCoversEntrance()
    {
        var s = Screen(height: 100); var set = new ScreenSet([s]);
        Assert.Equal(50, ToolbarGeometry.Home(set, s, new()).Entrance.Center.Y);
        var normal = Screen(); set = new([normal]);
        foreach (var edge in Enum.GetValues<ScreenEdge>())
        foreach (var orientation in Enum.GetValues<ToolbarOrientation>())
        {
            var home = ToolbarGeometry.Home(set, normal, new(edge, .4));
            var full = ToolbarGeometry.Expand(home, normal.WorkArea, orientation, false);
            Assert.True(full.X <= home.Entrance.X && full.Y <= home.Entrance.Y && full.Right >= home.Entrance.Right && full.Bottom >= home.Entrance.Bottom);
        }
        var neighbor = Screen(x: 1000, id: "b", primary: false);
        Assert.Equal(ScreenEdge.Left, ToolbarGeometry.Home(new([normal, neighbor]), normal, new()).Position.Edge);
        var projected = ToolbarGeometry.ProjectHome(set, normal, new(850, -50));
        Assert.Equal(ScreenEdge.Top, projected.Position.Edge);
        Assert.Equal(36, projected.Entrance.Center.Y);
        Assert.Equal(T(.3), ToolbarGeometry.ReturnDuration(0));
        Assert.Equal(T(.5), ToolbarGeometry.ReturnDuration(900));
        Assert.Equal(new SizeD(428, 64), ToolbarGeometry.FullSize(ToolbarOrientation.Horizontal, true));
    }
    [Fact]
    public void NewAvoidsFullTargetAndNotesThenCascadesWithinSafetyInset()
    {
        var s = Screen(); var set = new ScreenSet([s]);
        var toolbar = new RectD(8, 8, 64, 296); var existing = new RectD(80, 8, 288, 240);
        var placed = NoteLayout.New(set, "a", toolbar, [existing]);
        Assert.False(placed.Intersects(toolbar)); Assert.False(placed.Intersects(existing));
        var cascade = NoteLayout.New(set, "a", s.WorkArea, [s.WorkArea]);
        Assert.Equal(new RectD(32, 32, 288, 240), cascade);
        Assert.Equal(new SizeD(184, 84), NoteLayout.Constrain(new(900, 900), new(0, 0, 200, 100)));
        Assert.Equal(480, NoteLayout.Constrain(new(288, 900), s.WorkArea, true).Height);
        var restored = NoteLayout.Restore(new(new(-500, 900, 288, 240), "offline"), set);
        Assert.Equal("a", restored.DisplayDeviceHint); Assert.Equal(8, restored.Bounds.X); Assert.Equal(792, restored.Bounds.Bottom);
    }
    [Fact]
    public void ArrangementUsesShortestLeftColumnAndPagesPreservingExpandedHeight()
    {
        var s = Screen(width: 638, height: 600); var set = new ScreenSet([s]);
        var notes = new[] { Note(0, 200), Note(1, 120), Note(2, 200, collapsed: true), Note(3, 240, auto: true, docked: true), Note(4, 500) };
        double measuredWidth = 0;
        var result = Arranger.Arrange(set, notes.Reverse(), (_, width) => { measuredWidth = width; return 300; });
        Assert.Equal(22, result.Notes[0].Bounds.X); Assert.Equal(328, result.Notes[1].Bounds.X);
        Assert.Equal(328, result.Notes[2].Bounds.X); Assert.Equal(32, result.Notes[2].Bounds.Height);
        Assert.Equal(200, result.Notes[2].ExpandedSize.Height);
        Assert.Equal(288, measuredWidth); Assert.Equal(1, result.Notes[^1].Page);
        Assert.Null(result.Notes[3].ToPlacement(s).DockEdge);
        Assert.Equal(1, result.PageFor("a", 30));
    }
    [Fact]
    public void ArrangementSkipsForbiddenRegionAndSharesPagesAcrossScreens()
    {
        var a = Screen(width: 638, height: 600); var b = Screen(x: -1000, id: "b", primary: false);
        var r = Arranger.Arrange(new([a, b]), [Note(0), Note(1), Note(2), Note(3), Note(4, screen: "b")], (_, _) => 240,
            new RectD(22, 22, 288, 64), "a");
        Assert.Equal(new RectD(328, 22, 288, 240), r.Notes[0].Bounds);
        Assert.Equal(new RectD(22, 104, 288, 240), r.Notes[1].Bounds);
        Assert.All(r.Notes.Where(n => n.ScreenId == "a"), n => Assert.False(n.Bounds.Intersects(new(22, 22, 288, 64))));
        Assert.Equal(0, r.PageFor("b", 99));
        Assert.True(r.Notes.Single(n => n.ScreenId == "b").Bounds.X < 0);
    }
    [Fact]
    public void DockReservesHomeOnlyAndReturnsOverflowPagesAndDetachBand()
    {
        var s = Screen(height: 600);
        var items = Enumerable.Range(0, 6).Select(i => new DockItem(NoteId.New(), i)).ToArray();
        var top = DockLayout.Arrange(s, DockEdge.Top, items);
        Assert.All(top.Visible, n => Assert.Equal(200, n.Bounds.Height));
        Assert.NotEmpty(top.Overflow); Assert.True(top.PageCount > 1);
        var next = DockLayout.Arrange(s, DockEdge.Top, items, page: 1);
        Assert.DoesNotContain(next.Visible[0].Id, top.Visible.Select(v => v.Id));
        var home = new RectD(0, 100, 64, 64);
        var side = DockLayout.Arrange(s, DockEdge.Left, items, home);
        Assert.All(side.Visible, n => Assert.True(n.Bounds.Y >= 176));
        Assert.False(DockLayout.ShouldDetach(DockEdge.Left, s.WorkArea, new(336, 200)));
        Assert.True(DockLayout.ShouldDetach(DockEdge.Left, s.WorkArea, new(337, 200)));
    }
    [Fact]
    public void CollapseUsesLeftFallbackAndCapsBadge()
    {
        Assert.Null(CollapseGeometry.Badge(0)); Assert.Equal("99", CollapseGeometry.Badge(99)); Assert.Equal("99+", CollapseGeometry.Badge(100));
        var target = CollapseGeometry.Target(new(936, 100, 56, 56), Screen().WorkArea, 2);
        Assert.True(target.Right < 936); Assert.Equal(24, target.Width);
    }
    [Fact]
    public void PreferencesRoundTripAndUnknownValuesFallBackIndividually()
    {
        using var dir = new TestDirectory(); var log = new Log(); var store = new LocalPreferencesStore(log, dir.DirectoryPath);
        store.Save(new() { NewHeight = 0, Home = new(ScreenEdge.Left, .2), ReduceMotion = true });
        Assert.Equal(0, store.Load().NewHeight); Assert.Equal(.2, store.Load().Home.Ratio); Assert.True(store.Load().ReduceMotion);
        File.WriteAllText(Path.Combine(dir.DirectoryPath, "LocalPreferences.json"), """{"note.font":"future","note.textSize":"future","app.appearance":"future","toolbar.orientation":"future","toolbar.autoShrink":22,"note.newWidth":12,"toolbar.home":{"edge":"future","ratio":0.1},"note.newHeight":0}""");
        var p = store.Load();
        Assert.Equal(NoteFont.Default, p.Font); Assert.Equal(NoteTextSize.Standard, p.TextSize); Assert.Equal(Appearance.System, p.Appearance);
        Assert.Equal(ToolbarOrientation.Vertical, p.Orientation); Assert.Equal(AutoShrink.Seconds15, p.AutoShrink);
        Assert.Equal(288, p.NewWidth); Assert.True(p.Home.IsDefault); Assert.Equal(0, p.NewHeight); Assert.Equal(0, log.Errors);
    }
    [Fact]
    public void CorruptPreferencesArePreservedAndLoggedBeforeNextSave()
    {
        using var dir = new TestDirectory(); var log = new Log(); var store = new LocalPreferencesStore(log, dir.DirectoryPath);
        string path = Path.Combine(dir.DirectoryPath, "LocalPreferences.json"); File.WriteAllText(path, "{broken");
        Assert.Equal(240, store.Load().NewHeight); Assert.Equal(1, log.Errors);
        string preserved = Assert.Single(Directory.GetFiles(dir.DirectoryPath, "*.corrupt-*"));
        store.Save(new()); Assert.Equal("{broken", File.ReadAllText(preserved));
    }
    [Fact]
    public void IdleInterruptionsRestartFullDelayAndDisableExpandsImmediately()
    {
        var m = new ToolbarIdleMachine(); Assert.Equal(T(15), m.Update(T(0), new()).NextWake);
        m.Update(T(14), new(MenuOpen: true)); Assert.Equal(T(29), m.Update(T(14), new()).NextWake);
        Assert.Equal(ToolbarIdleAction.None, m.Update(T(28.9), new()).Action);
        Assert.Equal(ToolbarIdleAction.StartShrinkToHome, m.Update(T(29), new()).Action);
        Assert.Equal(ToolbarIdleAction.StartExpand, m.Update(T(29.1), new(AutoShrink: AutoShrink.Off)).Action);
    }
    [Fact]
    public void HoverNeeds140msThenUnusedDepartureGetsGraceAndOperationResetsIt()
    {
        var m = new ToolbarIdleMachine(); m.Update(T(0), new()); m.Update(T(15), new(AtHome: true));
        m.Update(T(15.3), new(AnimationCompleted: true));
        Assert.Equal(T(16.14), m.Update(T(16), new(PointerInside: true)).NextWake);
        Assert.Equal(ToolbarIdleAction.None, m.Update(T(16.139), new(PointerInside: true)).Action);
        Assert.Equal(ToolbarIdleAction.StartExpand, m.Update(T(16.14), new(PointerInside: true)).Action);
        m.Update(T(16.5), new(PointerInside: true, AnimationCompleted: true));
        Assert.Equal(T(18.5), m.Update(T(17), new()).NextWake);
        Assert.Equal(T(32.1), m.Update(T(17.1), new(Operated: true)).NextWake);
        Assert.Equal(ToolbarIdleAction.StartShrinkInPlace, m.Update(T(32.1), new(AtHome: true)).Action);
        Assert.Equal(ToolbarIdleAction.StartExpand, m.Update(T(32.2), new(PointerInside: true)).Action);
    }
    [Theory]
    [InlineData(true)] [InlineData(false)]
    public void ReturnOnlyExpandsAtArrivalIfPointerStayed(bool stays)
    {
        var m = new ToolbarIdleMachine(); m.Update(T(0), new()); m.Update(T(15), new());
        m.Update(T(15.1), new(PointerInside: true)); Assert.True(m.PendingExpand);
        if (!stays) { m.Update(T(15.2), new()); Assert.False(m.PendingExpand); }
        var output = m.Update(T(16), new(PointerInside: stays, AnimationCompleted: true));
        Assert.Equal(stays ? ToolbarIdleAction.StartExpand : ToolbarIdleAction.None, output.Action);
        Assert.Equal(stays ? ToolbarIdleState.Expanding : ToolbarIdleState.Round, m.State);
    }
    [Fact]
    public void HoverGraceActuallyExpiresAndPressedDragDoesNotWakeRound()
    {
        var m = new ToolbarIdleMachine();
        m.Update(T(0), new()); m.Update(T(15), new(AtHome: true));
        m.Update(T(15.3), new(AnimationCompleted: true));
        Assert.Null(m.Update(T(16), new(PointerInside: true, Dragging: true, Pressed: true)).NextWake);
        Assert.Equal(ToolbarIdleState.Round, m.State);
        Assert.Equal(ToolbarIdleAction.StartExpand, m.Update(T(17), new(Clicked: true)).Action);
        m.Update(T(17.5), new(AnimationCompleted: true));
        Assert.Equal(T(32.5), m.Update(T(18), new()).NextWake);
        m.Update(T(32.5), new(AtHome: true)); m.Update(T(33), new(AnimationCompleted: true));
        m.Update(T(34), new(PointerInside: true)); m.Update(T(34.14), new(PointerInside: true));
        // Leaving during expansion must still receive the hover-only grace period.
        m.Update(T(34.2), new());
        Assert.Equal(T(36.5), m.Update(T(35), new(AnimationCompleted: true)).NextWake);
        Assert.Equal(ToolbarIdleAction.StartShrinkToHome, m.Update(T(36.5), new()).Action);
    }
    [Theory]
    [InlineData("pointer")] [InlineData("drag")] [InlineData("pressed")]
    [InlineData("animation")] [InlineData("settings")] [InlineData("keep")]
    public void EveryIdleBlockerRestartsFullDelay(string blocker)
    {
        var m = new ToolbarIdleMachine(); m.Update(T(0), new());
        m.Update(T(14), new(PointerInside: blocker == "pointer", Dragging: blocker == "drag", Pressed: blocker == "pressed",
            Animating: blocker == "animation", SettingsVisible: blocker == "settings", KeepExpanded: blocker == "keep"));
        Assert.Equal(T(30), m.Update(T(15), new()).NextWake);
        Assert.Equal(ToolbarIdleAction.None, m.Update(T(29.99), new()).Action);
    }
    [Fact]
    public void InvalidPreferenceFieldKeepsNeighborsAndMissingHeightUsesFixedDefault()
    {
        using var dir = new TestDirectory(); var log = new Log();
        File.WriteAllText(Path.Combine(dir.DirectoryPath, "LocalPreferences.json"),
            """{"note.newWidth":"bad","toolbar.home":{"edge":"left","ratio":9},"reduceMotion":true,"toolbar.autoShrink":10}""");
        var p = new LocalPreferencesStore(log, dir.DirectoryPath).Load();
        Assert.Equal(288, p.NewWidth); Assert.Equal(240, p.NewHeight); Assert.True(p.Home.IsDefault);
        Assert.True(p.ReduceMotion); Assert.Equal(AutoShrink.Seconds10, p.AutoShrink); Assert.Equal(0, log.Errors);
        Assert.Equal(new SizeD(340, 480), NoteLayout.NewSize(p with { NewWidth = 340, NewHeight = 0 }, Screen().WorkArea, width => width * 2));
    }
    [Fact]
    public void ForbiddenFirstColumnDoesNotCreateAnEmptyPage()
    {
        var s = Screen(width: 638, height: 600);
        var result = Arranger.Arrange(new([s]), [Note(0, 500)], (_, _) => 500, new(22, 22, 288, 556), "a");
        var note = Assert.Single(result.Notes);
        Assert.Equal(328, note.Bounds.X); Assert.Equal(0, note.Page);
    }
    [Fact]
    public void NewOnPreferredScreenNeverUsesAnotherScreensObstacleEdges()
    {
        var s = Screen(); var left = Screen(x: -1000, id: "left", primary: false);
        var placed = NoteLayout.New(new([s, left]), "a", new(-900, 10, 64, 296), [new(-800, 8, 288, 240)]);
        Assert.Equal(new RectD(8, 8, 288, 240), placed);
    }
    [Fact]
    public void SupersededAnimationCallbackDoesNotCompleteReversedExpansion()
    {
        var m = new ToolbarIdleMachine(); m.Update(T(0), new());
        var shrinking = m.Update(T(15), new(AtHome: true));
        var expanding = m.Update(T(15.1), new(PointerInside: true));
        Assert.True(expanding.Generation > shrinking.Generation);
        m.Update(T(15.2), new(AnimationCompleted: true, AnimationGeneration: shrinking.Generation));
        Assert.Equal(ToolbarIdleState.Expanding, m.State);
        m.Update(T(15.6), new(AnimationCompleted: true, AnimationGeneration: expanding.Generation));
        Assert.Equal(ToolbarIdleState.Expanded, m.State);
    }
    [Theory]
    [InlineData(699, 200)] [InlineData(700, 260)]
    public void TopDockUsesVisibleHeightThreshold(double screenHeight, double dockHeight)
    {
        var result = DockLayout.Arrange(Screen(height: screenHeight), DockEdge.Top, [new(NoteId.New(), 0)]);
        Assert.Equal(dockHeight, Assert.Single(result.Visible).Bounds.Height);
    }
    [Fact]
    public void LocalPreferencesPersistAnchorsPagesAndAccessibilityWithoutDerivedProperties()
    {
        using var dir = new TestDirectory(); var store = new LocalPreferencesStore(new Log(), dir.DirectoryPath);
        store.Save(new() { Anchor = new(null, ScreenEdge.Bottom, .7), DeskCollapsed = true, KeepToolbarExpanded = true,
            Pages = System.Collections.Immutable.ImmutableDictionary<string, int>.Empty.Add("note-id", 2), Page = 2 });
        var loaded = store.Load();
        Assert.Equal(ScreenEdge.Bottom, Assert.IsType<ToolbarAnchor>(loaded.Anchor).Edge); Assert.Equal(.7, loaded.Anchor!.Ratio);
        Assert.True(loaded.DeskCollapsed); Assert.True(loaded.KeepToolbarExpanded); Assert.Equal(2, loaded.Page);
        Assert.Equal(2, loaded.Pages["note-id"]);
        string json = File.ReadAllText(Path.Combine(dir.DirectoryPath, "LocalPreferences.json"));
        Assert.DoesNotContain("isValid", json); Assert.DoesNotContain("isDefault", json);
        store.Save(loaded with { Anchor = new(new(-300, 200)) });
        Assert.Equal(new PointD(-300, 200), store.Load().Anchor!.Center);
    }
    [Theory]
    [InlineData(332)]
    [InlineData(638)]
    public void ImpossibleToolbarAvoidanceFallsBackToFirstColumnWithoutEmptyPages(double width)
    {
        var screen = Screen(width: width, height: 600);
        var result = Arranger.Arrange(new([screen]), [Note(0, 500), Note(1, 500)], (_, _) => 500,
            screen.WorkArea, "a");
        Assert.Equal(2, result.Notes.Count);
        Assert.Equal(new RectD(22, 22, 288, 500), result.Notes[0].Bounds);
        Assert.Equal(new RectD(22, 22, 288, 500), result.Notes[1].Bounds);
        Assert.Equal(new[] { 0, 1 }, result.Notes.Select(n => n.Page));
        Assert.Equal(2, result.PageCounts["a"]);
    }
    [Fact]
    public void UnplacedAnchorUsesRuntimeHomeAndRoundTripsAsNull()
    {
        using var dir = new TestDirectory(); var store = new LocalPreferencesStore(new Log(), dir.DirectoryPath);
        store.Save(new());
        Assert.Null(store.Load().Anchor);
        var screen = Screen(x: -1000); var screens = new ScreenSet([screen]);
        var preferences = store.Load();
        Assert.Equal(ToolbarGeometry.Expand(ToolbarGeometry.Home(screens, screen, preferences.Home), screen.WorkArea,
            ToolbarOrientation.Horizontal, true), ToolbarGeometry.ResolveAnchor(screens, preferences, ToolbarOrientation.Horizontal, true));
    }
    [Fact]
    public void FreeAnchorRestoresCenterOnItsScreenAndClampsOfflineCoordinates()
    {
        var left = Screen(x: -1000, id: "left", primary: false); var main = Screen();
        var screens = new ScreenSet([left, main]);
        Assert.Equal(new RectD(-532, 238, 64, 324), ToolbarGeometry.ResolveAnchor(screens,
            new() { Anchor = new(new(-500, 400)) }, ToolbarOrientation.Vertical, true));
        Assert.Equal(new RectD(8, 8, 364, 64), ToolbarGeometry.ResolveAnchor(screens,
            new() { Anchor = new(new(-4000, -4000)) }, ToolbarOrientation.Horizontal, false));
    }
    [Theory]
    [InlineData(ScreenEdge.Left, 0, 8, 468)]
    [InlineData(ScreenEdge.Right, 1, 928, 8)]
    [InlineData(ScreenEdge.Top, 0, 8, 8)]
    [InlineData(ScreenEdge.Bottom, 1, 928, 468)]
    public void SnappedAnchorUsesFullFrameSpan(ScreenEdge edge, double ratio, double x, double y)
    {
        Assert.Equal(new RectD(x, y, 64, 324), ToolbarGeometry.ResolveAnchor(new([Screen()]),
            new() { Anchor = new(null, edge, ratio) }, ToolbarOrientation.Vertical, true));
    }
    [Fact]
    public void PreferenceReadIoFailureReturnsDefaultsAndSaveFailureCleansTemporaryFile()
    {
        using var dir = new TestDirectory(); var log = new Log();
        string path = Path.Combine(dir.DirectoryPath, "LocalPreferences.json");
        Directory.CreateDirectory(path);
        var store = new LocalPreferencesStore(log, dir.DirectoryPath);
        Assert.Equal(new LocalPreferences(), store.Load());
        Assert.Equal(1, log.Errors);
        Assert.ThrowsAny<IOException>(() => store.Save(new()));
        Assert.Empty(Directory.GetFiles(dir.DirectoryPath, "*.tmp"));
        Assert.True(Directory.Exists(path));
    }
    [Theory]
    [InlineData(AutoShrink.Off, 0)]
    [InlineData(AutoShrink.Seconds10, 10)]
    [InlineData(AutoShrink.Seconds15, 15)]
    [InlineData(AutoShrink.Seconds30, 30)]
    public void AutoShrinkUsesStableNumericIdentifiers(AutoShrink value, int identifier)
    {
        using var dir = new TestDirectory(); var store = new LocalPreferencesStore(new Log(), dir.DirectoryPath);
        store.Save(new() { AutoShrink = value, Orientation = ToolbarOrientation.Horizontal,
            Appearance = Appearance.Dark, Font = NoteFont.Wenkai, TextSize = NoteTextSize.ExtraLarge });
        using var document = System.Text.Json.JsonDocument.Parse(File.ReadAllText(Path.Combine(dir.DirectoryPath, "LocalPreferences.json")));
        Assert.Equal(identifier, document.RootElement.GetProperty("toolbar.autoShrink").GetInt32());
        var loaded = store.Load();
        Assert.Equal(value, loaded.AutoShrink); Assert.Equal(ToolbarOrientation.Horizontal, loaded.Orientation);
        Assert.Equal(Appearance.Dark, loaded.Appearance); Assert.Equal(NoteFont.Wenkai, loaded.Font);
        Assert.Equal(NoteTextSize.ExtraLarge, loaded.TextSize);
    }
    private sealed class Log : IDeskNodesLog
    {
        public int Errors { get; private set; }
        public void Info(string message) { }
        public void Warn(string message) { }
        public void Error(string message, Exception exception) => Errors++;
    }
}
