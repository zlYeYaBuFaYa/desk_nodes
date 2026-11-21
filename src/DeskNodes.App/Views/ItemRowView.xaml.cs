using System.Windows.Controls;

namespace DeskNodes.App.Views;

internal partial class ItemRowView : UserControl
{
    internal ItemViewModel State { get; } = new();
    public ItemRowView()
    {
        InitializeComponent();
        DataContext = State;
    }
}
