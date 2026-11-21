using System.Windows;
using DeskNodes.App.Platform;

namespace DeskNodes.App.Views;

internal partial class LoginPromptWindow : Window
{
    private readonly AppCoordinator app;
    private bool answered;
    public LoginPromptWindow(AppCoordinator app)
    {
        this.app = app;
        InitializeComponent();
        SourceInitialized += (_, _) => AuxiliaryWindowPlacement.Position(this, app.Screens, 400, 190);
        Closing += (_, _) =>
        {
            if (!answered)
            {
                try
                {
                    app.AnswerLogin(false);
                    answered = true;
                }
                catch (Exception exception)
                {
                    app.Log.Error("保存登录启动选择失败。", exception);
                    app.RecordError("无法保存登录启动选择，请在设置中重试。");
                }
            }
        };
    }
    private void Decline(object sender, RoutedEventArgs e) => Answer(false);
    private void Enable(object sender, RoutedEventArgs e) => Answer(true);
    private void Answer(bool enabled)
    {
        try
        {
            app.AnswerLogin(enabled);
            answered = true;
            if (IsVisible)
                Close();
        }
        catch (Exception exception)
        {
            app.Log.Error("保存登录启动选择失败。", exception);
            app.RecordError("无法保存登录启动选择，请在设置中重试。");
        }
    }
}
