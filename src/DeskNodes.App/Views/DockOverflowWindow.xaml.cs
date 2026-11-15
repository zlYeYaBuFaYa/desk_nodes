using System.Windows;
using System.Windows.Controls;
using DeskNodes.Core.Domain;

namespace DeskNodes.App.Views;
internal sealed record DockOverflowEntry(NoteId Id, string Title);
internal sealed record DockOverflowModel(string PageText, IReadOnlyList<DockOverflowEntry> Entries);
internal partial class DockOverflowWindow : Window
{
    private readonly Action<int> change;
    private readonly Action<NoteId> reveal;
    public DockOverflowWindow(Action<int> change, Action<NoteId> reveal)
    {
        InitializeComponent();
        this.change = change;
        this.reveal = reveal;
    }
    private void Previous(object sender, RoutedEventArgs e) => change(-1);
    private void Next(object sender, RoutedEventArgs e) => change(1);
    private void Reveal(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: NoteId id }) reveal(id);
    }
}
