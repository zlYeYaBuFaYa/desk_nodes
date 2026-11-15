using System.Windows;

namespace DeskNodes.App;

public partial class App : Application
{
    private readonly AppCoordinator coordinator = new();

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        try
        {
            coordinator.Start();
            // W1 verifies the store and exits; a later step will add the toolbar lifetime.
            Shutdown(0);
        }
        catch (Exception exception)
        {
            MessageBox.Show($"DeskNodes 无法打开本地数据库。请保留数据目录，不要删除原文件。\n\n" +
                $"数据目录：{coordinator.DataDirectoryPath ?? "解析失败"}\n\n{exception}\n\n" +
                "按 Ctrl+C 可复制此对话框的完整内容。",
                "DeskNodes 启动失败", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(1);
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        coordinator.Stop();
        base.OnExit(e);
    }
}
