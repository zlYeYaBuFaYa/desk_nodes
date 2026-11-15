using System.Runtime.InteropServices;

namespace DeskNodes.App.Platform;

internal sealed class VirtualDesktop : IDisposable
{
    private IManager? manager;
    public VirtualDesktop()
    {
        try
        {
            manager = (IManager?)Activator.CreateInstance(Type.GetTypeFromCLSID(new("AA509086-5CA9-4C25-8F95-589D3C07B48A"), true)!);
        }
        catch (COMException) { }
    }
    public bool IsCurrent(nint window)
    {
        try { return manager is null || manager.IsWindowOnCurrentVirtualDesktop(window, out bool current) < 0 || current; }
        catch (COMException) { return true; }
    }
    public void Dispose()
    {
        if (manager is not null) Marshal.FinalReleaseComObject(manager);
        manager = null;
    }
    [ComImport, Guid("A5CD92FF-29BE-454C-8D04-D82879FB3F1B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IManager
    {
        [PreserveSig] int IsWindowOnCurrentVirtualDesktop(nint window, [MarshalAs(UnmanagedType.Bool)] out bool current);
        [PreserveSig] int GetWindowDesktopId(nint window, out Guid desktop);
        [PreserveSig] int MoveWindowToDesktop(nint window, in Guid desktop);
    }
}
