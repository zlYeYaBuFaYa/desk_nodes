using System.Windows.Input;

namespace DeskNodes.App.Views;

internal static class AuxiliaryWindowShortcuts
{
    internal static void TryCreateNote(AppCoordinator app, KeyEventArgs e)
    {
        if (e.Handled || e.Key != Key.N ||
            Keyboard.Modifiers != ModifierKeys.Control)
            return;
        e.Handled = true;
        app.Run(app.CreateNote);
    }
}
