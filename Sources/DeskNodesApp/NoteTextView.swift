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
        super.doCommand(by: selector)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "z", !hasMarkedText(), deletionUndo?() == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    init(text: String) {
        super.init(frame: .zero)
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
        maxSize = NSSize(width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
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
