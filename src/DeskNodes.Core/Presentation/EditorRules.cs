namespace DeskNodes.Core.Presentation;

public static class EditorRules
{
    public static bool CanDeleteEmptyRow(string text, bool composing) => !composing && text.Length == 0;
    public static bool CanMoveBetweenItems(bool composing, int selectionLength, int visualLine, int lineCount, bool up)
        => !composing && selectionLength == 0 && visualLine >= 0 && lineCount > 0 && (up ? visualLine == 0 : visualLine == lineCount - 1);
}
