import AppKit
import DeskNodesCore

/// AppKit owns the input context, selection, undo, and marked range throughout editing.
/// N1 never replaces the text storage in response to a text-change notification.
final class NoteTextView: NSTextView {
    var hasUncommittedComposition: Bool { hasMarkedText() }

    override func doCommand(by selector: Selector) {
        guard CompositionPolicy.allowsStructuralCommand(hasMarkedText: hasMarkedText()) else {
            super.doCommand(by: selector)
            return
        }
        // N3 will route Return/empty Backspace to item actions here. Until then,
        // these remain ordinary native text commands, including newline and undo.
        super.doCommand(by: selector)
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
        setAccessibilityLabel("事项（临时编辑，不保存）")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}
