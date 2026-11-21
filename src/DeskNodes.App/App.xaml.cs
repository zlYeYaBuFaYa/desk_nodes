using System.Windows;

namespace DeskNodes.App;

public partial class App : System.Windows.Application
{
    private readonly AppCoordinator coordinator = new();
    private Platform.SingleInstance? instance;

    internal Platform.TextScaleService TextScale { get; private set; } = null!;
    internal Themes.ThemeService Theme { get; private set; } = null!;
    internal void RefreshAppearance() => Theme.Refresh();

    protected override void OnStartup(StartupEventArgs e)
    {
        DispatcherUnhandledException += (_, args) =>
        {
            args.Handled = true;
            coordinator.Log?.Error("界面发生未处理异常，即将退出。", args.Exception);
            MessageBox.Show("DeskNodes 遇到错误，即将退出。请重新启动；已保存的数据会保留。", "DeskNodes", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(1);
        };
        base.OnStartup(e);
        Theme = new(() => coordinator.Preferences.Appearance, Dispatcher, Resources);
        try
        {
            instance = new(Core.Storage.DataDirectory.Resolve());
            if (!instance.IsFirst)
            {
                try
                {
                    instance.SignalAsync().GetAwaiter().GetResult();
                }
                catch (Exception exception) when (exception is System.IO.IOException or TimeoutException or OperationCanceledException or UnauthorizedAccessException)
                {
                    MessageBox.Show("DeskNodes 已在运行，但无法唤起工具条（可从托盘打开）。", "DeskNodes", MessageBoxButton.OK, MessageBoxImage.Information);
                }
                Shutdown();
                return;
            }
            TextScale = new(Dispatcher, Resources);
            TextScale.Changed += (_, _) => coordinator.RefreshTextScale();
            coordinator.Start();
            coordinator.PreferencesChanged += (_, _) => Theme.Refresh();
            Theme.Refresh();
            _ = instance.ListenAsync(() => Dispatcher.BeginInvoke(coordinator.ShowToolbar),
                error => coordinator.Log.Error("单实例恢复入口通信失败。", error));
        }
        catch (Exception exception)
        {
            System.Windows.MessageBox.Show($"DeskNodes 无法打开本地数据库。请保留数据目录，不要删除原文件。\n\n" +
                $"数据目录：{coordinator.DataDirectoryPath ?? "解析失败"}\n\n{exception}\n\n" +
                "按 Ctrl+C 可复制此对话框的完整内容。",
                "DeskNodes 启动失败", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(1);
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        TextScale?.Dispose();
        Theme?.Dispose();
        coordinator.Stop();
        instance?.Dispose();
        base.OnExit(e);
    }
}
