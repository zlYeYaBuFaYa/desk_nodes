using DeskNodes.Core.Services;

namespace DeskNodes.Core.Presentation;

public static class EditorRules
{
    public static bool UsesStructuralUndo(bool composing, UndoDecision decision)
        => !composing && decision == UndoDecision.StructuralUndo;

    public static bool IsCtrlZ(bool control, bool shift, bool alt, bool windows)
        => control && !shift && !alt && !windows;

    public static bool ConsumeCtrlZ(bool control, bool shift, bool alt, bool windows, bool composing, UndoDecision decision, CommitResult commit)
        => IsCtrlZ(control, shift, alt, windows)
            && UsesStructuralUndo(composing, decision)
            && commit == CommitResult.Committed;

    public static bool CanDeleteEmptyRow(string text, bool composing) => !composing && text.Length == 0;
    public static bool CanMoveBetweenItems(bool composing, int selectionLength, int visualLine, int lineCount, bool up)
        => !composing && selectionLength == 0 && visualLine >= 0 && lineCount > 0 && (up ? visualLine == 0 : visualLine == lineCount - 1);
}
