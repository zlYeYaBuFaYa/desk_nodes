import AppKit
import DeskNodesCore
import DeskNodesActions
import DeskNodesPersistence

/// Owns the resident toolbar and the desktop-wide presentation: global collapse,
/// "整理" and its overflow pages. It never edits note content; geometry changes go
/// through `NoteActions` in one transaction, and only at the end of a user action.
@MainActor
final class DesktopController {
    let toolbar = Toolbar()
    private let hint = StackHint()
    private let defaults: PresentationDefaults
    private let actions: NoteActions
    private(set) var state: DeskPresentation
    /// Bumped by every collapse/expand; a stale animation's completion does nothing.
    private var generation = 0
    /// Where each note rests while a collapse/expand animation moves it.
    private var resting: [NoteID: NSRect] = [:]
    private var pages: [NoteID: (page: Int, pages: Int)]
    private var notes: [Note] = []

    var surfaces: () -> NoteSurfaces? = { nil }
    /// The current dock controller; import replaces it.
    var docking: () -> DockController? = { nil }
    var refresh: (RefreshScope) -> Void = { _ in }
    var canMutate: () -> Bool = { true }
    var failure: (Error) -> Void = { _ in }

    init(actions: NoteActions, defaults: PresentationDefaults) {
        self.actions = actions; self.defaults = defaults
        state = DeskPresentation(collapsed: defaults.collapsed)
        pages = defaults.pages
        toolbar.moved = { [weak self] frame in self?.toolbarMoved(frame) }
        toolbar.turnPage = { [weak self] delta in self?.turnPage(delta) }
        hint.expand = { [weak self] in self?.expand() }
    }

    // MARK: Visibility

    /// Collapsed, or on an arrangement page that is not showing.
    func isHidden(_ id: NoteID) -> Bool { state.targetsCollapsed || !pageVisible(id) }
    private func pageVisible(_ id: NoteID) -> Bool {
        guard let entry = pages[id] else { return true }
        return Arrangement.visible(page: entry.page, pages: entry.pages, current: defaults.currentPage)
    }
    private var pageInfo: (Int, Int)? {
        let total = pages.values.map(\.pages).max() ?? 1
        return total > 1 ? (min(defaults.currentPage, total - 1), total) : nil
    }
    /// Applies the page rule to every panel; used after paging and arranging.
    private func applyPages() {
        guard !state.targetsCollapsed, let surfaces = surfaces() else { return }
        for (id, panel) in surfaces.panels {
            if !pageVisible(id) { panel.suppressed = true }
            else if panel.suppressed { panel.suppressed = false; panel.alphaValue = 1; panel.orderFrontRegardless() }
        }
    }

    // MARK: Toolbar

    func start() {
        placeToolbar()
        toolbar.panel.orderFrontRegardless()
        if state.targetsCollapsed { showHint() }
    }
    /// Called after every refresh with the live notes.
    func sync(_ notes: [Note]) {
        self.notes = notes
        let live = Set(notes.map(\.id))
        if pages.keys.contains(where: { !live.contains($0) }) {
            pages = pages.filter { live.contains($0.key) }
            if (pages.values.map(\.pages).max() ?? 1) <= 1 { pages = [:]; defaults.currentPage = 0 }
            defaults.pages = pages
        }
        // Nothing left to gather: drop the collapsed state rather than show an empty stack.
        if notes.isEmpty && state.targetsCollapsed {
            generation += 1; state = .expanded; defaults.collapsed = false; resting = [:]
            docking()?.suppressed = false; hideHint()
        }
        if state.targetsCollapsed { hint.show(colors: notes.map(\.color), count: notes.count) }
        updateToolbar()
    }
    func updateToolbar() {
        let selection = surfaces()?.selection
        let visible = selection.flatMap { surfaces()?.panels[$0] }.map { !$0.suppressed && $0.isVisible } ?? false
        let paged = toolbar.paged
        toolbar.update(Toolbar.State(count: notes.count, canDelete: state == .expanded && visible,
                                     collapsed: state.targetsCollapsed, page: pageInfo))
        // Only the pager row changes the toolbar's height; keep it on screen when it grows.
        if toolbar.paged != paged { placeToolbar(keepingPosition: true) }
    }
    /// Restores the saved position, or the first-launch spot when its display is gone.
    func placeToolbar(keepingPosition: Bool = false) {
        let screens = DockController.screens()
        guard let primary = screens.first else { return }
        let height = Double(toolbar.panel.frame.height)
        var frame: NoteFrame
        if keepingPosition {
            let f = toolbar.panel.frame
            frame = NoteFrame(x: f.minX, y: f.minY, width: f.width, height: f.height)
        } else if let saved = defaults.toolbar {
            frame = NoteFrame(x: saved.x, y: saved.y - height, width: ToolbarMetrics.width, height: height)
            if Arrangement.toolbarScreen(frame, displayID: saved.display, screens: screens) == nil {
                frame = Arrangement.defaultToolbar(on: primary, height: height)
            }
        } else { frame = Arrangement.defaultToolbar(on: primary, height: height) }
        let screen = toolbarScreen(frame, screens: screens) ?? primary
        let clamped = Arrangement.clampToolbar(frame, to: screen)
        let rect = NSRect(x: clamped.x, y: clamped.y, width: clamped.width, height: clamped.height)
        if rect != toolbar.panel.frame { toolbar.panel.setFrame(rect, display: true) }
        if hint.isVisible { positionHint() }
    }
    /// Menu bar recovery: back onto a connected display and in front.
    func revealToolbar() {
        placeToolbar()
        toolbar.panel.orderFrontRegardless()
        if state.targetsCollapsed { showHint() }
    }
    func screensChanged() { placeToolbar() }
    private func toolbarScreen(_ frame: NoteFrame, screens: [DockScreen]) -> DockScreen? {
        screens.first { DockGeometry.contains($0.visible, x: frame.x + frame.width / 2, y: frame.y + frame.height / 2) }
    }
    private var toolbarFrame: NoteFrame {
        let f = toolbar.panel.frame
        return NoteFrame(x: f.minX, y: f.minY, width: f.width, height: f.height)
    }
    private func toolbarMoved(_ frame: NSRect) {
        let note = NoteFrame(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
        let screen = toolbarScreen(note, screens: DockController.screens())
        defaults.toolbar = .init(x: frame.minX, y: frame.maxY, display: screen?.persistentID)
        if hint.isVisible { positionHint() }
    }

    // MARK: Stack hint

    private func positionHint() {
        let screens = DockController.screens()
        guard let screen = toolbarScreen(toolbarFrame, screens: screens) ?? screens.first else { return }
        let f = Arrangement.stackHint(beside: toolbarFrame, width: StackHint.size.width, height: StackHint.size.height, screen: screen)
        hint.setFrame(NSRect(x: f.x, y: f.y, width: f.width, height: f.height), display: true)
    }
    private func showHint() {
        guard !notes.isEmpty || surfaces()?.panels.isEmpty == false else { return }
        hint.show(colors: notes.map(\.color), count: notes.count)
        positionHint()
        if hint.parent == nil { toolbar.panel.addChildWindow(hint, ordered: .above) }
        hint.alphaValue = 0; hint.orderFrontRegardless()
        Motion.windows([(hint, hint.frame, 1)], duration: MotionPolicy.gathering) {}
    }
    private func hideHint() {
        if hint.parent != nil { toolbar.panel.removeChildWindow(hint) }
        hint.orderOut(nil)
    }
    private var hintCenter: NSPoint {
        if !hint.isVisible { positionHint() }
        return NSPoint(x: hint.frame.midX, y: hint.frame.midY)
    }
    private func centered(_ size: NSSize, at center: NSPoint) -> NSRect {
        NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }

    // MARK: Collapse / expand

    func toggleCollapse() { state.targetsCollapsed ? expand() : collapse() }

    func collapse() {
        guard !state.targetsCollapsed, !notes.isEmpty, let surfaces = surfaces() else { return }
        guard canMutate() else { failure(StoreError.invalid("请先完成输入法组词，再收起便签")); return }
        do { try surfaces.flushEdits() } catch { failure(error); return }
        let reversing = state == .expanding
        state = .collapsing; defaults.collapsed = true
        generation += 1; let token = generation
        docking()?.suppressed = true
        refresh(.layout) // closes dock overflow tabs; suppressed panels stay hidden
        let center = hintCenter
        showHint()
        var moves: [(NSWindow, NSRect, CGFloat)] = []
        for (id, panel) in surfaces.panels where !panel.suppressed && panel.isVisible {
            // Reversing an expand: the destination it was heading to is where the note rests.
            let rest = (reversing ? resting[id] : nil) ?? panel.restingFrame ?? panel.frame
            resting[id] = rest
            panel.ignoresMouseEvents = true
            moves.append((panel, centered(rest.size, at: center), 0))
        }
        updateToolbar()
        Motion.windows(moves, duration: MotionPolicy.gathering) { [weak self] in
            guard let self, self.generation == token, let surfaces = self.surfaces() else { return }
            for (id, panel) in surfaces.panels {
                panel.suppressed = true
                if let rest = self.resting[id] { panel.setFrame(rest, display: false) }
                panel.alphaValue = 1; panel.ignoresMouseEvents = false
            }
            self.resting = [:]; self.state = .collapsed; self.updateToolbar()
        }
    }

    /// Restores every note where it was, with its own folding and level. Never arranges.
    func expand() {
        guard state.targetsCollapsed, let surfaces = surfaces() else { return }
        let reversing = state == .collapsing
        let center = hintCenter
        state = .expanding; defaults.collapsed = false
        generation += 1; let token = generation
        docking()?.suppressed = false
        hideHint()
        var moves: [(NSWindow, NSRect, CGFloat)] = []
        for (id, panel) in surfaces.panels where pageVisible(id) {
            let rest = (reversing ? resting[id] : nil) ?? panel.restingFrame ?? panel.frame
            resting[id] = rest
            if panel.suppressed || !panel.isVisible {
                panel.alphaValue = 0
                panel.setFrame(Motion.reduced ? rest : centered(rest.size, at: center), display: false)
                panel.suppressed = false; panel.orderFrontRegardless()
            }
            panel.ignoresMouseEvents = false
            moves.append((panel, rest, 1))
        }
        updateToolbar()
        Motion.windows(moves, duration: MotionPolicy.gathering) { [weak self] in
            guard let self, self.generation == token else { return }
            self.resting = [:]; self.state = .expanded
            self.refresh(.layout) // dock strips and their tabs come back
            self.updateToolbar()
        }
    }

    // MARK: Arrange

    func arrange() {
        guard !notes.isEmpty, let surfaces = surfaces() else { return }
        guard canMutate() else { failure(StoreError.invalid("请先完成输入法组词，再整理便签")); return }
        let collapsed = state.targetsCollapsed
        do {
            let screens = DockController.screens()
            let preferred = try actions.store.settings().displayID
            let cards = try actions.store.notes().compactMap { note -> Arrangement.Card? in
                let screen: DockScreen?
                switch note.placement {
                case .free(let display, let x, let y, let w, let h):
                    screen = Arrangement.screen(for: NoteFrame(x: x, y: y, width: w, height: h), displayID: display, screens: screens)
                case .dock(_, let display):
                    screen = DockGeometry.screen(display, screens: screens, preferred: preferred)
                }
                guard let screen else { return nil }
                let content = (surfaces.panels[note.id]?.contentView as? NoteCardView)?.preferredHeight(width: NoteMetrics.width) ?? 120
                let stored = note.placement.freeFrame?.height ?? note.freeRestore?.freeFrame?.height ?? 200
                let expanded = min(screen.available.height, note.automaticHeight ? NoteFrame.automaticHeight(content: content) : stored)
                return Arrangement.Card(id: note.id, screen: screen.id,
                                        presentedHeight: note.collapsed ? NoteMetrics.collapsedHeight : expanded, expandedHeight: expanded)
            }
            let slots = Arrangement.plan(cards, screens: screens, toolbar: toolbarFrame,
                                         toolbarScreen: toolbarScreen(toolbarFrame, screens: screens)?.id)
            var before: [NoteID: NSRect] = [:]
            for (id, panel) in surfaces.panels where !panel.suppressed && panel.isVisible { before[id] = panel.frame }
            try actions.arrange(slots, screens: screens)
            pages = Dictionary(uniqueKeysWithValues: slots.filter { $0.pages > 1 }.map { ($0.id, (page: $0.page, pages: $0.pages)) })
            defaults.pages = pages; defaults.currentPage = 0
            refresh(.layout)
            if collapsed { resting = [:]; expand(); return }
            applyPages()
            var moves: [(NSWindow, NSRect, CGFloat)] = []
            for (id, from) in before {
                guard let panel = surfaces.panels[id], !panel.suppressed else { continue }
                let to = panel.frame
                guard to != from else { continue }
                panel.setFrame(from, display: false)
                moves.append((panel, to, 1))
            }
            Motion.windows(moves, duration: MotionPolicy.arrangement) {}
            updateToolbar()
        } catch { failure(error) }
    }

    private func turnPage(_ delta: Int) {
        guard let (current, total) = pageInfo else { return }
        defaults.currentPage = min(max(0, current + delta), total - 1)
        applyPages(); updateToolbar()
    }

    // MARK: New notes

    /// Next to the toolbar, avoiding visible notes. Expands first when collapsed.
    func newNoteFrame(height: Double) -> (NoteFrame, String?) {
        let screens = DockController.screens()
        guard let screen = toolbarScreen(toolbarFrame, screens: screens) ?? screens.first else {
            return (NoteFrame(x: 100, y: 100, width: NoteMetrics.width, height: height), nil)
        }
        let panels = surfaces()?.panels ?? [:]
        let occupied = panels.values.compactMap { panel -> NoteFrame? in
            guard !panel.suppressed, panel.isVisible else { return nil }
            let f = panel.restingFrame ?? panel.frame
            return NoteFrame(x: f.minX, y: f.minY, width: f.width, height: f.height)
        }
        let frame = Arrangement.placement(width: NoteMetrics.width, height: height, screen: screen, toolbar: toolbarFrame, occupied: occupied)
        return (frame, screen.persistentID)
    }
}
