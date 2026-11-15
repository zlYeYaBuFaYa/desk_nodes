using System.Windows;
using System.Windows.Controls;
using DeskNodes.Core.Presentation;
using DeskNodes.Core.Domain;
using DeskNodes.Core.Services;
using Forms = System.Windows.Forms;

namespace DeskNodes.App.Views;

internal sealed class AppMenus(AppCoordinator app)
{
    internal sealed record HistoryEntry(string Label, int Completed, int Total, bool Available, HistoryDay? Day = null);
    private IReadOnlyList<HistoryEntry> History()
    {
        try
        {
            var days = app.History.RecentSealedDays();
            if (days.Count == 0) return [new("暂无历史记录", 0, 0, false)];
            return days.Select(day => new HistoryEntry(HistoryQueries.RelativeLabel(day.Day, app.BusinessDays.Current), day.Progress.Completed, day.Progress.Total, true, day.Day)).ToArray();
        }
        catch (Exception ex)
        {
            app.Log.Error("无法读取历史记录。", ex);
            return [new("无法读取历史记录", 0, 0, false)];
        }
    }
    private MenuItem HistoryMenu()
    {
        var menu = new MenuItem { Header = "历史记录" };
        foreach (var entry in History())
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal };
            row.Children.Add(new TextBlock { Text = entry.Label, Width = 88 });
            if (entry.Available)
            {
                row.Children.Add(new ProgressBar { Width = 28, Height = 4, Maximum = Math.Max(1, entry.Total), Value = entry.Completed, VerticalAlignment = VerticalAlignment.Center });
                row.Children.Add(new TextBlock { Text = $"  {entry.Completed}/{entry.Total}", FontFamily = new System.Windows.Media.FontFamily("Consolas") });
            }
            var item = Command(entry.Label, () => app.OpenHistory(entry.Day), enabled: entry.Available);
            item.Header = row;
            menu.Items.Add(item);
        }
        menu.Items.Add(new Separator());
        menu.Items.Add(Command("打开日历…", () => app.OpenHistory()));
        var deleted = DeletedCount();
        menu.Items.Add(Command(deleted.Label, () => app.OpenHistory(deleted: true), enabled: deleted.Enabled));
        return menu;
    }
    private (string Label, bool Enabled) DeletedCount()
    {
        try
        {
            int count = app.Deleted.Count();
            return ($"最近删除（{count}）", count > 0);
        }
        catch (Exception ex)
        {
            app.Log.Error("无法读取最近删除计数。", ex);
            return ("最近删除", true);
        }
    }
    private MenuItem Command(string text, Action action, bool check = false, bool enabled = true)
    {
        var item = new MenuItem { Header = text, IsCheckable = check, IsChecked = check, IsEnabled = enabled };
        item.Click += (_, _) => app.Run(() =>
        {
            app.Presentation.ExitSelection();
            action();
        });
        return item;
    }
    public ContextMenu ToolbarMenu()
    {
        var menu = new ContextMenu();
        menu.Items.Add(HistoryMenu());
        var toolbar = new MenuItem { Header = "工具条" };
        var orientation = new MenuItem { Header = "排列方向" };
        foreach (var value in Enum.GetValues<ToolbarOrientation>())
            orientation.Items.Add(Command(value == ToolbarOrientation.Vertical ? "竖向" : "横向", () => app.SavePreferences(app.Preferences with { Orientation = value }), app.Preferences.Orientation == value));
        toolbar.Items.Add(orientation);
        var shrink = new MenuItem { Header = "闲置自动收缩" };
        foreach (var value in Enum.GetValues<AutoShrink>())
            shrink.Items.Add(Command(value == AutoShrink.Off ? "关闭" : $"{(int)value} 秒", () => app.SavePreferences(app.Preferences with { AutoShrink = value }), app.Preferences.AutoShrink == value));
        toolbar.Items.Add(shrink);
        toolbar.Items.Add(Command("恢复默认收缩位置", () => app.SavePreferences(app.Preferences with { Home = new() }), enabled: !app.Preferences.Home.IsDefault));
        menu.Items.Add(Command("选择便签…", () => app.Presentation.EnterSelection(), enabled: app.NoteCount > 0));
        menu.Items.Add(toolbar);
        menu.Items.Add(new Separator());
        menu.Items.Add(Command("退出 DeskNodes", app.Exit));
        return menu;
    }
    public void PopulateTray(Forms.ContextMenuStrip menu)
    {
        menu.Items.Clear();
        void Add(string text, Action action, bool enabled = true)
        {
            var item = menu.Items.Add(text, null, (_, _) => app.Run(() =>
            {
                app.Presentation.ExitSelection();
                action();
            }));
            item.Enabled = enabled;
        }
        Add("显示工具条", app.ShowToolbar);
        Add("新建便签", app.CreateNote);
        Add("选择便签…", () => app.Presentation.EnterSelection(), app.NoteCount > 0);
        Add(app.Raised ? "放回" : "浮起", app.ToggleRaised, app.NoteCount > 0);
        var history = new Forms.ToolStripMenuItem("历史记录");
        foreach (var entry in History())
        {
            if (!entry.Available)
            {
                history.DropDownItems.Add(new Forms.ToolStripMenuItem(entry.Label) { Enabled = false });
                continue;
            }
            var row = new Forms.Panel { Size = new System.Drawing.Size(210, 26), AccessibleName = $"{entry.Label} {entry.Completed}/{entry.Total}" };
            row.Controls.Add(new Forms.Label { Text = entry.Label, AutoSize = true, Location = new System.Drawing.Point(4, 5) });
            row.Controls.Add(new Forms.Label { Text = $"{entry.Completed}/{entry.Total}", AutoSize = true, Location = new System.Drawing.Point(150, 5) });
            row.Paint += (_, e) =>
            {
                using var track = new System.Drawing.SolidBrush(System.Drawing.SystemColors.ControlDark);
                using var fill = new System.Drawing.SolidBrush(System.Drawing.SystemColors.Highlight);
                e.Graphics.FillRectangle(track, 110, 11, 28, 4);
                if (entry.Total > 0) e.Graphics.FillRectangle(fill, 110, 11, 28f * entry.Completed / entry.Total, 4);
            };
            var host = new Forms.ToolStripControlHost(row) { AutoSize = false, Size = row.Size };
            void OpenDate(object? sender, EventArgs args)
            {
                menu.Close();
                app.Run(() => app.OpenHistory(entry.Day));
            }
            host.Click += OpenDate;
            row.Click += OpenDate;
            foreach (Forms.Control child in row.Controls) child.Click += OpenDate;
            history.DropDownItems.Add(host);
        }
        history.DropDownItems.Add(new Forms.ToolStripSeparator());
        history.DropDownItems.Add("打开日历…", null, (_, _) => app.Run(() => app.OpenHistory()));
        var deleted = DeletedCount();
        var deletedItem = history.DropDownItems.Add(deleted.Label, null, (_, _) => app.Run(() => app.OpenHistory(deleted: true)));
        deletedItem.Enabled = deleted.Enabled;
        menu.Items.Add(history);
        menu.Items.Add(new Forms.ToolStripSeparator());
        Add("退出 DeskNodes", app.Exit);
    }
}
