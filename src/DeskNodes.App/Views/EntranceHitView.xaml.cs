using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
namespace DeskNodes.App.Views;
internal partial class EntranceHitView : UserControl
{
    public static readonly DependencyProperty HitGeometryProperty = DependencyProperty.Register(nameof(HitGeometry), typeof(Geometry), typeof(EntranceHitView));
    public Geometry HitGeometry
    {
        get => (Geometry)GetValue(HitGeometryProperty);
        set => SetValue(HitGeometryProperty, value);
    }
    public EntranceHitView() => InitializeComponent();
}
