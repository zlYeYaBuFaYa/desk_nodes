using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using DeskNodes.App.Platform;
using DeskNodes.Core.Domain;

namespace DeskNodes.App.Views;

internal sealed partial class NoteWindow
{
    private void TrackMenu(ContextMenu menu)
    {
        // A popup temporarily owns focus; keep the original editing row alive until it closes.
        menu.Opened += (_, _) => openMenus++;
        menu.Closed += (_, _) => openMenus--;
    }

    private void OpenMenu(bool atPointer = false)
    {
        var menu = new ContextMenu
        {
            PlacementTarget = more,
            Placement = atPointer ? PlacementMode.MousePoint : PlacementMode.Bottom
        };
        PopulateNoteMenu(menu);
        TrackMenu(menu);
        menu.IsOpen = true;
    }

    private void PopulateNoteMenu(ItemsControl menu)
    {
        void Command(ItemsControl parent, string name, Action action, bool? check = null)
        {
            var item = new MenuItem
            {
                Header = name,
                IsCheckable = check.HasValue,
                IsChecked = check ?? false
            };
            item.Click += (_, _) => app.Run(action);
            parent.Items.Add(item);
        }
        var colors = new MenuItem
        {
            Header = "颜色"
        };
        menu.Items.Add(colors);
        string[] names = ["宣纸", "柠黄", "杏", "樱", "薰衣草", "雾蓝", "薄荷"];
        foreach (var color in Enum.GetValues<NoteColor>()) Command(colors, names[(int)color], () => app.Update(Current(), color: color), note.Color == color);
        var levelsMenu = new MenuItem
        {
            Header = "层级"
        };
        menu.Items.Add(levelsMenu);
        Command(levelsMenu, "靠后（桌面近似）", () => app.Update(Current(), level: NoteLevel.Back), note.SavedLevel == NoteLevel.Back);
        Command(levelsMenu, "普通", () => app.Update(Current(), level: NoteLevel.Normal), note.SavedLevel == NoteLevel.Normal);
        Command(levelsMenu, "置顶", () => app.Update(Current(), level: NoteLevel.Topmost), note.SavedLevel == NoteLevel.Topmost);
        menu.Items.Add(new Separator());
        foreach (var edge in Enum.GetValues<DockEdge>()) Command(menu, "停靠到" + (edge == DockEdge.Top ? "顶" : edge == DockEdge.Left ? "左" : "右"), () =>
        {
            var current = Current();
            var screen = app.Screens.GetScreens().Resolve(ScreenProvider.DeviceForWindow(new WindowInteropHelper(this).Handle));
            app.Update(current, placement: new(current.Placement.Bounds, screen.DeviceHint, edge, app.Repository.GetNotes().Count), free: current.FreeRestore ?? current.Placement.Bounds);
            foreach (Window window in Application.Current.Windows) if (window is NoteWindow n) n.Place();
        }, note.Placement.DockEdge == edge);
        if (note.Placement.DockEdge is not null) Command(menu, "取消停靠", () =>
        {
            var current = Current();
            app.Update(current, placement: new(current.FreeRestore ?? current.Placement.Bounds, current.Placement.DisplayDeviceHint), clearFree: true);
            Place();
        });
        Command(menu, note.Collapsed ? "展开" : "折叠", () =>
        {
            app.Update(Current(), collapsed: !note.Collapsed);
            Place();
        });
        Command(menu, "随内容", () => app.Update(Current(), automatic: true), note.AutomaticHeight);
        Command(menu, "添加事项", AddItem);
        menu.Items.Add(new Separator());
        Command(menu, "删除", () => app.DeleteNote(note.Id));
    }

    private ContextMenu CreateEditorMenu(TextBox editor)
    {
        var menu = new ContextMenu();
        (string Name, RoutedUICommand Command)[] commands =
        [
            ("撤销", ApplicationCommands.Undo),
            ("剪切", ApplicationCommands.Cut),
            ("复制", ApplicationCommands.Copy),
            ("粘贴", ApplicationCommands.Paste),
            ("全选", ApplicationCommands.SelectAll)
        ];
        foreach (var (name, command) in commands)
            menu.Items.Add(new MenuItem
            {
                Header = name,
                Command = command,
                CommandTarget = editor
            });
        menu.Items.Add(new Separator());
        var noteMenu = new MenuItem
        {
            Header = "便签"
        };
        menu.Items.Add(noteMenu);
        menu.Opened += (_, _) =>
        {
            noteMenu.Items.Clear();
            PopulateNoteMenu(noteMenu);
        };
        TrackMenu(menu);
        return menu;
    }

    private void OpenContextMenu(object sender, ContextMenuEventArgs e)
    {
        if (FindEditor(e.OriginalSource as DependencyObject) is not null) return;
        e.Handled = true;
        OpenMenu(e.CursorLeft >= 0);
    }

    private void ContextMenuKeys(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Apps && !(e.Key == Key.F10 && Keyboard.Modifiers == ModifierKeys.Shift)) return;
        if (Keyboard.FocusedElement is TextBox editor && editor.ContextMenu is { } menu)
        {
            menu.PlacementTarget = editor;
            menu.Placement = PlacementMode.Bottom;
            menu.IsOpen = true;
        }
        else OpenMenu();
        e.Handled = true;
    }

    private static TextBox? FindEditor(DependencyObject? source)
    {
        while (source is not null)
        {
            if (source is TextBox editor) return editor;
            source = source is Visual ? VisualTreeHelper.GetParent(source) : LogicalTreeHelper.GetParent(source);
        }
        return null;
    }
}
