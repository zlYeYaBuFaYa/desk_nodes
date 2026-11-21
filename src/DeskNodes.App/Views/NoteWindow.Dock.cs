using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using DeskNodes.App.Interop;
using DeskNodes.Core.Domain;
using DeskNodes.Core.Presentation;

namespace DeskNodes.App.Views;
internal sealed partial class NoteWindow
{
    private PointD? dockDrag;
    private void BeginDockDrag(MouseButtonEventArgs e)
    {
        if (app.Editors.TryCommitPending() != Core.Services.CommitResult.Committed) return;
        NativeMethods.GetCursorPos(out var p);
        dockDrag = new(p.X, p.Y);
        CaptureMouse();
        MouseMove += DockMove;
        MouseLeftButtonUp += DockRelease;
        LostMouseCapture += DockLostCapture;
        e.Handled = true;
    }
    private void DockMove(object sender, MouseEventArgs e)
    {
        if (dockDrag is null || note.Placement.DockEdge is not { } edge) return;
        NativeMethods.GetCursorPos(out var p);
        var screen = app.Screens.GetScreens().Resolve(note.Placement.DisplayDeviceHint);
        var pointer = new PointD(p.X / screen.DpiScale, p.Y / screen.DpiScale);
        if (DockLayout.ShouldDetach(edge, screen.WorkArea, pointer))
        {
            EndDockDrag();
            app.Run(() => app.Update(Current(), placement: new(note.FreeRestore ?? note.Placement.Bounds, screen.DeviceHint), clearFree: true));
            return;
        }
        // Preview the insertion slot using physical pointer ownership and per-screen DIP.
        var peers = app.Repository.GetNotes().Where(n => n.Placement.DockEdge == edge && n.Placement.DisplayDeviceHint == note.Placement.DisplayDeviceHint).OrderBy(n => n.Placement.DockOrder).ToList();
        int index = peers.FindIndex(n => n.Id == note.Id);
        var visible = app.Presentation.Dock(screen, edge).Visible;
        var target = visible.FirstOrDefault(n => edge == DockEdge.Top ? pointer.X < n.Bounds.Center.X : pointer.Y < n.Bounds.Center.Y);
        if (target?.Id == note.Id || visible.Count == 0) return;
        int destination = DockLayout.PeerIndex(peers.Select(n => n.Id).ToArray(), visible.Select(n => n.Id).ToArray(), target?.Id);
        if (destination == index) return;
        var bounds = target?.Bounds ?? visible.Last().Bounds;
        Left = bounds.X;
        Top = bounds.Y;
        dockDropOrder = destination;
        e.Handled = true;
    }
    private int? dockDropOrder;
    private void DockRelease(object sender, MouseButtonEventArgs e)
    {
        int? order = dockDropOrder;
        EndDockDrag();
        if (order is not { } destination) return;
        app.Run(() =>
        {
            var peers = app.Repository.GetNotes().Where(n => n.Placement.DockEdge == note.Placement.DockEdge && n.Placement.DisplayDeviceHint == note.Placement.DisplayDeviceHint).OrderBy(n => n.Placement.DockOrder).ToList();
            peers.RemoveAll(n => n.Id == note.Id);
            peers.Insert(Math.Min(destination, peers.Count), Current());
            app.ReorderDock(peers);
        });
        e.Handled = true;
    }
    private void DockLostCapture(object sender, MouseEventArgs e) => EndDockDrag();
    private void EndDockDrag()
    {
        dockDrag = null;
        dockDropOrder = null;
        MouseMove -= DockMove;
        MouseLeftButtonUp -= DockRelease;
        LostMouseCapture -= DockLostCapture;
        ReleaseMouseCapture();
        Place();
    }
}
