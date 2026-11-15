using System.Windows;
using System.ComponentModel;

namespace DeskNodes.App;

public partial class App : System.Windows.Application
{
    private readonly AppCoordinator coordinator = new();
    private Platform.SingleInstance? instance;

    private ResourceDictionary? highContrast;

    private void UpdatePalette()
    {
        if (highContrast is not null)
            Resources.MergedDictionaries.Remove(highContrast);
        highContrast = SystemParameters.HighContrast
            ? new ResourceDictionary { Source = new Uri("Themes/HighContrast.xaml", UriKind.Relative) }
            : null;
        if (highContrast is not null)
            Resources.MergedDictionaries.Add(highContrast);
    }

    private void SystemParametersChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(SystemParameters.HighContrast))
            Dispatcher.BeginInvoke(UpdatePalette);
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        UpdatePalette();
        SystemParameters.StaticPropertyChanged += SystemParametersChanged;
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
            coordinator.Start();
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
        SystemParameters.StaticPropertyChanged -= SystemParametersChanged;
        coordinator.Stop();
        instance?.Dispose();
        base.OnExit(e);
    }
}
