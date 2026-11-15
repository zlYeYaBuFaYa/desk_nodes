using System.Diagnostics;
using System.IO;
using System.Windows;
using DeskNodes.App.Platform;

namespace DeskNodes.App.Views;

internal partial class LicenseWindow : Window
{
    public string LicenseText { get; }
    private LicenseWindow(string text, Window owner, AppCoordinator app)
    {
        LicenseText = text;
        InitializeComponent();
        Owner = owner;
        DataContext = this;
        SourceInitialized += (_, _) => AuxiliaryWindowPlacement.Position(this, app.Screens, 680, 520);
    }
    internal static void Open(Window owner, AppCoordinator app)
    {
        System.Windows.Resources.StreamResourceInfo? resource;
        try
        {
            resource = Application.GetResourceStream(new Uri("pack://application:,,,/Resources/Fonts/OFL.txt"));
        }
        catch (IOException)
        {
            resource = null;
        }
        if (resource is null)
        {
            Process.Start(new ProcessStartInfo("https://github.com/lxgw/LxgwWenKai/blob/v1.530/OFL.txt") { UseShellExecute = true });
            return;
        }
        using var reader = new StreamReader(resource.Stream);
        new LicenseWindow(reader.ReadToEnd(), owner, app).Show();
    }
}
