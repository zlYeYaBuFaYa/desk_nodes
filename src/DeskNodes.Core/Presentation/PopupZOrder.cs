namespace DeskNodes.Core.Presentation;

public readonly record struct ZBandWindow(long Id, bool Topmost);

public static class PopupZOrder
{
    public static long? InsertAfter(IReadOnlyList<ZBandWindow> topToBottom, long popup, long owner)
    {
        int ownerIndex = -1;
        for (int i = 0; i < topToBottom.Count; i++)
            if (topToBottom[i].Id == owner) { ownerIndex = i; break; }
        if (ownerIndex < 0) return null;
        for (int i = ownerIndex - 1; i >= 0; i--)
        {
            var window = topToBottom[i];
            if (window.Topmost) return null;
            if (window.Id != popup) return window.Id;
        }
        return null;
    }
}
