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
    /// The frame last applied by `present`, i.e. where the note rests between animations.
    var restingFrame: NSRect?
    /// Any click inside the note makes it the toolbar's deletion target.
    var pressed: (() -> Void)?
    /// Hidden by global collapse or by an inactive arrangement page. While set, no refresh,
    /// dock layout or restore path can order the panel back on screen.
    var suppressed = false {
        didSet { if suppressed && !oldValue { orderOut(nil) } }
    }
    override func orderFrontRegardless() { guard !suppressed else { return }; super.orderFrontRegardless() }
    override func orderFront(_ sender: Any?) { guard !suppressed else { return }; super.orderFront(sender) }
    override func makeKeyAndOrderFront(_ sender: Any?) { guard !suppressed else { return }; super.makeKeyAndOrderFront(sender) }
    /// Batch selection: consumes a press while selecting, or a ⌘-press that starts it.
    var pickPress: ((NSEvent) -> Bool)?
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown, pickPress?(event) == true { return }
        if event.type == .leftMouseDown || event.type == .rightMouseDown { pressed?() }
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
        applyLevel()
    }
    /// Short ease-out slide and fade; the window closes when it ends.
    func dismissNote() {
        guard isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = contentView?.layer else { close(); return }
        ignoresMouseEvents = true
        let group = CAAnimationGroup()
        group.animations = [Motion.basic("transform.translation.y", from: 0, to: -8), Motion.basic("opacity", from: 1, to: 0)]
        group.duration = MotionPolicy.deletion; group.timingFunction = Motion.easeOut
        group.fillMode = .forwards; group.isRemovedOnCompletion = false
        layer.add(group, forKey: "noteDeletion")
        DispatchQueue.main.asyncAfter(deadline: .now() + MotionPolicy.deletion) { self.close() }
    }
    func showNote() {
        orderFrontRegardless()
        guard isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = contentView?.layer else { return }
        let group = CAAnimationGroup()
        group.animations = [Motion.basic("transform.translation.y", from: -8, to: 0), Motion.basic("opacity", from: 0, to: 1)]
        group.duration = MotionPolicy.insertion; group.timingFunction = Motion.easeOut
        layer.add(group, forKey: "noteInsertion")
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
    private let separator = NSView()
    private let moreButton = NSButton()
    /// The current note, outlined in a deeper tone of its own colour.
    var isSelected = false { didSet { if isSelected != oldValue { colors() } } }
    /// Batch selection: nil outside it, otherwise whether this note is picked.
    var picked: Bool? {
        didSet {
            guard picked != oldValue else { return }
            pickBadge.isHidden = picked == nil
            pickBadge.image = NSImage(systemSymbolName: picked == true ? "checkmark.circle.fill" : "circle", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
            pickBadge.contentTintColor = picked == true ? .controlAccentColor : NoteTheme.secondary
            pickBadge.setAccessibilityLabel(picked == true ? "已选中" : "未选中")
            colors()
        }
    }
    /// "选择多张…" in the note menu.
    var pickMany: (() -> Void)?
    private let pickBadge = NSImageView()
    private let list = FlippedList()
    private var orderedRows: [ItemRow] = []
    private let scroll = NSScrollView()
    private var rows: [ItemID: ItemRow] = [:]
    private var note: Note
    var canMutate: () -> Bool = { true }
    private var invalidated = false
    private var hovering = false
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
         undoDelete: @escaping () -> Bool, failure: @escaping (Error) -> Void,
         items: [Item]? = nil) {
        self.note = note
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
        wantsLayer = true; layer?.cornerRadius = NoteMetrics.cornerRadius; layer?.borderWidth = 1; layer?.masksToBounds = true
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(activationChanged), name: name, object: nil)
        }
        titleEditor.stringValue = note.title ?? ""
        titleEditor.setAccessibilityLabel("便签标题（可选）")
        titleEditor.lineBreakMode = .byTruncatingTail; titleEditor.cell?.isScrollable = true
        pinIndicator.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "已置顶")
        pinIndicator.contentTintColor = NoteTheme.tertiary
        addButton.target = self; addButton.action = #selector(addItem)
        addButton.isBordered = false; addButton.alignment = .left
        addButton.setAccessibilityLabel("添加事项")
        separator.wantsLayer = true
        moreButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "更多操作")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        moreButton.isBordered = false; moreButton.contentTintColor = NoteTheme.secondary
        moreButton.target = self; moreButton.action = #selector(showMenu)
        moreButton.setAccessibilityLabel("更多操作"); moreButton.toolTip = "颜色、置顶、折叠与更多操作"
        titleEditor.isBordered = false; titleEditor.drawsBackground = false
        titleEditor.textColor = NoteTheme.primary; titleEditor.delegate = self
        count.textColor = NoteTheme.secondary; count.alignment = .right
        collapsedLabel.textColor = NoteTheme.primary
        collapsedLabel.font = NoteType.font(ofSize: NoteMetrics.titleSize - 2, weight: .semibold)
        collapsedLabel.lineBreakMode = .byTruncatingTail
        grip.resize = true
        let finish: (NoteFrame, Bool) -> Void = { [weak self] frame, resize in
            guard let self else { return }
            self.run { try self.actions.finalGeometry(self.id, frame: frame, manuallyResized: resize) }
        }
        header.finish = finish; grip.finish = finish
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        scroll.documentView = list
        [header, titleEditor, collapsedLabel, count, scroll, separator, grip, pinIndicator, addButton, moreButton].forEach { addSubview($0) }
        pickBadge.frame = NSRect(x: 7, y: 6, width: 22, height: 22); pickBadge.isHidden = true
        addSubview(pickBadge)
        applyTextSize()
        refresh(note, items: items)
    }
    required init?(coder: NSCoder) { fatalError() }
    /// Applies `NoteType` (文字大小) to this card and its rows; the folded bar keeps its size.
    /// 文字大小 and 字体. The count stays in system digits so fractions line up.
    func applyTextSize() {
        titleEditor.font = NoteType.font(ofSize: NoteType.titleSize, weight: .semibold)
        collapsedLabel.font = NoteType.font(ofSize: NoteMetrics.titleSize - 2, weight: .semibold)
        // A quiet placeholder: an untitled note is normal, not a missing field.
        titleEditor.placeholderAttributedString = NSAttributedString(string: "标题",
            attributes: [.font: NoteType.font(ofSize: NoteType.titleSize), .foregroundColor: NoteTheme.tertiary])
        addButton.attributedTitle = NSAttributedString(string: "＋ 添加事项", attributes: [
            .font: NoteType.font(ofSize: NoteType.secondarySize + 1), .foregroundColor: NoteTheme.secondary])
        count.font = .monospacedDigitSystemFont(ofSize: NoteType.secondarySize, weight: .regular)
        for row in orderedRows { row.applyTextSize() }
        needsLayout = true
    }
    /// Header, list and footer have fixed slots; hovering only shows controls in space
    /// that is already reserved, so the title never changes width under the pointer.
    override func layout() {
        super.layout()
        let padding = CGFloat(NoteMetrics.padding)
        let compact = note.collapsed
        // Folded notes have no grip row; "更多" shares the count slot.
        let inlineMore = compact
        let headerHeight = compact ? bounds.height : NoteType.headerHeight
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        header.showsGrip = !inlineMore
        titleEditor.isHidden = compact
        collapsedLabel.isHidden = !compact
        scroll.isHidden = compact
        let footer = !compact
        addButton.isHidden = !footer; separator.isHidden = !footer
        grip.isHidden = compact || !hovering || (window as? NotePanel)?.docked == true
        // Title band: 18pt down and 22pt tall at standard size, scaled with the type.
        let scale = CGFloat(NoteType.size.scale), titleHeight = (22 * scale).rounded()
        let titleY: CGFloat = compact ? (bounds.height - 22) / 2 : (18 * scale).rounded()
        let countWidth = max(32, ceil(count.attributedStringValue.size().width) + 2)
        let countHeight = compact ? 16 : (16 * scale).rounded()
        count.frame = NSRect(x: bounds.width - padding - countWidth, y: titleY + (compact ? 3 : (titleHeight - countHeight) / 2 + 1), width: countWidth, height: countHeight)
        count.isHidden = inlineMore && hovering
        moreButton.isHidden = !hovering
        moreButton.frame = inlineMore
            ? NSRect(x: bounds.width - padding - 24, y: titleY - 1, width: 26, height: 24)
            : NSRect(x: bounds.width - 34, y: 2, width: 28, height: 18)
        let pinned = note.level == .topmost
        pinIndicator.isHidden = !pinned
        pinIndicator.frame = NSRect(x: count.frame.minX - 16, y: count.frame.midY - 5.5, width: 11, height: 11)
        let titleLimit = (pinned ? pinIndicator.frame.minX : count.frame.minX) - 10
        let available = max(1, titleLimit - padding)
        // An idle title is only as wide as its text, leaving the rest of the header to drag by.
        let shown = titleEditor.stringValue.isEmpty ? "标题" : titleEditor.stringValue
        let fitted = ceil((shown as NSString).size(withAttributes: [.font: titleEditor.font as Any]).width) + 12
        let editing = titleEditor.currentEditor() != nil
        titleEditor.frame = NSRect(x: padding - 2, y: titleY, width: editing ? available : min(available, max(44, fitted)), height: titleHeight)
        collapsedLabel.frame = NSRect(x: padding, y: titleY + 1, width: available, height: 20)
        let footerTop = bounds.height - NoteType.footerHeight
        separator.frame = NSRect(x: padding, y: footerTop, width: max(1, bounds.width - padding * 2), height: 1)
        addButton.frame = NSRect(x: padding - 2, y: footerTop + (NoteType.footerHeight - 28) / 2, width: max(1, min(160, bounds.width - padding * 2)), height: 28)
        grip.frame = NSRect(x: bounds.width - 18, y: bounds.height - 18, width: 16, height: 16)
        scroll.frame = NSRect(x: listX, y: headerHeight, width: max(1, bounds.width - listX - 8),
                              height: max(1, bounds.height - headerHeight - bottomInset(footer: footer)))
        var y: CGFloat = 0
        for row in orderedRows {
            let height = row.fittingHeight(width: scroll.contentSize.width)
            row.frame = NSRect(x: 0, y: y, width: scroll.contentSize.width, height: height)
            y += height
        }
        list.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width,
                            height: max(scroll.contentSize.height, y))
    }
    /// The circle's hit area starts left of the padding, so the circle itself lines up with the title.
    private var listX: CGFloat { CGFloat(NoteMetrics.padding) - ItemRow.circleInset }
    private func bottomInset(footer: Bool) -> CGFloat { footer ? NoteType.footerHeight + 6 : 10 }
    var firstEditor: NoteTextView? { orderedRows.first?.editor }
    var itemRows: [ItemRow] { orderedRows }
    var titleFrame: NSRect { titleEditor.frame }
    private var isDocked: Bool { if case .dock = note.placement { return true }; return false }
    func preferredHeight(width: CGFloat) -> Double {
        let compact = note.collapsed
        let header = NoteType.headerHeight
        let rows = orderedRows.reduce(CGFloat(0)) { $0 + $1.fittingHeight(width: width - listX - 8) }
        return Double(compact ? CGFloat(NoteMetrics.collapsedHeight) : header + rows + bottomInset(footer: true))
    }
    /// `preloaded` comes from a batched refresh; nil reads this note's rows itself.
    func refresh(_ note: Note, items preloaded: [Item]? = nil) {
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
            let items = try preloaded ?? actions.store.items(in: id)
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
                row.setState(completed: item.completed, struck: item.struck)
            }
            collapsedLabel.stringValue = WindowModes.collapsedTitle(note.title, firstItem: items.first?.text)
            setAccessibilityLabel("便签：" + (collapsedLabel.stringValue.isEmpty ? "无标题" : collapsedLabel.stringValue))
            // Struck-out items were dropped, so they leave the progress count.
            let done = items.filter(\.completed).count, total = items.filter { !$0.struck }.count
            setAccessibilityValue("完成 \(done) / \(total)" + (note.collapsed ? "，已折叠" : ""))
            layer?.cornerRadius = note.collapsed ? NoteMetrics.collapsedCornerRadius : NoteMetrics.cornerRadius
            count.stringValue = "\(done) / \(total)"
            count.setAccessibilityLabel("已完成 \(done) 项，共 \(total) 项")
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
    func controlTextDidBeginEditing(_ notification: Notification) { needsLayout = true }
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
        // 停靠 ▸ marks the current edge; 取消停靠 only appears for a docked note.
        var dockedEdge: DockEdge?
        if case .dock(let edge, _) = note.placement { dockedEdge = edge }
        let dockItem = NSMenuItem(title: "停靠", action: nil, keyEquivalent: ""), edges = NSMenu()
        edges.autoenablesItems = false
        for (index, edge) in [DockEdge.top, .left, .right].enumerated() {
            let item = NSMenuItem(title: ["顶部", "左侧", "右侧"][index], action: #selector(docking(_:)), keyEquivalent: "")
            item.target = self; item.tag = index; item.state = edge == dockedEdge ? .on : .off
            edges.addItem(item)
        }
        dockItem.submenu = edges; menu.addItem(dockItem)
        if dockedEdge != nil {
            let undock = NSMenuItem(title: "取消停靠", action: #selector(docking(_:)), keyEquivalent: "")
            undock.target = self; undock.tag = 3; menu.addItem(undock)
        }
        menu.addItem(.separator())
        let folding = note.collapsed ? "展开" : "折叠"
        for (title, selector) in [(folding, #selector(collapse)), ("随内容调整高度", #selector(autoHeight)), ("添加事项", #selector(addItem))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self; menu.addItem(item)
        }
        menu.addItem(.separator())
        let pick = NSMenuItem(title: "选择多张…", action: #selector(startPicking), keyEquivalent: "")
        pick.target = self; pick.isEnabled = pickMany != nil; menu.addItem(pick)
        let delete = NSMenuItem(title: "删除便签", action: #selector(deleteNote), keyEquivalent: "")
        delete.target = self
        delete.attributedTitle = NSAttributedString(string: "删除便签", attributes: [.foregroundColor: NSColor.systemRed])
        menu.addItem(delete)
        activeMenu = menu
        return menu
    }
    @objc private func docking(_ sender: NSMenuItem) {
        guard !invalidated, canMutate() else { return }
        (window as? NotePanel)?.dockingAction?(sender.tag == 3 ? nil : [DockEdge.top, .left, .right][sender.tag])
    }
    @objc private func showMenu() { contextMenu().popUp(positioning: nil, at: NSPoint(x: moreButton.frame.minX, y: moreButton.frame.maxY + 4), in: self) }
    @objc private func selectColor(_ sender: NSButton) {
        run { try actions.appearance(id, color: NotePalette.allCases[sender.tag]) }
        activeMenu?.cancelTracking()

    }
    @objc private func selectLevel(_ sender: NSMenuItem) { run { try actions.appearance(id, level: [WindowLevel.desktop, .ordinary, .topmost][sender.tag]) } }
    @objc private func startPicking() { guard !invalidated, canMutate() else { return }; pickMany?() }
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
    func strike(_ item: ItemID) { run { try actions.strike(item, in: id) } }
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
        needsLayout = true
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        // Change notifications and the focus-loss flush own writes. An ended
        // field editor may already be passive and must never republish stale text.
        do { try commitPendingSaves(notify: false) } catch { failure(error) }
        needsLayout = true
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.invalidated else { return }
            self.changed()
        }
    }
    @objc private func addItem() { add() }
    /// Typed text is committed first, so undoing the deletion restores it too.
    @objc private func deleteNote() {
        guard !invalidated, canMutate() else { return }
        flushBeforeFocusLoss()
        run { try actions.deleteNote(id) }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); colors() }
    @objc private func activationChanged() { if isSelected { colors() } }
    private func colors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer?.backgroundColor = NoteTheme.background(palette).cgColor
            // While picking, the blue pick outline replaces the selection outline.
            let outlined = isSelected && picked == nil
            layer?.borderWidth = picked == true ? 2 : outlined ? 1.5 : 1
            layer?.borderColor = (picked == true ? NSColor.controlAccentColor
                : outlined ? NoteTheme.selection(palette, active: NSApp?.isActive ?? true)
                : hovering ? NoteTheme.primary.withAlphaComponent(0.10) : NoteTheme.border).cgColor
            separator.layer?.backgroundColor = NoteTheme.hairline.cgColor
            CATransaction.commit()
        }
    }
}

private final class FlippedList: NSView { override var isFlipped: Bool { true } }

/// Flipped, so the first line is at the top. The editor centres every fixed-height line,
/// so the completion circle aligns with the first line at `rowHeight / 2` for any script,
/// wrapped text, or composition in progress.
final class ItemRow: NSView, NSTextViewDelegate, NSDraggingSource {
    /// Hit area to the left of the visible circle.
    static let circleInset: CGFloat = 6
    static var textX: CGFloat { circleInset + NoteType.checkboxSize + NoteType.checkboxGap }
    let item: Item
    weak var owner: NoteCardView?
    let editor: NoteTextView
    let check = CompletionButton(done: false)
    private let textScroll = NSScrollView()
    private let remove = RowActionButton(symbol: "xmark", label: "删除事项", destructive: true)
    private let strikeButton = RowActionButton(symbol: "minus.circle", label: "划掉事项")
    private var struck = false
    private let handle = NSTextField(labelWithString: "⠿")
    override var isFlipped: Bool { true }
    private var tracking: NSTrackingArea?
    private static let type = NSPasteboard.PasteboardType("local.desknodes.native.item")
    init(item: Item, owner: NoteCardView) {
        self.item = item; self.owner = owner; editor = NoteTextView(text: item.text, centredLines: true)
        super.init(frame: .zero)
        check.target = self; check.action = #selector(toggle)
        remove.target = self; remove.action = #selector(deleteItem); remove.toolTip = "删除事项"
        strikeButton.target = self; strikeButton.action = #selector(strike)
        handle.textColor = NoteTheme.secondary; handle.font = .systemFont(ofSize: 13); handle.alignment = .center
        handle.setAccessibilityLabel("拖动排序")
        textScroll.drawsBackground = false
        textScroll.documentView = editor
        [check, textScroll, strikeButton, remove, handle].forEach { addSubview($0) }
        editor.delegate = self
        editor.addRow = { [weak self] in guard let self else { return }; self.owner?.add(after: self.item.id) }
        editor.deleteEmptyRow = { [weak self] in guard let self else { return }; self.owner?.delete(self.item.id) }
        editor.deletionUndo = { [weak owner] in owner?.undo() ?? false }
        editor.moveToRow = { [weak self] offset in guard let self else { return }; self.owner?.focus(from: self.item.id, offset: offset) }
        editor.toggleCompletion = { [weak self] in guard let self else { return }; self.owner?.toggle(self.item.id) }
        editor.toggleStrike = { [weak self] in guard let self else { return }; self.owner?.strike(self.item.id) }
        editor.pasteLines = { [weak self] lines in guard let self else { return }; self.owner?.insert(lines: lines, after: self.item.id) }
        remove.isHidden = true; strikeButton.isHidden = true; handle.isHidden = true
        registerForDraggedTypes([Self.type])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        let line = NoteType.rowHeight
        let action = CGFloat(RowActionButton.size)
        handle.frame = NSRect(x: bounds.width - 14, y: (line - 18) / 2, width: 14, height: 18)
        // Taller than the circle and as tall as the first line: a comfortable target.
        check.frame = NSRect(x: 0, y: 0, width: Self.textX - 4, height: line)
        textScroll.frame = NSRect(x: Self.textX, y: 0, width: max(1, bounds.width - Self.textX - CGFloat(NoteMetrics.rowTrailing)), height: bounds.height)
        editor.frame.size = NSSize(width: textScroll.contentSize.width, height: max(bounds.height, editor.frame.height))
        remove.frame = NSRect(x: bounds.width - 16 - action, y: (line - action) / 2, width: action, height: action)
        strikeButton.frame = NSRect(x: remove.frame.minX - 2 - action, y: (line - action) / 2, width: action, height: action)
    }
    /// Circle centre in row coordinates (flipped: y from the top).
    var circleCenter: NSPoint { NSPoint(x: check.frame.minX + Self.circleInset + NoteType.checkboxSize / 2, y: check.frame.midY) }
    func applyTextSize() { editor.applyTextSize(); check.needsDisplay = true; needsLayout = true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { [remove, strikeButton, handle].forEach { $0.isHidden = false } }
    override func mouseExited(with event: NSEvent) { [remove, strikeButton, handle].forEach { $0.isHidden = true } }
    func fittingHeight(width: CGFloat) -> CGFloat {
        let line = NoteType.lineHeight
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = line; paragraph.maximumLineHeight = line
        let rect = (editor.string as NSString).boundingRect(
            with: NSSize(width: max(1, width - Self.textX - CGFloat(NoteMetrics.rowTrailing)), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NoteType.font(ofSize: NoteType.itemSize), .paragraphStyle: paragraph])
        return max(NoteType.rowHeight, ceil(rect.height) + NoteType.rowPadding * 2)
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
    /// Completed reads as done (dimmed); struck reads as dropped (dimmed and lined through).
    func setState(completed: Bool, struck: Bool) {
        self.struck = struck
        check.state = completed ? .on : .off
        check.struck = struck
        check.needsDisplay = true
        check.setAccessibilityLabel(completed ? "取消完成" : "标记完成")
        strikeButton.symbol = struck ? "arrow.uturn.backward.circle" : "minus.circle"
        strikeButton.setAccessibilityLabel(struck ? "取消划掉" : "划掉事项")
        strikeButton.toolTip = struck ? "取消划掉（⌘⇧X）" : "划掉事项：不做了，但保留在便签里（⌘⇧X）"
        // Layout-manager temporary ink leaves text storage, selection and text undo untouched.
        guard let manager = editor.layoutManager else { return }
        let range = NSRange(location: 0, length: (editor.string as NSString).length)
        manager.removeTemporaryAttribute(.strikethroughStyle, forCharacterRange: range)
        manager.removeTemporaryAttribute(.strikethroughColor, forCharacterRange: range)
        manager.addTemporaryAttribute(.foregroundColor, value: struck ? NoteTheme.tertiary : completed ? NoteTheme.completed : NoteTheme.primary,
                                      forCharacterRange: range)
        if struck {
            manager.addTemporaryAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, forCharacterRange: range)
            manager.addTemporaryAttribute(.strikethroughColor, value: NoteTheme.completed, forCharacterRange: range)
        }
    }
    private func restyle() { setState(completed: check.state == .on, struck: struck) }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        restyle()
    }
    func textDidChange(_ notification: Notification) { owner?.save(item.id, text: editor.string); restyle() }
    @objc private func toggle() { owner?.toggle(item.id) }
    @objc private func strike() { owner?.strike(item.id) }
    @objc private func deleteItem() { owner?.delete(item.id) }
    override func mouseDown(with event: NSEvent) {
        guard convert(event.locationInWindow, from: nil).x > bounds.width - 15 else { super.mouseDown(with: event); return }
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

/// A row's hover action: a 22pt target with a quiet plate under the pointer, red when destructive.
final class RowActionButton: NSButton {
    static let size = 22.0
    var symbol: String { didSet { needsDisplay = true } }
    private let destructive: Bool
    private var hovering = false { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?
    init(symbol: String, label: String, destructive: Bool = false) {
        self.symbol = symbol; self.destructive = destructive
        super.init(frame: .zero)
        title = ""; isBordered = false
        setAccessibilityLabel(label)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override var isHidden: Bool { didSet { if isHidden { hovering = false } } }
    override func draw(_ dirtyRect: NSRect) {
        if hovering {
            NoteTheme.primary.withAlphaComponent(isHighlighted ? 0.16 : 0.09).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        let ink = hovering && destructive ? NSColor.systemRed : hovering ? NoteTheme.primary : NoteTheme.secondary
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium).applying(.init(paletteColors: [ink]))
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
        image.draw(in: NSRect(x: bounds.midX - image.size.width / 2, y: bounds.midY - image.size.height / 2,
                              width: image.size.width, height: image.size.height))
    }
}

/// Draws a fixed-size circle at `ItemRow.circleInset`, centred vertically in its bounds.
final class CompletionButton: NSButton {
    /// A struck-out row keeps an empty, fainter circle.
    var struck = false
    init(done: Bool) {
        super.init(frame: .zero)
        title = ""; isBordered = false; setButtonType(.toggle)
        state = done ? .on : .off
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let size = NoteType.checkboxSize
        let rect = NSRect(x: ItemRow.circleInset, y: bounds.midY - size / 2, width: size, height: size)
        if state == .on {
            NoteTheme.checkboxFill.setFill(); NSBezierPath(ovalIn: rect).fill()
            NoteTheme.checkmark.setStroke()
            // Unit points measured from the top-left of the circle, mapped for either flip.
            func point(_ u: CGFloat, _ v: CGFloat) -> NSPoint {
                NSPoint(x: rect.minX + u * size, y: isFlipped ? rect.minY + v * size : rect.maxY - v * size)
            }
            let path = NSBezierPath()
            path.move(to: point(0.29, 0.52)); path.line(to: point(0.44, 0.67)); path.line(to: point(0.72, 0.36))
            path.lineWidth = 1.6; path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke()
        } else {
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 0.7, dy: 0.7))
            NoteTheme.checkboxBorder.withAlphaComponent(struck ? 0.4 : 1).setStroke()
            circle.lineWidth = 1.4; circle.stroke()
        }
    }
}
