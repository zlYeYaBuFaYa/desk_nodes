import AppKit
import DeskNodesActions
import DeskNodesPersistence

/// How much a refresh must touch beyond notes whose stored state changed.
enum RefreshScope: Comparable {
    /// Only notes whose row or live items differ from what their panel last showed.
    case changes
    /// Also relayout every dock strip: UI-only state changed (tab selection, page, drag, settings).
    case layout
    /// Re-apply everything: screens changed or panels were rebuilt.
    case all
}

/// Owns the desktop note panels and reconciles them with the store.
///
/// Each refresh reads notes and all live items in two queries, compares them with what
/// each panel last rendered, and touches only notes that changed. Any database change
/// (typing, rollover, undo, restore, import) is picked up by the comparison itself, so
/// callers never have to describe what they changed.
@MainActor
final class NoteSurfaces {
    struct Rendered: Equatable {
        let note: Note
        let items: [Item]
    }
    /// What one refresh touched; used by the owner and by tests.
    struct Pass: Equatable {
        var created: Set<NoteID> = []
        var updated: Set<NoteID> = []
        var removed: Set<NoteID> = []
        var stripsLaidOut = false
        var touched: Set<NoteID> { created.union(updated) }
    }

    private let actions: NoteActions
    private(set) var panels: [NoteID: NotePanel] = [:]
    private var rendered: [NoteID: Rendered] = [:]
    var modes = WindowModes()

    private let changed: () -> Void
    private let undo: () -> Bool
    private let canMutate: () -> Bool
    private let failure: (Error) -> Void
    /// Dock strips and free-panel clamping. `changed == nil` means every free panel.
    var layoutDock: (_ panels: [NoteID: NotePanel], _ modes: WindowModes, _ changed: Set<NoteID>?, _ strips: Bool) -> Void = { _, _, _, _ in }
    /// Screens used for automatic-height limits; injectable for tests.
    var screens: () -> [DockScreen] = { DockController.screens() }
    /// Global collapse / inactive page. Consulted before a new panel is first shown;
    /// existing panels are hidden and shown by the desktop controller itself.
    var hidden: (NoteID) -> Bool = { _ in false }
    /// The toolbar's deletion target. Independent of keyboard focus: clicking the
    /// (non-activating) toolbar never clears it.
    private(set) var selection: NoteID?
    var selectionChanged: () -> Void = {}
    func select(_ id: NoteID?) {
        let id = id.flatMap { panels[$0] == nil ? nil : $0 }
        guard id != selection else { return }
        selection = id
        for (key, panel) in panels { (panel.contentView as? NoteCardView)?.isSelected = key == id }
        selectionChanged()
    }

    /// Batch selection: nil outside it, otherwise the picked notes.
    private(set) var picked: Set<NoteID>?
    var pickedChanged: () -> Void = {}
    func setPicked(_ ids: Set<NoteID>?) {
        let ids = ids.map { $0.filter { panels[$0] != nil } }
        guard ids != picked else { return }
        picked = ids
        for (key, panel) in panels { (panel.contentView as? NoteCardView)?.picked = ids.map { $0.contains(key) } }
        pickedChanged()
    }
    /// Notes on screen now: not hidden by collapse, an arrangement page or a dock overflow.
    var pickable: [NoteID: NotePanel] { panels.filter { !$0.value.suppressed && $0.value.isVisible } }
    /// Press routing and the "选择多张…" menu item, wired by the owner.
    var pickPress: (NSEvent, NoteID) -> Bool = { _, _ in false }
    var pickMany: (NoteID) -> Void = { _ in }

    init(actions: NoteActions, changed: @escaping () -> Void, undo: @escaping () -> Bool,
         canMutate: @escaping () -> Bool, failure: @escaping (Error) -> Void) {
        self.actions = actions; self.changed = changed; self.undo = undo
        self.canMutate = canMutate; self.failure = failure
    }

    var cards: [NoteCardView] { panels.values.compactMap { $0.contentView as? NoteCardView } }
    var hasMarkedComposition: Bool { cards.contains { $0.hasMarkedComposition } }
    func flushEdits() throws { for card in cards { try card.flushRolloverEdits() } }

    @discardableResult
    func refresh(_ scope: RefreshScope = .changes) throws -> (notes: [Note], pass: Pass) {
        let notes = try actions.store.notes()
        let items = try actions.store.liveItemsByNote()
        var pass = Pass()
        var strips = scope >= .layout
        let ids = Set(notes.map(\.id))
        for id in Array(panels.keys) where !ids.contains(id) {
            if rendered[id]?.note.isDocked == true { strips = true }
            (panels[id]?.contentView as? NoteCardView)?.prepareForRemoval()
            panels.removeValue(forKey: id)?.dismissNote()
            rendered[id] = nil; pass.removed.insert(id)
            if selection == id { selection = nil; selectionChanged() }
            if picked?.contains(id) == true { picked?.remove(id); pickedChanged() }
        }
        let visible = NSScreen.screens.first?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        for (index, note) in notes.enumerated() {
            var state = Rendered(note: note, items: items[note.id] ?? [])
            let previous = rendered[note.id]
            if let panel = panels[note.id], let card = panel.contentView as? NoteCardView {
                guard scope == .all || previous != state else { continue }
                card.refresh(note, items: state.items)
                state = Rendered(note: try configure(panel, note: note), items: state.items)
                pass.updated.insert(note.id)
            } else {
                let panel = NotePanel(origin: NSPoint(x: visible.midX - 120 + CGFloat(index % 5) * 24,
                                                      y: visible.maxY - 300 - CGFloat(index % 5) * 24))
                panel.deletionUndo = undo
                let id = note.id
                panel.pressed = { [weak self] in self?.select(id) }
                panel.pickPress = { [weak self] event in self?.pickPress(event, id) ?? false }
                panel.suppressed = hidden(id)
                let card = NoteCardView(note: note, actions: actions, changed: changed,
                                        undoDelete: undo, failure: failure, items: state.items)
                card.canMutate = canMutate
                card.pickMany = { [weak self] in self?.pickMany(id) }
                card.picked = picked.map { $0.contains(id) }
                panel.contentView = card
                panels[note.id] = panel
                state = Rendered(note: try configure(panel, note: note), items: state.items); panel.showNote()
                pass.created.insert(note.id)
            }
            // Recorded only after the panel applied it, so a failed pass is retried next time.
            rendered[note.id] = state
            if note.isDocked || previous?.note.isDocked == true { strips = true }
        }
        pass.stripsLaidOut = strips
        let changedIDs: Set<NoteID>? = scope == .all ? nil : pass.touched
        if strips || !pass.touched.isEmpty { layoutDock(panels, modes, changedIDs, strips) }
        return (notes, pass)
    }

    /// Returns the note as stored afterwards: fitting an automatic height to the content
    /// writes geometry, and recording that row keeps the next refresh from seeing a change.
    private func configure(_ panel: NotePanel, note: Note) throws -> Note {
        panel.choice = note.level; panel.modes = modes; panel.applyLevel()
        guard case .free(let display, let x, let y, let width, let height) = note.placement else {
            return note // DockController owns strip geometry; free geometry stays durable.
        }
        var expanded = NoteFrame(x: x, y: y, width: width, height: height)
        if note.automaticHeight {
            let availableHeight = DockGeometry.screen(display, screens: screens())?.available.height ?? 480
            let height = min(availableHeight, NoteFrame.automaticHeight(content: (panel.contentView as? NoteCardView)?.preferredHeight(width: expanded.width) ?? 120))
            expanded.y += expanded.height - height; expanded.height = height
        }
        let changedCollapse = panel.frame.height == 32 ? !note.collapsed : note.collapsed
        panel.present(expanded, collapsed: note.collapsed, animate: changedCollapse)
        let placement = Placement.free(expanded, displayID: display)
        if placement != note.placement, expanded.width >= 200, expanded.height >= 120 {
            try actions.finalGeometry(note.id, frame: expanded)
            return try actions.store.notes().first { $0.id == note.id } ?? note
        }
        return note
    }

    /// All-topmost / restore: levels only, no data read.
    func apply(_ modes: WindowModes) {
        self.modes = modes
        for panel in panels.values { panel.modes = modes; panel.applyLevel() }
        layoutDock(panels, modes, [], true)
    }
    func lowerTransientRaises() {
        for panel in panels.values { panel.temporarilyRaised = false; panel.applyLevel() }
    }
    /// Import replaces every identity: cards must already be invalidated by the caller.
    func discardAll() {
        for panel in panels.values { panel.undoManager?.removeAllActions(); panel.pressed = nil; panel.pickPress = nil; panel.close() }
        panels = [:]; rendered = [:]; modes = WindowModes(); selection = nil; picked = nil
    }
}

extension Note {
    var isDocked: Bool { if case .dock = placement { return true }; return false }
}
