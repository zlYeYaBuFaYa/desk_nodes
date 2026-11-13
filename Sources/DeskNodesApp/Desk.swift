import AppKit
import DeskNodesCore
import DeskNodesActions
import DeskNodesPersistence

/// Owns the resident toolbar and the desktop-wide presentation: global collapse,
/// all-topmost, "浮起", "整理" and its overflow pages. It never edits note content; geometry changes go
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
    /// Lets the status menu mirror the toolbar's 置顶 toggle.
    var topmostChanged: (Bool) -> Void = { _ in }
    /// The app activates on entry and watches for leaving (Esc, another app).
    var peekChanged: (Bool) -> Void = { _ in }
    /// "浮起" is session state: a relaunch always starts with notes at their own levels.
    private(set) var peeking = false
    /// The display the toolbar last resolved on, kept when the pointer leaves every display.
    private var toolbarDisplay: String?
    /// The reservation docked strips last saw; a change relays them out.
    private var reserved: NoteFrame?
    /// The hint is mid-fade with the toolbar's controls; a settled capsule leaves it alone.
    private var hintFollows = false

    init(actions: NoteActions, defaults: PresentationDefaults) {
        self.actions = actions; self.defaults = defaults
        state = DeskPresentation(collapsed: defaults.collapsed)
        pages = defaults.pages
        toolbar.released = { [weak self] visible, round, pointer in self?.toolbarReleased(visible, round: round, pointer: pointer) }
        toolbar.snapPreview = { [weak self] visible, round, pointer in
            self?.release(visible, round: round, pointer: pointer).flatMap { $0.1.edge == nil ? nil : NSRect($0.1.target) }
        }
        toolbar.presented = { [weak self] visible, controls in self?.toolbarPresented(visible, controls: controls) }
        toolbar.turnPage = { [weak self] delta in self?.turnPage(delta) }
        toolbar.autoShrink = defaults.toolbarAutoShrink
        toolbar.setOrientation(defaults.toolbarOrientation)
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

    // MARK: Topmost

    var topmost: Bool { defaults.topmost }
    func toggleTopmost() {
        endPeek() // the lasting toggle supersedes the temporary one
        defaults.topmost.toggle()
        applyTopmost()
        updateToolbar()
    }
    /// Pushes the saved toggle and the peek to the note windows; also after an import rebuilds them.
    func applyTopmost() {
        if let surfaces = surfaces() {
            var modes = surfaces.modes; modes.allTopmost = defaults.topmost; modes.peek = peeking
            surfaces.apply(modes)
        }
        topmostChanged(defaults.topmost)
    }

    // MARK: Peek

    /// Lifts every note above other apps, fullscreen ones included, until `endPeek`.
    /// The real notes come forward where they are: nothing is copied or moved.
    func togglePeek() { peeking ? endPeek() : beginPeek() }
    /// 置顶 already keeps every note in front; with no notes there is nothing to lift.
    var canPeek: Bool { !defaults.topmost && !notes.isEmpty }
    func beginPeek() {
        guard !peeking, canPeek else { return }
        if state.targetsCollapsed { expand() }
        peeking = true
        applyTopmost()
        for panel in (surfaces()?.panels ?? [:]).values where !panel.suppressed { panel.orderFrontRegardless() }
        updateToolbar(); peekChanged(true)
    }
    func endPeek() {
        guard peeking else { return }
        peeking = false
        applyTopmost(); updateToolbar(); peekChanged(false)
    }

    // MARK: Toolbar

    /// Launch shows the whole toolbar where it was, never the round entry; idle timing
    /// takes over from there.
    func start() {
        placeToolbar()
        toolbar.show()
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
        let paged = toolbar.paged
        if notes.isEmpty { endPeek() }
        toolbar.update(Toolbar.State(count: notes.count, peeking: peeking, canPeek: canPeek,
                                     collapsed: state.targetsCollapsed, topmost: defaults.topmost, page: pageInfo))
        // Only the pager changes the toolbar's length; re-solve from the same anchor.
        if toolbar.paged != paged { placeToolbar() }
    }
    /// Resolves the saved anchor on the current displays. Upgrading from a plain saved
    /// position keeps it as a free place; it is never treated as snapped by distance alone.
    func placeToolbar(animated: Bool = false) {
        let screens = DockController.screens()
        if defaults.toolbarAnchor == nil, let legacy = defaults.toolbar {
            let height = ToolbarMetrics.height(paged: false)
            defaults.toolbarAnchor = .free(centerX: legacy.x + ToolbarMetrics.width / 2, centerY: legacy.y - height / 2, display: legacy.display)
        }
        guard let frames = ToolbarGeometry.resolve(defaults.toolbarAnchor, orientation: defaults.toolbarOrientation,
                                                   paged: toolbar.paged, screens: screens) else { return }
        toolbarDisplay = frames.screen.id
        toolbar.place(Toolbar.Frames(frames), animated: animated)
        reservationChanged()
    }
    /// Menu bar recovery: back onto a connected display, fully expanded and in front.
    func revealToolbar() {
        placeToolbar()
        toolbar.panel.orderFrontRegardless()
        toolbar.expand()
        if state.targetsCollapsed { showHint() }
    }
    func screensChanged() { placeToolbar() }
    func setToolbarOrientation(_ orientation: ToolbarOrientation) {
        guard orientation != defaults.toolbarOrientation else { return }
        defaults.toolbarOrientation = orientation
        toolbar.setOrientation(orientation)
        placeToolbar(animated: true)
    }
    func setToolbarAutoShrink(_ seconds: Int) {
        defaults.toolbarAutoShrink = seconds
        toolbar.autoShrink = defaults.toolbarAutoShrink
    }
    private func toolbarScreen(_ frame: NoteFrame, screens: [DockScreen]) -> DockScreen? {
        screens.first { $0.id == toolbarDisplay }
            ?? screens.first { DockGeometry.contains($0.visible, x: frame.x + frame.width / 2, y: frame.y + frame.height / 2) }
    }
    /// The full expanded frame, even while the toolbar is shrunk to its entry: new notes,
    /// "整理" and docked strips keep clear of it.
    private var toolbarFrame: NoteFrame {
        NoteFrame(toolbar.frames?.target ?? toolbar.panel.frame)
    }
    /// What docked strips avoid on the toolbar's display.
    var toolbarReservation: (display: String, frame: NoteFrame)? {
        guard toolbar.frames != nil, let display = toolbarDisplay else { return nil }
        return (display, toolbarFrame)
    }
    /// Placement can be re-solved from inside a refresh (the pager appearing), so strips
    /// relay out on the next turn rather than re-entering it.
    private func reservationChanged() {
        guard toolbarFrame != reserved else { return }
        reserved = toolbarFrame
        DispatchQueue.main.async { [weak self] in self?.refresh(.layout) }
    }
    private func release(_ visible: NSRect, round: Bool, pointer: NSPoint) -> (ToolbarAnchor, ToolbarFrames)? {
        ToolbarGeometry.release(NoteFrame(visible), round: round, pointer: (pointer.x, pointer.y),
                                last: toolbarDisplay, previous: defaults.toolbarAnchor?.edge,
                                orientation: defaults.toolbarOrientation, paged: toolbar.paged, screens: DockController.screens())
    }
    private func toolbarReleased(_ visible: NSRect, round: Bool, pointer: NSPoint) -> Toolbar.Frames? {
        guard let (anchor, frames) = release(visible, round: round, pointer: pointer) else { return nil }
        defaults.toolbarAnchor = anchor
        toolbarDisplay = frames.screen.id
        let resolved = Toolbar.Frames(frames)
        DispatchQueue.main.async { [weak self] in self?.reservationChanged() } // after the toolbar holds `resolved`
        return resolved
    }
    /// The stack hint shows with the controls: hidden on the round entry, fading in and out
    /// with the controls during a transition, and following the capsule.
    private func toolbarPresented(_ visible: NSRect, controls: CGFloat) {
        guard state.targetsCollapsed, hint.parent != nil else { return }
        if controls > 0 { positionHint() }
        guard controls < 1 || hintFollows else { return }
        hintFollows = controls < 1
        hint.alphaValue = controls
        hint.ignoresMouseEvents = controls < 1
    }

    // MARK: Stack hint

    private func positionHint() {
        let screens = DockController.screens()
        guard let screen = toolbarScreen(toolbarFrame, screens: screens) ?? screens.first else { return }
        // Beside the capsule as it is on screen, which may be mid-snap.
        let beside = toolbar.isRound ? toolbarFrame : NoteFrame(toolbar.visibleFrame)
        let f = Arrangement.stackHint(beside: beside, width: StackHint.size.width, height: StackHint.size.height, screen: screen)
        let rect = NSRect(x: f.x, y: f.y, width: f.width, height: f.height)
        if hint.frame != rect { hint.setFrame(rect, display: true) }
    }
    private func showHint() {
        guard !notes.isEmpty || surfaces()?.panels.isEmpty == false else { return }
        hint.show(colors: notes.map(\.color), count: notes.count)
        positionHint()
        if hint.parent == nil { toolbar.panel.addChildWindow(hint, ordered: .above) }
        hint.alphaValue = 0; hint.orderFrontRegardless()
        // On the round entry the badge stands in; the hint returns with the controls.
        guard toolbar.shape == .expanded else { hint.ignoresMouseEvents = true; return }
        hint.ignoresMouseEvents = false
        Motion.windows([(hint, hint.frame, 1)], duration: MotionPolicy.gathering) {}
    }
    private func hideHint() {
        hintFollows = false
        if hint.parent != nil { toolbar.panel.removeChildWindow(hint) }
        hint.orderOut(nil)
    }
    /// Where gathered notes go and come from: the stack hint, or the round entry while shrunk.
    private var hintCenter: NSPoint {
        if toolbar.shape != .expanded { return NSPoint(x: toolbar.visibleFrame.midX, y: toolbar.visibleFrame.midY) }
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
        endPeek() // nothing stays lifted behind the stack
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
    func newNoteFrame(width: Double = NoteMetrics.width, height: Double) -> (NoteFrame, String?) {
        let screens = DockController.screens()
        guard let screen = toolbarScreen(toolbarFrame, screens: screens) ?? screens.first else {
            return (NoteFrame(x: 100, y: 100, width: width, height: height), nil)
        }
        let panels = surfaces()?.panels ?? [:]
        let occupied = panels.values.compactMap { panel -> NoteFrame? in
            guard !panel.suppressed, panel.isVisible else { return nil }
            let f = panel.restingFrame ?? panel.frame
            return NoteFrame(x: f.minX, y: f.minY, width: f.width, height: f.height)
        }
        let frame = Arrangement.placement(width: width, height: height, screen: screen, toolbar: toolbarFrame, occupied: occupied)
        return (frame, screen.persistentID)
    }
}

extension NoteFrame {
    init(_ rect: NSRect) { self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height) }
}
extension NSRect {
    init(_ frame: NoteFrame) { self.init(x: frame.x, y: frame.y, width: frame.width, height: frame.height) }
}
extension Toolbar.Frames {
    init(_ frames: ToolbarFrames) {
        self.init(target: NSRect(frames.target), circle: frames.circle.map(NSRect.init), edge: frames.edge)
    }
}
