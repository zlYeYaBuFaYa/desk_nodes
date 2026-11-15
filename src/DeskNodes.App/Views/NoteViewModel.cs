using System.ComponentModel;
using System.Windows;
using System.Windows.Media;
using DeskNodes.Core.Presentation;
using DeskNodes.Core.Domain;

namespace DeskNodes.App.Views;

// Editing buffers remain owned by EditorCoordinator; these properties only describe presentation.
internal sealed class NoteViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    public bool Collapsed { get; set; }
    public string Count { get; set; } = "";
    public string Summary { get; set; } = "";
    public FontFamily Font { get; set; } = new(NoteFontRules.DefaultFamily);
    public FontWeight TitleWeight { get; set; } = FontWeights.SemiBold;
    public NoteTypography Typography { get; set; } = NoteTypography.For(NoteTextSize.Standard);
    public double TitleSize => Typography.Title;
    public double SecondarySize => Typography.Secondary;
    public double AddSize => Typography.Secondary + 1;
    public GridLength HeaderHeight => new(Collapsed ? 32 : Typography.Scale(50));
    public GridLength FooterHeight => new(Collapsed ? 0 : Typography.Scale(44));
    public Thickness HeadingMargin => new(0, Collapsed ? 0 : 13, 10, 0);
    public Thickness CountMargin => new(0, Collapsed ? 0 : 10, 0, 0);
    public CornerRadius Radius => new(Collapsed ? 10 : 13);
    public NoteColor Color { get; set; }
    public bool Selected { get; set; }
    public bool Picked { get; set; }
    public double SelectionOpacity { get; set; } = 1;
    public void Refresh() => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(null));
}

internal sealed class ItemViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    public bool Completed { get; set; }
    public bool Struck { get; set; }
    public FontFamily Font { get; set; } = new(NoteFontRules.DefaultFamily);
    public NoteTypography Typography { get; set; } = NoteTypography.For(NoteTextSize.Standard);
    public double BodySize => Typography.Body;
    public double RowHeight => Typography.Scale(32);
    public double LineHeight => Typography.Scale(22);
    public double CircleSize => Typography.Scale(16);
    public Thickness EditorPadding => new(0, Typography.Scale(5), 0, Typography.Scale(5));
    public Thickness CircleMargin => new(0, Typography.Scale(8), Typography.Scale(11), 0);
    public string CompletionName => Completed ? "取消完成事项" : "完成事项";
    public void Refresh() => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(null));
}
