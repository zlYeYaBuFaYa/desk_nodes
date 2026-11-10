import AppKit
import QuartzCore
import DeskNodesCore
import DeskNodesPersistence
import DeskNodesActions

final class NotePanel: NSPanel, NSWindowDelegate {
    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        (client as? NoteTitleField)?.ownedEditor
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var choice: WindowLevel = .desktop
    var modes = WindowModes()
    var temporarilyRaised = false
    var docked = false
    var dockingAction: ((DockEdge?) -> Void)?
    var dragBegin: (() -> Void)?
    var dragUpdate: ((NoteFrame, NSPoint) -> Void)?
    var dragCancel: (() -> Void)?
    var dragEnd: ((NoteFrame, NSPoint) -> Void)?
    var expandedFrame: NoteFrame?
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            if choice == .desktop { temporarilyRaised = true; applyLevel() }
            makeKeyAndOrderFront(nil)
        }
        super.sendEvent(event)
    }
    override func resignKey() {
        if let card = contentView as? NoteCardView, !card.hasMarkedComposition {
            card.flushBeforeFocusLoss(); card.pruneBlankRowsAfterFocusLoss()
        }
        super.resignKey(); temporarilyRaised = false; applyLevel()
    }
    var deletionUndo: (() -> Bool)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "z", deletionUndo?() == true { return true }
        return super.performKeyEquivalent(with: event)
    }
    init(origin: NSPoint) {
        super.init(contentRect: NSRect(origin: origin, size: NSSize(width: 240, height: 260)),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        delegate = self
        title = "便签"
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        isFloatingPanel = false; hidesOnDeactivate = false; isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenNone]
        applyLevel()
    }
    func dismissNote() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = contentView?.layer else { close(); return }
        ignoresMouseEvents = true
        let spring = CASpringAnimation(keyPath: "transform.translation.y")
        spring.fromValue = 0; spring.toValue = -8; spring.stiffness = 300; spring.damping = 27; spring.duration = 0.30
        spring.fillMode = .forwards; spring.isRemovedOnCompletion = false
        layer.add(spring, forKey: "noteDeletion")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1; fade.toValue = 0; fade.duration = 0.30
        fade.fillMode = .forwards; fade.isRemovedOnCompletion = false
        layer.add(fade, forKey: "noteDeletionFade")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { self.close() }
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
    private let titleEditor = NoteTitleField(frame: .zero)
    private let count = NSTextField(labelWithString: "")
    private let pinIndicator = NSImageView()
    private let addButton = NSButton(title: "＋ 添加事项", target: nil, action: nil)
    private let list = FlippedList()
    private var orderedRows: [ItemRow] = []
    private let scroll = NSScrollView()
    private var rows: [ItemID: ItemRow] = [:]
    private var note: Note
    private let reveal: Bool
    var canMutate: () -> Bool = { true }
    private var invalidated = false
    private var hovering = false
    private let tools = NSView()
    private let header = NoteGestureView()
    private let grip = NoteGestureView()
    private let collapsedLabel = NSTextField(labelWithString: "")
    private var activeMenu: NSMenu?
    private var tracking: NSTrackingArea?
    private var palette: NotePalette = .paper
    /// Typing is persisted after a short pause instead of on every keystroke; every
    /// flush point (focus loss, rollover, export, quit) commits the pending edits first.
    static let saveDelay: TimeInterval = 0.4
    private var pendingItems: Set<ItemID> = []
    private var pendingTitle = false
    private var saveWork: DispatchWorkItem?
    override var isFlipped: Bool { true }
    init(note: Note, actions: NoteActions, changed: @escaping () -> Void,
         undoDelete: @escaping () -> Bool, failure: @escaping (Error) -> Void, reveal: Bool = false) {
        self.note = note
        self.reveal = reveal
        id = note.id; self.actions = actions; self.changed = changed
        self.undoDelete = undoDelete; self.failure = failure
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "便签菜单") { [weak self] in
                guard let self, !self.invalidated else { return false }
                self.showMenu(); return true
            }
        ])
        wantsLayer = true; layer?.cornerRadius = 12; layer?.borderWidth = 1; layer?.masksToBounds = true
        titleEditor.stringValue = note.title ?? ""
        titleEditor.placeholderString = "标题（可选）"
        titleEditor.setAccessibilityLabel("便签标题（可选）")
        pinIndicator.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "已置顶")
        pinIndicator.contentTintColor = NoteTheme.secondary
        addButton.target = self; addButton.action = #selector(addItem)
        addButton.isBordered = false; addButton.alignment = .left
        addButton.font = .systemFont(ofSize: 12); addButton.contentTintColor = NoteTheme.secondary
        addButton.setAccessibilityLabel("添加事项")
        titleEditor.isBordered = false; titleEditor.drawsBackground = false
        titleEditor.font = .systemFont(ofSize: 13, weight: .semibold)
        titleEditor.textColor = NoteTheme.primary; titleEditor.delegate = self
        count.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        count.textColor = NoteTheme.secondary
        collapsedLabel.textColor = NoteTheme.primary
        collapsedLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        collapsedLabel.lineBreakMode = .byTruncatingTail
        for (index, entry) in [("circle", "更换颜色", #selector(showMenu)),
                               ("pin", "置顶", #selector(pin)),
                               ("chevron.up", "折叠 / 展开", #selector(collapse)),
                               ("ellipsis", "更多", #selector(showMenu))].enumerated() {
            let button = NSButton(image: NSImage(systemSymbolName: entry.0, accessibilityDescription: entry.1)!, target: self, action: entry.2)
            button.isBordered = false; button.contentTintColor = NoteTheme.secondary
            button.setAccessibilityLabel(entry.1)
            button.toolTip = entry.1; button.frame = NSRect(x: CGFloat(index * 24), y: 0, width: 24, height: 24)
            tools.addSubview(button)
        }
        grip.resize = true
        let finish: (NoteFrame, Bool) -> Void = { [weak self] frame, resize in
            guard let self else { return }
            self.run { try self.actions.finalGeometry(self.id, frame: frame, manuallyResized: resize) }
        }
        header.finish = finish; grip.finish = finish
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        scroll.documentView = list
        [header, titleEditor, collapsedLabel, count, scroll, tools, grip, pinIndicator, addButton].forEach { addSubview($0) }
        refresh(note)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 40)
        let compact = !reveal && note.collapsed
        titleEditor.isHidden = compact
        collapsedLabel.isHidden = !compact
        scroll.isHidden = compact
        tools.isHidden = !hovering; count.isHidden = hovering
        header.isHidden = reveal
        grip.isHidden = reveal || compact || !hovering || (window as? NotePanel)?.docked == true
        let pinned = note.level == .topmost
        pinIndicator.isHidden = !pinned || hovering
        pinIndicator.frame = NSRect(x: 14, y: compact ? 10 : 14, width: 12, height: 12)
        let titleX: CGFloat = pinned && !hovering ? 32 : 14
        let titleWidth = max(1, bounds.width - (hovering ? 110 : 68) - titleX)
        let footer = !reveal && !compact && isDocked
        addButton.isHidden = !footer
        addButton.frame = NSRect(x: 14, y: bounds.height - 36, width: bounds.width - 28, height: 22)
        titleEditor.frame = NSRect(x: titleX, y: 10, width: titleWidth, height: 22)
        collapsedLabel.frame = NSRect(x: titleX, y: 7, width: titleWidth, height: 20)
        count.frame = NSRect(x: bounds.width - 68, y: compact ? 9 : 14, width: 54, height: 18)
        tools.frame = NSRect(x: bounds.width - 108, y: compact ? 4 : 9, width: 96, height: 24)
        grip.frame = NSRect(x: bounds.width - 18, y: bounds.height - 18, width: 16, height: 16)
        scroll.frame = NSRect(x: 14, y: 42, width: max(1, bounds.width - 28), height: max(1, bounds.height - (footer ? 82 : 56)))
        var y: CGFloat = 0
        for row in orderedRows {
            let height = row.fittingHeight(width: scroll.contentSize.width)
            row.frame = NSRect(x: 0, y: y, width: scroll.contentSize.width, height: height)
            y += height
        }
        list.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width,
                            height: max(scroll.contentSize.height, y))
    }
    var firstEditor: NoteTextView? { orderedRows.first?.editor }
    private var isDocked: Bool { if case .dock = note.placement { return true }; return false }
    func preferredHeight(width: CGFloat) -> Double {
        Double((!reveal && isDocked ? 82 : 56) + orderedRows.reduce(CGFloat(0)) { $0 + $1.fittingHeight(width: width - 28) })
    }
    func refresh(_ note: Note) {
        guard !invalidated else { return }
        self.note = note
        let titleInput = titleEditor.currentEditor() as? NSTextView
        let titleActive = window?.isKeyWindow == true && titleInput != nil
        let localTitle = titleInput?.string ?? titleEditor.stringValue
        if EditorSynchronization.receive(local: localTitle, committed: note.title ?? "",
            active: titleActive, marked: titleInput?.hasMarkedText() == true) {
            titleEditor.ownedEditor.undoManager?.removeAllActions()
            titleEditor.stringValue = note.title ?? ""
            if let titleInput { titleInput.string = note.title ?? "" }
        }
        palette = note.color
        do {
            let items = try actions.store.items(in: id)
            let ids = Set(items.map(\.id))
            for key in Array(rows.keys) where !ids.contains(key) {
                if let row = rows[key] {
                    // A completed focused editor must relinquish focus before leaving the view tree.
                    if window?.firstResponder === row.editor { window?.makeFirstResponder(nil) }
                    row.editor.undoManager?.removeAllActions()
                    row.removeFromSuperview()
                }
                rows.removeValue(forKey: key)
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
                row.synchronize(item.text)
                row.setCompleted(item.completed)
            }
            collapsedLabel.stringValue = WindowModes.collapsedTitle(note.title, firstItem: items.first?.text)
            setAccessibilityLabel("便签：" + (collapsedLabel.stringValue.isEmpty ? "无标题" : collapsedLabel.stringValue))
            setAccessibilityValue("完成 \(items.filter(\.completed).count) / \(items.count)" + (note.collapsed && !reveal ? "，已折叠" : ""))
            layer?.cornerRadius = !reveal && note.collapsed ? 10 : 12
            count.stringValue = "\(items.filter(\.completed).count) / \(items.count)"
            if let pin = tools.subviews.dropFirst().first as? NSButton {
                pin.image = NSImage(systemSymbolName: note.level == .topmost ? "pin.fill" : "pin", accessibilityDescription: "置顶")
                pin.state = note.level == .topmost ? .on : .off
                pin.setAccessibilityLabel(note.level == .topmost ? "取消置顶" : "置顶")
            }
            if let collapse = tools.subviews.dropFirst(2).first as? NSButton {
                let label = note.collapsed ? (reveal ? "展开桌面便签" : "展开") : (reveal ? "折叠桌面便签" : "折叠")
                collapse.image = NSImage(systemSymbolName: note.collapsed ? "chevron.down" : "chevron.up", accessibilityDescription: label)
                collapse.setAccessibilityLabel(label); collapse.toolTip = label
            }
            if let color = tools.subviews.first as? NSButton { color.contentTintColor = NoteTheme.secondary }
            needsLayout = true; colors()
        } catch { failure(error) }
    }
    var hasMarkedComposition: Bool {
        // The owned title field editor lives outside this card's subtree.
        if let editor = window?.firstResponder as? NSTextView, editor.hasMarkedText() { return true }
        func marked(_ view: NSView) -> Bool {
            if let editor = view as? NSTextView, editor.hasMarkedText() { return true }
            return view.subviews.contains { marked($0) }
        }
        return marked(self)
    }
    /// Called only after the application has checked every editor for marked text.
    /// No refresh callbacks inside the rollover transaction.
    func flushRolloverEdits() throws {
        guard !invalidated else { return }
        try commitPendingSaves(notify: false)
        // Passive views are never authoritative. Only the live first responder can
        // contribute an unnotified committed edit, inside the rollover transaction.
        if window?.isKeyWindow == true, let editor = titleEditor.currentEditor() as? NSTextView,
           !editor.hasMarkedText(),
           let current = try actions.store.notes().first(where: { $0.id == id }),
           (current.title ?? "") != editor.string {
            var updated = current; updated.title = editor.string.isEmpty ? nil : editor.string
            try actions.store.update(updated)
        }
        for row in orderedRows where window?.isKeyWindow == true && window?.firstResponder === row.editor {
            guard !row.editor.hasMarkedText(),
                  let item = try actions.store.items(in: id).first(where: { $0.id == row.item.id }) else { continue }
            if EditorSynchronization.flush(local: row.editor.string, committed: item.text, active: true, marked: row.editor.hasMarkedText()) {
                var updated = item; updated.text = row.editor.string; try actions.store.update(updated)
            }
            row.editor.breakUndoCoalescing()
        }
    }
    func flushBeforeFocusLoss() {
        do { try flushRolloverEdits() } catch { failure(error) }
    }
    func prepareForRemoval() {
        invalidated = true
        saveWork?.cancel(); saveWork = nil; pendingItems = []; pendingTitle = false
        activeMenu?.cancelTracking()
        canMutate = { false }
        if titleEditor.currentEditor() != nil || orderedRows.contains(where: { window?.firstResponder === $0.editor }) {
            window?.makeFirstResponder(nil)
        }
        titleEditor.ownedEditor.undoManager?.removeAllActions()
        for row in orderedRows { row.editor.undoManager?.removeAllActions() }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsLayout = true; colors() }
    override func mouseExited(with event: NSEvent) { hovering = false; needsLayout = true; colors() }
    override func menu(for event: NSEvent) -> NSMenu? { contextMenu() }
    private func contextMenu() -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        let paletteItem = NSMenuItem(title: "颜色", action: nil, keyEquivalent: "")
        let swatches = NSView(frame: NSRect(x: 0, y: 0, width: 232, height: 36))
        for (index, color) in NotePalette.allCases.enumerated() {
            let button = NSButton(title: "", target: self, action: #selector(selectColor(_:)))
            button.tag = index; button.isBordered = false; button.wantsLayer = true
            button.frame = NSRect(x: CGFloat(9 + index * 28), y: 7, width: 22, height: 22)
            button.layer?.cornerRadius = 11
            button.layer?.backgroundColor = NoteTheme.background(color).cgColor
            button.layer?.borderColor = NoteTheme.primary.withAlphaComponent(0.6).cgColor
            button.layer?.borderWidth = color == note.color ? 2 : 0.5
            button.toolTip = color.name; button.setAccessibilityLabel(color.name + (color == note.color ? "（当前）" : ""))
            swatches.addSubview(button)
        }
        paletteItem.view = swatches; menu.addItem(paletteItem); menu.addItem(.separator())
        for (index, title) in ["桌面层", "普通", "置顶"].enumerated() {
            let item = NSMenuItem(title: title, action: #selector(selectLevel(_:)), keyEquivalent: "")
            item.target = self; item.tag = index
            item.state = [WindowLevel.desktop, .ordinary, .topmost][index] == note.level ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for (index, title) in ["停靠到顶部", "停靠到左侧", "停靠到右侧", "移出停靠条"].enumerated() {
            let item = NSMenuItem(title: title, action: #selector(docking(_:)), keyEquivalent: "")
            item.target = self; item.tag = index
            item.isEnabled = !reveal
            if index == 3 { item.isEnabled = !reveal && (window as? NotePanel)?.docked == true }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for (title, selector) in [(note.collapsed ? "展开" : "折叠", #selector(collapse)),
                                  ("随内容调整高度", #selector(autoHeight)), ("添加事项", #selector(addItem)), ("删除便签", #selector(deleteNote))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            if title == "删除便签" { item.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.systemRed]) }
            menu.addItem(item)
        }
        activeMenu = menu
        return menu
    }
    @objc private func docking(_ sender: NSMenuItem) {
        guard !invalidated, canMutate() else { return }
        (window as? NotePanel)?.dockingAction?(sender.tag == 3 ? nil : [DockEdge.top, .left, .right][sender.tag])
    }
    @objc private func showMenu() { contextMenu().popUp(positioning: nil, at: NSPoint(x: bounds.width - 108, y: 34), in: self) }
    @objc private func selectColor(_ sender: NSButton) {
        run { try actions.appearance(id, color: NotePalette.allCases[sender.tag]) }
        activeMenu?.cancelTracking()

    }
    @objc private func selectLevel(_ sender: NSMenuItem) { run { try actions.appearance(id, level: [WindowLevel.desktop, .ordinary, .topmost][sender.tag]) } }
    @objc private func pin() { run { try actions.appearance(id, level: note.level == .topmost ? .desktop : .topmost) } }
    @objc private func collapse() { run { try actions.appearance(id, collapsed: !note.collapsed) } }
    @objc private func autoHeight() { run { try actions.appearance(id, automaticHeight: true) } }
    func run(_ body: () throws -> Void) { guard !invalidated, canMutate() else { return }; do { try body(); changed() } catch { failure(error) } }
    func save(_ item: ItemID, text _: String) { // No reload while typing/composing.
        guard !invalidated, let editor = rows[item]?.editor, !editor.hasMarkedText() else { return }
        actions.noteTyping()
        pendingItems.insert(item)
        needsLayout = true // wrapped rows grow immediately; the window follows after the pause
        scheduleSave()
    }
    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do { try self.commitPendingSaves(notify: true) } catch { self.failure(error) }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: work)
    }
    /// Writes edits the user typed in this card. Rows still composing stay pending.
    func commitPendingSaves(notify: Bool) throws {
        saveWork?.cancel(); saveWork = nil
        guard !invalidated, !pendingItems.isEmpty || pendingTitle else { return }
        var wrote = false, composing = false
        for item in pendingItems {
            guard let editor = rows[item]?.editor else { pendingItems.remove(item); continue }
            if editor.hasMarkedText() { composing = true; continue }
            pendingItems.remove(item)
            do { try actions.text(item, in: id, editor.string); wrote = true }
            catch StoreError.notFound { continue } // archived or deleted meanwhile
        }
        if pendingTitle {
            let editor = titleEditor.currentEditor() as? NSTextView
            if editor?.hasMarkedText() == true { composing = true }
            else {
                pendingTitle = false
                try actions.title(id, editor?.string ?? titleEditor.stringValue); wrote = true
            }
        }
        if composing { scheduleSave() }
        if wrote && notify { changed() }
    }
    /// Return leaves blank rows behind; once focus leaves the note they disappear silently.
    func pruneBlankRowsAfterFocusLoss() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.invalidated, self.window?.isKeyWindow != true, self.canMutate(),
                  self.orderedRows.contains(where: { $0.editor.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return }
            self.run { try self.actions.pruneBlankItems(in: self.id) }
        }
    }
    func toggle(_ item: ItemID) { run { try actions.toggle(item, in: id) } }
    func delete(_ item: ItemID) {
        guard canMutate() else { return }
        let previous = orderedRows.firstIndex(where: { $0.item.id == item }) ?? 0
        let blank = rows[item]?.editor.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
        pendingItems.remove(item)
        // Blank rows vanish without a toast; rows with content stay recoverable.
        run { blank ? try actions.discardBlankItem(item, in: id) : try actions.deleteItem(item, in: id) }
        if !orderedRows.isEmpty {
            window?.makeFirstResponder(orderedRows[min(previous, orderedRows.count - 1)].editor)
        }
    }
    func add(after item: ItemID? = nil) {
        var created: Item?
        run { created = try actions.add(in: id, after: item) }
        if let created, let editor = rows[created.id]?.editor { window?.makeFirstResponder(editor) }
    }
    /// Inserts pasted lines as new rows after `item` and focuses the last one.
    func insert(lines: [String], after item: ItemID) {
        var last: Item?
        run {
            var anchor = item
            for line in lines { let created = try actions.add(in: id, after: anchor, text: line); anchor = created.id; last = created }
        }
        if let last, let editor = rows[last.id]?.editor {
            window?.makeFirstResponder(editor)
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        }
    }
    func focus(from item: ItemID, offset: Int) {
        guard let index = orderedRows.firstIndex(where: { $0.item.id == item }),
              orderedRows.indices.contains(index + offset) else { return }
        let editor = orderedRows[index + offset].editor
        window?.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: offset < 0 ? (editor.string as NSString).length : 0, length: 0))
        editor.scrollRangeToVisible(editor.selectedRange())
        orderedRows[index + offset].scrollToVisible(orderedRows[index + offset].bounds)
    }
    func move(_ item: ItemID, before target: ItemID) {
        run {
            var ids = try actions.store.items(in: id).map(\.id)
            guard item != target, ids.contains(item), ids.contains(target) else { return }
            ids.removeAll { $0 == item }; ids.insert(item, at: ids.firstIndex(of: target)!)
            try actions.reorder(id, ids: ids)
        }
    }
    func undo() -> Bool { !invalidated && undoDelete() }
    func editingEnded() {
        do { try commitPendingSaves(notify: false) } catch { failure(error) }
        // AppKit may notify before makeFirstResponder has finished. Never reenter
        // reconciliation while a disappearing row is relinquishing focus.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.invalidated else { return }
            self.changed()
        }
    }
    func controlTextDidChange(_ notification: Notification) {
        guard !invalidated, let editor = titleEditor.currentEditor() as? NSTextView, !editor.hasMarkedText() else { return }
        actions.noteTyping()
        pendingTitle = true
        scheduleSave()
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        // Change notifications and the focus-loss flush own writes. An ended
        // field editor may already be passive and must never republish stale text.
        do { try commitPendingSaves(notify: false) } catch { failure(error) }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.invalidated else { return }
            self.changed()
        }
    }
    @objc private func addItem() { add() }
    @objc private func deleteNote() { run { try actions.deleteNote(id) } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); colors() }
    private func colors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer?.backgroundColor = NoteTheme.background(palette).cgColor
            layer?.borderColor = (hovering ? NoteTheme.primary.withAlphaComponent(0.10) : NoteTheme.border).cgColor; CATransaction.commit()
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
    private var tracking: NSTrackingArea?
    private static let type = NSPasteboard.PasteboardType("local.desknodes.native.item")
    init(item: Item, owner: NoteCardView) {
        self.item = item; self.owner = owner; editor = NoteTextView(text: item.text)
        super.init(frame: .zero)
        check.target = self; check.action = #selector(toggle)
        remove.target = self; remove.action = #selector(deleteItem); remove.isBordered = false
        remove.setAccessibilityLabel("删除事项")
        remove.toolTip = "删除事项"; handle.textColor = NoteTheme.secondary
        textScroll.drawsBackground = false
        textScroll.documentView = editor
        [check, textScroll, remove, handle].forEach { addSubview($0) }
        editor.delegate = self
        editor.addRow = { [weak self] in guard let self else { return }; self.owner?.add(after: self.item.id) }
        editor.deleteEmptyRow = { [weak self] in guard let self else { return }; self.owner?.delete(self.item.id) }
        editor.deletionUndo = { [weak owner] in owner?.undo() ?? false }
        editor.moveToRow = { [weak self] offset in guard let self else { return }; self.owner?.focus(from: self.item.id, offset: offset) }
        editor.toggleCompletion = { [weak self] in guard let self else { return }; self.owner?.toggle(self.item.id) }
        editor.pasteLines = { [weak self] lines in guard let self else { return }; self.owner?.insert(lines: lines, after: self.item.id) }
        remove.isHidden = true; handle.isHidden = true
        registerForDraggedTypes([Self.type])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        handle.frame = NSRect(x: bounds.width - 10, y: 5, width: 10, height: 18)
        check.frame = NSRect(x: 0, y: 5, width: 16, height: 16)
        textScroll.frame = NSRect(x: 25, y: 0, width: bounds.width - 55, height: bounds.height)
        editor.frame.size = NSSize(width: textScroll.contentSize.width, height: max(bounds.height, editor.frame.height))
        remove.frame = NSRect(x: bounds.width - 30, y: 3, width: 19, height: 20)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { remove.isHidden = false; handle.isHidden = false }
    override func mouseExited(with event: NSEvent) { remove.isHidden = true; handle.isHidden = true }
    func fittingHeight(width: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 26; paragraph.maximumLineHeight = 26
        let rect = (editor.string as NSString).boundingRect(
            with: NSSize(width: max(1, width - 55), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 13), .paragraphStyle: paragraph])
        return max(26, ceil(rect.height))
    }
    func synchronize(_ text: String) {
        guard EditorSynchronization.receive(local: editor.string, committed: text, active: window?.isKeyWindow == true && window?.firstResponder === editor, marked: editor.hasMarkedText()) else { return }
        editor.breakUndoCoalescing()
        editor.undoManager?.removeAllActions()
        editor.string = text
    }
    func textDidEndEditing(_ notification: Notification) {
        guard let owner else { return }
        // Commit this card's own typed edits (never a passive copy), then refresh.
        owner.editingEnded()
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
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        setCompleted(check.state == .on)
    }
    func textDidChange(_ notification: Notification) { owner?.save(item.id, text: editor.string); setCompleted(check.state == .on) }
    @objc private func toggle() { owner?.toggle(item.id) }
    @objc private func deleteItem() { owner?.delete(item.id) }
    override func mouseDown(with event: NSEvent) {
        guard convert(event.locationInWindow, from: nil).x > bounds.width - 12 else { super.mouseDown(with: event); return }
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
            NoteTheme.checkboxFill.setFill(); circle.fill()
            NoteTheme.checkmark.setStroke()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 4, y: 9)); path.line(to: NSPoint(x: 7, y: 6))
            path.line(to: NSPoint(x: 13, y: 12))
            path.lineWidth = 1.6; path.lineCapStyle = .round; path.stroke()
        } else {
            NoteTheme.checkboxBorder.setStroke()
            circle.lineWidth = 1.5; circle.stroke()
        }
    }
}
