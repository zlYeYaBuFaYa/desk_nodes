using DeskNodes.App.Interop;
using DeskNodes.Core.Domain;
namespace DeskNodes.App.Platform;
internal sealed class WindowLevelService(nint handle)
{
    public NoteLevel SavedLevel { get; set; }
    public bool TemporarilyRaised { get; set; }
    public void Apply(bool returnBoundary = false)
    {
        var level = TemporarilyRaised ? NoteLevel.Topmost : SavedLevel;
        nint after = level == NoteLevel.Topmost ? NativeMethods.Topmost : NativeMethods.NotTopmost;
        NativeMethods.SetWindowPos(handle, after, 0, 0, 0, 0, NativeMethods.NoActivate | NativeMethods.NoMove | NativeMethods.NoSize | NativeMethods.NoOwnerZOrder);
        if (level == NoteLevel.Back && returnBoundary)
            NativeMethods.SetWindowPos(handle, NativeMethods.Bottom, 0, 0, 0, 0, NativeMethods.NoActivate | NativeMethods.NoMove | NativeMethods.NoSize | NativeMethods.NoOwnerZOrder);
    }
}
