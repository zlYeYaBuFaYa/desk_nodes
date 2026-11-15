using DeskNodes.Core.Domain;

namespace DeskNodes.Core.Presentation;

[Flags]
public enum SuppressionReason
{
    None = 0, Collapsed = 1, ArrangementPage = 2, DockOverflow = 4, OtherDesktop = 8
}
public enum DeskTransition { Expanded, Collapsing, Collapsed, Expanding }
public sealed class PresentationState
{
    public long Generation { get; private set; }
    public DeskTransition Transition { get; private set; }
    public long Request(bool collapsed)
    {
        Transition = collapsed ? DeskTransition.Collapsing : DeskTransition.Expanding;
        return ++Generation;
    }
    public bool Complete(long generation)
    {
        if (generation != Generation) return false;
        Transition = Transition switch
        {
            DeskTransition.Collapsing => DeskTransition.Collapsed,
            DeskTransition.Expanding => DeskTransition.Expanded,
            _ => Transition
        };
        return true;
    }
}
public static class PresentationRules
{
    public static SuppressionReason Suppressed(bool collapsed, int? page, int currentPage, int lastPage,
        bool dockOverflow, bool currentDesktop) =>
        (collapsed ? SuppressionReason.Collapsed : 0) |
        (page is { } p && p != Math.Min(currentPage, lastPage) ? SuppressionReason.ArrangementPage : 0) |
        (dockOverflow ? SuppressionReason.DockOverflow : 0) |
        (!currentDesktop ? SuppressionReason.OtherDesktop : 0);
    public static bool EndsRaise(bool toggle, bool escape, bool collapsed, bool empty,
        bool appDeactivated, bool foregroundOwned, bool composing) =>
        toggle || escape || collapsed || empty || appDeactivated && !foregroundOwned && !composing;
    public static RectD Prompt(RectD work, double width, double height, double bottom) =>
        new RectD(work.Center.X - width / 2, work.Bottom - bottom - height, width, height).Fit(work);
    public static RectD DeletionPrompt(RectD work, bool selecting) => Prompt(work, 296, 46, selecting ? 92 : 28);
}
public sealed class NoteSelection
{
    private readonly HashSet<NoteId> picked = [];
    public IReadOnlySet<NoteId> Picked => picked;
    public bool CanDelete => picked.Count > 0;
    public void Toggle(NoteId id)
    {
        if (!picked.Remove(id)) picked.Add(id);
    }
    public void Apply(IEnumerable<NoteId> ids, bool append = false)
    {
        if (!append) picked.Clear();
        picked.UnionWith(ids);
    }
    public void Retain(IEnumerable<NoteId> visible) => picked.IntersectWith(visible);
    public static IEnumerable<NoteId> Intersect(RectD pixelBox, IEnumerable<(NoteId Id, RectD PixelBounds)> notes) =>
        notes.Where(n => pixelBox.Width > 0 && pixelBox.Height > 0 && n.PixelBounds.Width > 0 && n.PixelBounds.Height > 0 && pixelBox.Intersects(n.PixelBounds)).Select(n => n.Id);
}
