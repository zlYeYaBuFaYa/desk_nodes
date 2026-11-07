import AppKit
import QuartzCore
import DeskNodesCore
import DeskNodesPersistence
import DeskNodesActions

final class NotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var deletionUndo: (() -> Bool)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "z", deletionUndo?() == true { return true }
        return super.performKeyEquivalent(with: event)
    }
    init(origin: NSPoint) {
        super.init(contentRect: NSRect(origin: origin, size: NSSize(width: 240, height: 260)),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        title = "便签"
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        isFloatingPanel = false; hidesOnDeactivate = false; isReleasedWhenClosed = false
        level = .normal // N4 owns level/geometry behavior.
    }
    func showNote() {
        orderFrontRegardless()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = contentView?.layer else { return }
        let spring = CASpringAnimation(keyPath: "transform.translation.y")
        spring.fromValue = -8; spring.toValue = 0
        spring.mass = 1; spring.stiffness = 300; spring.damping = 27; spring.duration = 0.30
        layer.add(spring, forKey: "noteInsertion")
    }
}

final class NoteCardView: NSView, NSTextFieldDelegate {
    let id: NoteID
    private let actions: NoteActions
    private let changed: () -> Void
    private let failure: (Error) -> Void
    private let undoDelete: () -> Bool
    private let titleEditor = NSTextField()
    private let count = NSTextField(labelWithString: "")
    private let list = FlippedList()
    private var orderedRows: [ItemRow] = []
    private let scroll = NSScrollView()
    private var rows: [ItemID: ItemRow] = [:]
    private var palette: NotePalette = .paper
    override var isFlipped: Bool { true }
    init(note: Note, actions: NoteActions, changed: @escaping () -> Void,
         undoDelete: @escaping () -> Bool, failure: @escaping (Error) -> Void) {
        id = note.id; self.actions = actions; self.changed = changed
        self.undoDelete = undoDelete; self.failure = failure
        super.init(frame: .zero)
        wantsLayer = true; layer?.cornerRadius = 12; layer?.borderWidth = 1
        titleEditor.stringValue = note.title ?? ""
        titleEditor.placeholderString = "标题（可选）"
        titleEditor.isBordered = false; titleEditor.drawsBackground = false
        titleEditor.font = .systemFont(ofSize: 13, weight: .semibold)
        titleEditor.textColor = NoteTheme.primary; titleEditor.delegate = self
        count.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        count.textColor = NoteTheme.secondary
        let delete = NSButton(title: "删除便签", target: self, action: #selector(deleteNote))
        delete.isBordered = false; delete.font = .systemFont(ofSize: 11)
        delete.frame = NSRect(x: 155, y: 225, width: 74, height: 24)
        let add = NSButton(title: "＋ 添加事项", target: self, action: #selector(addItem))
        add.isBordered = false; add.font = .systemFont(ofSize: 12)
        add.frame = NSRect(x: 10, y: 225, width: 100, height: 24)
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        scroll.documentView = list
        [titleEditor, count, scroll, add, delete].forEach { addSubview($0) }
        refresh(note)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        titleEditor.frame = NSRect(x: 12, y: 12, width: 155, height: 22)
        count.frame = NSRect(x: 173, y: 14, width: 55, height: 18)
        scroll.frame = NSRect(x: 14, y: 42, width: bounds.width - 28, height: 176)
        list.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width,
                            height: max(176, CGFloat(rows.count) * 26))
        for (index, row) in orderedRows.enumerated() {
            row.frame = NSRect(x: 0, y: CGFloat(index) * 26, width: scroll.contentSize.width, height: 26)
        }
    }
    func refresh(_ note: Note) {
        palette = note.color
        do {
            let items = try actions.store.items(in: id)
            let ids = Set(items.map(\.id))
            for key in Array(rows.keys) where !ids.contains(key) {
                rows[key]?.removeFromSuperview(); rows.removeValue(forKey: key)
            }
            orderedRows = []
            for item in items {
                if rows[item.id] == nil {
                    let row = ItemRow(item: item, owner: self)
                    rows[item.id] = row
                    list.addSubview(row)
                }
                let row = rows[item.id]!
                orderedRows.append(row)
                row.setCompleted(item.completed)
            }
            count.stringValue = "\(items.filter(\.completed).count) / \(items.count)"
            needsLayout = true; colors()
        } catch { failure(error) }
    }
    func run(_ body: () throws -> Void) { do { try body(); changed() } catch { failure(error) } }
    func save(_ item: ItemID, text: String) { // No reload while typing/composing.
        do { try actions.text(item, in: id, text) } catch { failure(error) }
    }
    func toggle(_ item: ItemID) { run { try actions.toggle(item, in: id) } }
    func delete(_ item: ItemID) {
        let previous = orderedRows.firstIndex(where: { $0.item.id == item }) ?? 0
        run { try actions.deleteItem(item, in: id) }
        if !orderedRows.isEmpty {
            window?.makeFirstResponder(orderedRows[min(previous, orderedRows.count - 1)].editor)
        }
    }
    func add(after item: ItemID? = nil) {
        var created: Item?
        run { created = try actions.add(in: id, after: item) }
        if let created, let editor = rows[created.id]?.editor { window?.makeFirstResponder(editor) }
    }
    func move(_ item: ItemID, before target: ItemID) {
        run {
            var ids = try actions.store.items(in: id).map(\.id)
            guard item != target, ids.contains(item), ids.contains(target) else { return }
            ids.removeAll { $0 == item }; ids.insert(item, at: ids.firstIndex(of: target)!)
            try actions.reorder(id, ids: ids)
        }
    }
    func undo() -> Bool { undoDelete() }
    func controlTextDidChange(_ notification: Notification) {
        do { try actions.title(id, titleEditor.stringValue) } catch { failure(error) }
    }
    @objc private func addItem() { add() }
    @objc private func deleteNote() { run { try actions.deleteNote(id) } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); colors() }
    private func colors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer?.backgroundColor = NoteTheme.background(palette).cgColor
            layer?.borderColor = NoteTheme.border.cgColor; CATransaction.commit()
        }
    }
}

private final class FlippedList: NSView { override var isFlipped: Bool { true } }

private final class ItemRow: NSView, NSTextViewDelegate, NSDraggingSource {
    let item: Item
    weak var owner: NoteCardView?
    let editor: NoteTextView
    private let check = CompletionButton(done: false)
    private let textScroll = NSScrollView()
    private let remove = NSButton(title: "×", target: nil, action: nil)
    private let handle = NSTextField(labelWithString: "⠿")
    private static let type = NSPasteboard.PasteboardType("local.desknodes.native.item")
    init(item: Item, owner: NoteCardView) {
        self.item = item; self.owner = owner; editor = NoteTextView(text: item.text)
        super.init(frame: .zero)
        check.target = self; check.action = #selector(toggle)
        remove.target = self; remove.action = #selector(deleteItem); remove.isBordered = false
        remove.toolTip = "删除事项"; handle.textColor = NoteTheme.secondary
        textScroll.drawsBackground = false
        textScroll.documentView = editor
        [check, textScroll, remove, handle].forEach { addSubview($0) }
        editor.delegate = self
        editor.addRow = { [weak self] in guard let self else { return }; self.owner?.add(after: self.item.id) }
        editor.deleteEmptyRow = { [weak self] in guard let self else { return }; self.owner?.delete(self.item.id) }
        editor.deletionUndo = { [weak owner] in owner?.undo() ?? false }
        registerForDraggedTypes([Self.type])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        handle.frame = NSRect(x: 0, y: 5, width: 10, height: 18)
        check.frame = NSRect(x: 12, y: 4, width: 18, height: 18)
        textScroll.frame = NSRect(x: 35, y: 0, width: bounds.width - 55, height: 26)
        editor.frame.size = NSSize(width: textScroll.contentSize.width, height: max(26, editor.frame.height))
        remove.frame = NSRect(x: bounds.width - 19, y: 3, width: 19, height: 20)
    }
    func setCompleted(_ completed: Bool) {
        check.state = completed ? .on : .off
        check.needsDisplay = true
        check.setAccessibilityLabel(completed ? "取消完成" : "标记完成")
        // Layout-manager temporary ink leaves text storage, selection and text undo untouched.
        guard let manager = editor.layoutManager else { return }
        let range = NSRange(location: 0, length: (editor.string as NSString).length)
        manager.removeTemporaryAttribute(.strikethroughStyle, forCharacterRange: range)
        manager.addTemporaryAttribute(.foregroundColor, value: completed ? NoteTheme.completed : NoteTheme.primary, forCharacterRange: range)
        if completed { manager.addTemporaryAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, forCharacterRange: range) }
    }
    func textDidChange(_ notification: Notification) { owner?.save(item.id, text: editor.string); setCompleted(check.state == .on) }
    @objc private func toggle() { owner?.toggle(item.id) }
    @objc private func deleteItem() { owner?.delete(item.id) }
    override func mouseDown(with event: NSEvent) {
        guard convert(event.locationInWindow, from: nil).x < 12 else { super.mouseDown(with: event); return }
        let pasteboard = NSPasteboardItem()
        pasteboard.setString(item.id.rawValue.uuidString, forType: Self.type)
        let drag = NSDraggingItem(pasteboardWriter: pasteboard)
        let image = NSImage(size: bounds.size)
        if let bitmap = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: bitmap); image.addRepresentation(bitmap)
        }
        drag.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [drag], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let owner, let source = sender.draggingSource as? ItemRow, source.owner === owner else { return [] }
        return .move
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let owner, let source = sender.draggingSource as? ItemRow, source.owner === owner else { return false }
        owner.move(source.item.id, before: item.id); return true
    }
}

private final class CompletionButton: NSButton {
    init(done: Bool) {
        super.init(frame: .zero)
        title = ""; isBordered = false; setButtonType(.toggle)
        state = done ? .on : .off
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5))
        if state == .on {
            NoteTheme.primary.withAlphaComponent(0.72).setFill(); circle.fill()
            NoteTheme.background(.paper).setStroke()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 4, y: 9)); path.line(to: NSPoint(x: 7, y: 6))
            path.line(to: NSPoint(x: 13, y: 12))
            path.lineWidth = 1.6; path.lineCapStyle = .round; path.stroke()
        } else {
            NoteTheme.primary.withAlphaComponent(0.42).setStroke()
            circle.lineWidth = 1.5; circle.stroke()
        }
    }
}
