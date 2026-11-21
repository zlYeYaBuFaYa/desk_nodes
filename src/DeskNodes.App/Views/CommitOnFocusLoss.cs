using System.Windows;
using System.Windows.Input;

namespace DeskNodes.App.Views;

public static class CommitOnFocusLoss
{
    public static readonly DependencyProperty CommandProperty = DependencyProperty.RegisterAttached(
        "Command", typeof(ICommand), typeof(CommitOnFocusLoss), new PropertyMetadata(null, CommandChanged));
    public static ICommand? GetCommand(DependencyObject target) => (ICommand?)target.GetValue(CommandProperty);
    public static void SetCommand(DependencyObject target, ICommand? value) => target.SetValue(CommandProperty, value);
    private static void CommandChanged(DependencyObject target, DependencyPropertyChangedEventArgs e)
    {
        if (target is not UIElement element)
            return;
        element.LostKeyboardFocus -= Commit;
        if (e.NewValue is ICommand)
            element.LostKeyboardFocus += Commit;
    }
    private static void Commit(object sender, KeyboardFocusChangedEventArgs e)
    {
        if (GetCommand((DependencyObject)sender) is { } command && command.CanExecute(null))
            command.Execute(null);
    }
}
