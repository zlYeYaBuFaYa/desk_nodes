using System.Globalization;
using System.Windows;
using System.Windows.Controls;
namespace DeskNodes.App.Views;
internal sealed record StackHintViewModel(string? First, string? Second, string? Third, Visibility FirstVisible,
    Visibility SecondVisible, Visibility ThirdVisible, string Count);
internal partial class StackHintView : UserControl
{
    public StackHintView() => InitializeComponent();
    public void Update(string[] colors, int count)
    {
        string? Color(int index) => index < colors.Length ? colors[index] : null;
        Visibility Visible(int index) => index < colors.Length ? Visibility.Visible : Visibility.Collapsed;
        DataContext = new StackHintViewModel(Color(0), Color(1), Color(2), Visible(0), Visible(1), Visible(2), count.ToString(CultureInfo.InvariantCulture));
    }
}
