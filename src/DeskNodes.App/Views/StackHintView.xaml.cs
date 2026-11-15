using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
namespace DeskNodes.App.Views;
internal sealed record StackHintViewModel(Brush? First, Brush? Second, Brush? Third, Visibility FirstVisible,
    Visibility SecondVisible, Visibility ThirdVisible, string Count);
internal partial class StackHintView : UserControl
{
    public StackHintView() => InitializeComponent();
    public void Update(string[] colors, int count)
    {
        Brush? Color(int index) => index < colors.Length ? (Brush)FindResource(colors[index]) : null;
        Visibility Visible(int index) => index < colors.Length ? Visibility.Visible : Visibility.Collapsed;
        DataContext = new StackHintViewModel(Color(0), Color(1), Color(2), Visible(0), Visible(1), Visible(2), count.ToString(CultureInfo.InvariantCulture));
    }
}
