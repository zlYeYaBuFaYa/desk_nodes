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
    /// The fullscreen reveal copies. `changed == nil` means every card.
    var refreshReveal: (_ notes: [Note], _ items: [NoteID: [Item]], _ changed: Set<NoteID>?) -> Void = { _, _, _ in }
    /// Screens used for automatic-height limits; injectable for tests.
    var screens: () -> [DockScreen] = { DockController.screens() }

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
        }
        let visible = NSScreen.screens.first?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        for (index, note) in notes.enumerated() {
            let state = Rendered(note: note, items: items[note.id] ?? [])
            let previous = rendered[note.id]
            if let panel = panels[note.id], let card = panel.contentView as? NoteCardView {
                guard scope == .all || previous != state else { continue }
                card.refresh(note, items: state.items); try configure(panel, note: note)
                pass.updated.insert(note.id)
            } else {
                let panel = NotePanel(origin: NSPoint(x: visible.midX - 120 + CGFloat(index % 5) * 24,
                                                      y: visible.maxY - 300 - CGFloat(index % 5) * 24))
                panel.deletionUndo = undo
                let card = NoteCardView(note: note, actions: actions, changed: changed,
                                        undoDelete: undo, failure: failure, items: state.items)
                card.canMutate = canMutate
                panel.contentView = card
                panels[note.id] = panel; try configure(panel, note: note); panel.showNote()
                pass.created.insert(note.id)
            }
            // Recorded only after the panel applied it, so a failed pass is retried next time.
            rendered[note.id] = state
            if note.isDocked || previous?.note.isDocked == true { strips = true }
        }
        pass.stripsLaidOut = strips
        let changedIDs: Set<NoteID>? = scope == .all ? nil : pass.touched
        if strips || !pass.touched.isEmpty { layoutDock(panels, modes, changedIDs, strips) }
        refreshReveal(notes, items, changedIDs)
        return (notes, pass)
    }

    private func configure(_ panel: NotePanel, note: Note) throws {
        panel.choice = note.level; panel.modes = modes; panel.applyLevel()
        guard case .free(let display, let x, let y, let width, let height) = note.placement else {
            return // DockController owns strip geometry; free geometry stays durable.
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
        }
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
        for panel in panels.values { panel.undoManager?.removeAllActions(); panel.close() }
        panels = [:]; rendered = [:]; modes = WindowModes()
    }
}

extension Note {
    var isDocked: Bool { if case .dock = placement { return true }; return false }
}
