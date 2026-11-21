using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using DeskNodes.Core.Domain;
using DeskNodes.Core.Services;
using DeskNodes.Core.Presentation;

namespace DeskNodes.App.Views;

internal sealed partial class NoteWindow
{
    private ItemRowView CreateRow(NoteItem item)
    {
        var row = new ItemRowView();
        var editor = row.Editor;
        var check = row.Check;
        var strike = row.Strike;
        var delete = row.Delete;
        var sort = row.Sort;
        editor.Text = item.Text;
        editor.ContextMenu = CreateEditorMenu(editor);
        app.Editors.Register(editor, "item:" + item.Id, text => app.Actions.EditText(item.Id, text));
        editor.TextChanged += (_, _) => Dispatcher.BeginInvoke(MeasureHeight, DispatcherPriority.Background);
        editor.PreviewKeyDown += (_, e) => ItemKeys(item.Id, editor, e);
        DataObject.AddPastingHandler(editor, (_, e) => Paste(item.Id, editor, e));
        check.Click += (_, _) =>
        {
            app.Run(() =>
            {
                app.Actions.ToggleCompleted(item.Id);
                app.Refresh();
            });
            row.State.Completed = app.Repository.GetItem(item.Id)?.Completed ?? false;
            row.State.Refresh();
        };
        strike.Click += (_, _) =>
        {
            try
            {
                app.Run(() =>
                {
                    app.Actions.ToggleStruck(item.Id);
                    app.Refresh();
                });
                var current = app.Repository.GetItem(item.Id);
                row.State.Completed = current?.Completed ?? false;
                row.State.Struck = current?.Struck ?? false;
            }
            finally
            {
                // OneWay 绑定也会被点击临时切换；包括组词拒绝在内都须回显真实状态。
                row.State.Refresh();
            }
        };
        delete.Click += (_, _) => app.Run(() => DeleteRow(item.Id));
        Point? dragStart = null;
        sort.PreviewMouseLeftButtonDown += (_, e) => dragStart = e.GetPosition(sort);
        sort.PreviewMouseMove += (_, e) =>
        {
            if (dragStart is not
                {
                }
 start || e.LeftButton != MouseButtonState.Pressed || app.Editors.HasComposition) return;
            var point = e.GetPosition(sort);
            if (Math.Abs(point.X - start.X) < SystemParameters.MinimumHorizontalDragDistance && Math.Abs(point.Y - start.Y) < SystemParameters.MinimumVerticalDragDistance) return;
            dragStart = null;
            if (app.Editors.TryCommitPending() == CommitResult.Committed)
                DragDrop.DoDragDrop(sort, new DataObject("DeskNodes.Item." + note.Id, item.Id), DragDropEffects.Move);
        };
        row.DragOver += (_, e) =>
        {
            e.Effects = e.Data.GetDataPresent("DeskNodes.Item." + note.Id) ? DragDropEffects.Move : DragDropEffects.None;
            e.Handled = true;
        };
        row.Drop += (_, e) =>
        {
            if (e.Data.GetData("DeskNodes.Item." + note.Id) is not ItemId moved) return;
            app.Run(() =>
            {
                int target = app.Repository.GetItems(note.Id).ToList().FindIndex(i => i.Id == item.Id);
                if (target >= 0)
                {
                    app.Actions.MoveItem(note.Id, moved, target);
                    app.Refresh();
                }
            });
            e.Handled = true;
        };
        sort.Click += (_, _) =>
        {
            var menu = new ContextMenu();
            var items = app.Repository.GetItems(note.Id);
            int index = items.ToList().FindIndex(i => i.Id == item.Id);
            var up = new MenuItem
            {
                Header = "上移",
                IsEnabled = index > 0
            };
            up.Click += (_, _) => app.Run(() =>
            {
                app.Actions.MoveItem(note.Id, item.Id, index - 1);
                app.Refresh();
            });
            var down = new MenuItem
            {
                Header = "下移",
                IsEnabled = index < items.Count - 1
            };
            down.Click += (_, _) => app.Run(() =>
            {
                app.Actions.MoveItem(note.Id, item.Id, index + 1);
                app.Refresh();
            });
            TrackMenu(menu);
            menu.Items.Add(up);
            menu.Items.Add(down);
            menu.PlacementTarget = sort;
            menu.IsOpen = true;
        };
        return row;
    }

    private void AddItem()
    {
        var items = app.Repository.GetItems(note.Id);
        if (items.Count == 0)
        {
            app.Actions.CleanupBlankItems(note.Id);
            app.Refresh();
            FocusItem(app.Repository.GetItems(note.Id)[0].Id);
            return;
        }
        var id = app.Actions.InsertAfter(note.Id, items[^1].Id);
        app.Refresh();
        FocusItem(id);
    }

    private void DeleteRow(ItemId id)
    {
        var items = app.Repository.GetItems(note.Id);
        int index = items.ToList().FindIndex(i => i.Id == id);
        app.DeleteItem(id);
        if (items.Count == 1)
        {
            app.Actions.CleanupBlankItems(note.Id);
            app.Undo.AssociateBlankPlaceholder(id, app.Repository.GetItems(note.Id).Single().Id);
            app.Refresh();
        }
        var remaining = app.Repository.GetItems(note.Id);
        if (remaining.Count > 0) FocusItem(remaining[Math.Max(0, index - 1)].Id);
    }

    public void FocusItem(ItemId id)
    {
        if (itemRows.TryGetValue(id, out var row))
        {
            row.Editor.Focus();
            row.Editor.BringIntoView();
        }
    }

    private void WindowKeys(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.ImeProcessed || app.Editors.HasComposition) return;
        if (openMenus == 0) app.Presentation.Keys(e);
        if (e.Handled || (Keyboard.Modifiers & ModifierKeys.Control) == 0) return;
        switch (e.Key)
        {
            case Key.OemComma:
                app.OpenSettings();
                e.Handled = true;
                break;
            case Key.N:
                app.Run(app.CreateNote);
                break;
            case Key.OemPlus:
            case Key.Add:
                app.ChangeSize(1);
                break;
            case Key.OemMinus:
            case Key.Subtract:
                app.ChangeSize(-1);
                break;
            case Key.D0:
            case Key.NumPad0:
                app.ChangeSize(0, true);
                break;
            case Key.Z:
                if (app.Undo.DecideUndo(app.Clock.UtcNow, app.NewInputSinceDeletion) != UndoDecision.StructuralUndo) return;
                app.Run(() =>
                {
                    app.Undo.Undo(app.Clock.UtcNow);
                    app.Refresh();
                });
                break;
            default: return;
        }
        e.Handled = true;
    }

    private void ItemKeys(ItemId id, TextBox editor, KeyEventArgs e)
    {
        WindowKeys(editor, e);
        if (e.Handled || e.Key == Key.ImeProcessed || app.Editors.HasComposition) return;
        bool control = (Keyboard.Modifiers & ModifierKeys.Control) != 0;
        if (e.Key == Key.Return)
        {
            app.Run(() =>
            {
                if (control)
                {
                    app.Actions.ToggleCompleted(id);
                    app.Refresh();
                }
                else
                {
                    var next = app.Actions.InsertAfter(note.Id, id);
                    app.Refresh();
                    FocusItem(next);
                }
            });
        }
        else if (control && Keyboard.Modifiers.HasFlag(ModifierKeys.Shift) && e.Key == Key.X) app.Run(() =>
        {
            app.Actions.ToggleStruck(id);
            app.Refresh();
        });
        else if (e.Key == Key.Back && EditorRules.CanDeleteEmptyRow(editor.Text, app.Editors.HasComposition)) app.Run(() => DeleteRow(id));
        else if (Keyboard.Modifiers == ModifierKeys.None && e.Key is Key.Up or Key.Down && editor.SelectionLength == 0)
        {
            int line = editor.GetLineIndexFromCharacterIndex(editor.CaretIndex);
            if (!EditorRules.CanMoveBetweenItems(app.Editors.HasComposition, editor.SelectionLength, line, editor.LineCount, e.Key == Key.Up)) return;
            var items = app.Repository.GetItems(note.Id);
            int index = items.ToList().FindIndex(i => i.Id == id) + (e.Key == Key.Up ? -1 : 1);
            if (index < 0 || index >= items.Count) return;
            FocusItem(items[index].Id);
        }
        else return;
        e.Handled = true;
    }

    private void Paste(ItemId id, TextBox editor, DataObjectPastingEventArgs e)
    {
        if (!e.DataObject.GetDataPresent(DataFormats.UnicodeText)) return;
        var result = PasteParser.Parse((string)e.DataObject.GetData(DataFormats.UnicodeText));
        if (result.KeepNativePaste) return;
        e.CancelCommand();
        if (app.Editors.TryCommitPending() != CommitResult.Committed || result.FirstLine is null) return;
        app.Run(() =>
        {
            editor.BeginChange();
            try
            {
                editor.SelectedText = result.FirstLine;
            }
            finally
            {
                editor.EndChange();
            }
            if (app.Editors.TryCommitPending() != CommitResult.Committed) return;
            var added = app.Actions.InsertFollowing(note.Id, id, result.FollowingLines);
            app.Refresh();
            if (added.Count > 0) FocusItem(added[^1]);
        });
    }
}
