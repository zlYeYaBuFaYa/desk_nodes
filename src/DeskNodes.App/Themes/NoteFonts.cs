using System.IO;
using System.Windows;
using System.Windows.Media;
using DeskNodes.Core.Presentation;
namespace DeskNodes.App.Themes;
internal interface INoteFontAvailability { bool IsAvailable(string family); }
internal sealed class NoteFonts : INoteFontAvailability
{
    private readonly Dictionary<string, FontFamily> families = Fonts.SystemFontFamilies
        .GroupBy(f => f.Source, StringComparer.OrdinalIgnoreCase)
        .ToDictionary(g => g.Key, g => g.First(), StringComparer.OrdinalIgnoreCase);
    private static readonly Uri ApplicationUri = new("pack://application:,,,/");
    private readonly FontFamily? wenkai = FindWenkai();
    private static FontFamily? FindWenkai()
    {
        try
        {
            return Fonts.GetFontFamilies(ApplicationUri, "./Resources/Fonts/")
                .FirstOrDefault(f => f.FamilyNames.Values.Any(n => n.Contains("LXGW WenKai", StringComparison.OrdinalIgnoreCase)));
        }
        catch (IOException) { return null; }
    }
    public bool IsAvailable(string family) => family == "LXGW WenKai" ? wenkai is not null : families.ContainsKey(family);
    public NoteFontMapping Resolve(NoteFont font)
    {
        var mapping = NoteFontRules.Resolve(font, IsAvailable);
        if (font == NoteFont.Wenkai && mapping.Available && wenkai is not null)
            return mapping with { Family = "pack://application:,,,/DeskNodes.App;component/Resources/Fonts/#LXGW WenKai", TitleWeight = wenkai.GetTypefaces().Any(t => t.Weight == FontWeights.Medium) ? "Medium" : "Normal" };
        return mapping;
    }
}
