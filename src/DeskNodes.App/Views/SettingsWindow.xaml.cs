using System.Windows;
using DeskNodes.App.Platform;

namespace DeskNodes.App.Views;

internal partial class SettingsWindow : Window
{
    public SettingsWindow(AppCoordinator app)
    {
        InitializeComponent();
        var model = new SettingsViewModel(app, () => LicenseWindow.Open(this, app), Dispatcher);
        DataContext = model;
        SourceInitialized += (_, _) => AuxiliaryWindowPlacement.Position(this, app.Screens, 760, 576);
        PreviewKeyDown += (_, e) =>
        {
            model.CaptureKey(e);
            AuxiliaryWindowShortcuts.TryCreateNote(app, e);
        };
        Deactivated += (_, _) => model.CancelRecording();
        Closed += (_, _) =>
        {
            model.CancelRecording();
            model.Dispose();
        };
    }
}
