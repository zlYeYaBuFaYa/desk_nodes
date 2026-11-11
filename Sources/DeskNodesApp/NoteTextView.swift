import AppKit
import DeskNodesCore
import DeskNodesActions

/// AppKit owns the input context, selection, undo, and marked range throughout editing.
/// Persistence observes edits without replacing text storage. Structural commands alone create/remove rows.
final class NoteTextView: NSTextView {
    private let textUndo = UndoManager()
    override var undoManager: UndoManager? { textUndo }
    var hasUncommittedComposition: Bool { hasMarkedText() }

    var addRow: (() -> Void)?
    var deleteEmptyRow: (() -> Void)?
    var deletionUndo: (() -> Bool)?
    /// Arrow keys on the first/last visual line move to the neighbouring row.
    var moveToRow: ((_ offset: Int) -> Void)?
    var toggleCompletion: (() -> Void)?
    /// Receives the 2nd...nth pasted lines; the first line is inserted natively (undoable).
    var pasteLines: (([String]) -> Void)?
    // keyDown sees the marked range BEFORE the input context consumes Return.
    private var acceptingComposition = false
    override func keyDown(with event: NSEvent) {
        acceptingComposition = hasMarkedText()
        defer { acceptingComposition = false }
        super.keyDown(with: event)
    }
    override func doCommand(by selector: Selector) {
        let command = EditingPolicy.command(returnKey: selector == #selector(insertNewline(_:)),
            backspace: selector == #selector(deleteBackward(_:)),
            marked: acceptingComposition || hasMarkedText(), empty: string.isEmpty)
        switch command {
        case .addRow: if let addRow { addRow(); return }
        case .deleteRow: if let deleteEmptyRow { deleteEmptyRow(); return }
        case .native: break
        }
        if let moveToRow, !acceptingComposition, !hasMarkedText(), selectedRange().length == 0 {
            if selector == #selector(moveUp(_:)), caretOnEdgeLine(first: true) { moveToRow(-1); return }
            if selector == #selector(moveDown(_:)), caretOnEdgeLine(first: false) { moveToRow(1); return }
        }
        super.doCommand(by: selector)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "z", !hasMarkedText(), deletionUndo?() == true { return true }
        // Key equivalents visit every view in the window; only the focused row toggles.
        if flags == .command, event.charactersIgnoringModifiers == "\r", window?.firstResponder === self,
           !hasMarkedText(), let toggleCompletion { toggleCompletion(); return true }
        return super.performKeyEquivalent(with: event)
    }
    override func paste(_ sender: Any?) {
        guard let pasteLines, !hasMarkedText(),
              let text = NSPasteboard.general.string(forType: .string) else { super.paste(sender); return }
        let lines = Self.listLines(text)
        guard lines.count > 1 else { super.paste(sender); return }
        insertText(lines[0], replacementRange: selectedRange())
        pasteLines(Array(lines.dropFirst()))
    }
    /// Non-empty lines with common list markers ("- ", "* ", "• ", "- [ ] ", "1. ") removed.
    static func listLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).compactMap { line in
            var value = line.trimmingCharacters(in: .whitespaces)
            for marker in ["- [ ] ", "- [x] ", "- [X] ", "- ", "* ", "• "] where value.hasPrefix(marker) {
                value.removeFirst(marker.count); break
            }
            if let dot = value.firstIndex(of: "."), value[..<dot].allSatisfy(\.isNumber), !value[..<dot].isEmpty,
               value[value.index(after: dot)...].hasPrefix(" ") {
                value = String(value[value.index(dot, offsetBy: 2)...])
            }
            value = value.trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
    }
    private func caretOnEdgeLine(first: Bool) -> Bool {
        let text = string as NSString
        guard text.length > 0, let manager = layoutManager, let container = textContainer else { return true }
        manager.ensureLayout(for: container)
        let location = selectedRange().location
        // A caret after a trailing newline sits on the extra (last) line fragment.
        if location >= text.length, text.character(at: text.length - 1) == 10 { return !first }
        let caret = manager.lineFragmentRect(forGlyphAt: manager.glyphIndexForCharacter(at: min(location, text.length - 1)), effectiveRange: nil)
        let edge = manager.lineFragmentRect(forGlyphAt: first ? 0 : max(0, manager.numberOfGlyphs - 1), effectiveRange: nil)
        return caret.minY == edge.minY
    }

    init(text: String) {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        string = text
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        drawsBackground = false
        font = .systemFont(ofSize: NoteMetrics.itemSize)
        textColor = NoteTheme.primary
        insertionPointColor = NoteTheme.primary
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        isHorizontallyResizable = false
        isVerticallyResizable = true
        autoresizingMask = [.width]
        minSize = NSSize(width: 0, height: 26)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = NoteMetrics.rowHeight
        paragraph.maximumLineHeight = NoteMetrics.rowHeight
        defaultParagraphStyle = paragraph
        typingAttributes = [.font: font!, .foregroundColor: NoteTheme.primary, .paragraphStyle: paragraph]
        setAccessibilityLabel("事项")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

/// Each title owns a field editor and undo history; switching windows/notes never
/// transfers the shared system field editor's previous note undo into this title.
final class NoteTitleField: NSTextField {
    let ownedEditor = NoteTextView(text: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        ownedEditor.isFieldEditor = true
    }
    required init?(coder: NSCoder) { fatalError() }
}
