import AppKit
import QuartzCore
import DeskNodesActions
import DeskNodesPersistence

/// The ONLY fullscreen auxiliary window. Nonactivating means hover never steals
/// focus; clicking an editor may make this panel key without activating the app.
final class RevealPanel: NSPanel, NSWindowDelegate {
    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        (client as? NoteTitleField)?.ownedEditor
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var beforeFocusLoss: (() -> Void)?
    override func resignKey() { beforeFocusLoss?(); super.resignKey() }
    var deletionUndo: (() -> Bool)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "z", deletionUndo?() == true { return true }
        return super.performKeyEquivalent(with: event)
    }
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        delegate = self
        isReleasedWhenClosed = false; isOpaque = false; backgroundColor = .clear
        hasShadow = true; hidesOnDeactivate = false; isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
}
private final class RevealList: NSView {
    var container = false
    override var isFlipped: Bool { true }
    func updateColors() {
        guard container else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer?.backgroundColor = NoteTheme.dynamic("F2F0EB", "242321").cgColor
            layer?.borderColor = NoteTheme.border.cgColor
            CATransaction.commit()
        }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
}

@MainActor
final class EdgeRevealController: NSObject {
    private let actions: NoteActions
    private let changed: () -> Void
    private let undo: () -> Bool
    private let restoreDeletion: () -> Bool
    private let failure: (Error) -> Void
    private let canMutate: () -> Bool
    private let panel = RevealPanel()
    private let root = RevealList()
    private let list = RevealList()
    private let scroll = NSScrollView()
    private let undoButton = NSButton(title: "撤销删除", target: nil, action: nil)
    private let heading = NSTextField(labelWithString: "DeskNodes")
    private var timer: Timer?
    private var fastPolling = false
    private var failing = false
    private var timing = RevealTiming()
    private var current: RevealTarget?
    private var generation = 0
    private var environmentRead = -Double.infinity
    private var preference = EdgePreference.automatic
    private var dockOrientation: String?
    private var topology: [DockScreen] = []
    private var topologyChanged = false
    private(set) var cards: [NoteID: NoteCardView] = [:]
    private var ordered: [NoteID] = []
    init(actions: NoteActions, changed: @escaping () -> Void, undo: @escaping () -> Bool, restoreDeletion: @escaping () -> Bool,
         canMutate: @escaping () -> Bool, failure: @escaping (Error) -> Void) {
        self.actions = actions; self.changed = changed; self.undo = undo; self.restoreDeletion = restoreDeletion
        self.canMutate = canMutate; self.failure = failure
        super.init()
        root.container = true; root.wantsLayer = true; root.layer?.borderWidth = 1; root.layer?.cornerRadius = 16; root.layer?.masksToBounds = true
        heading.textColor = NoteTheme.primary
        heading.font = .systemFont(ofSize: 12, weight: .semibold)
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.documentView = list
        undoButton.target = self; undoButton.action = #selector(undoClicked)
        undoButton.isBordered = false
        root.addSubview(undoButton); root.addSubview(heading); root.addSubview(scroll); panel.contentView = root
        panel.deletionUndo = undo
        panel.beforeFocusLoss = { [weak self] in
            guard let self, !self.hasMarkedComposition else { return }
            do { try self.flushEdits() } catch { self.failure(error) }
        }
        // Public position polling only: no event tap, global monitor or keyboard observation.
        // Idle sampling is slow; the 25ms cadence runs only while a dwell or the panel is active.
        schedule(fast: false)
    }
    private func schedule(fast: Bool) {
        guard timer == nil || fast != fastPolling else { return }
        timer?.invalidate()
        fastPolling = fast
        // Idle 10 Hz bounds dwell start latency to 0.1s (0.25s dwell -> at most 0.35s).
        let timer = Timer(timeInterval: fast ? 0.025 : 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = fast ? 0.005 : 0.02
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    func invalidateAfterImport() {
        stop(); generation += 1
        for card in cards.values { card.prepareForRemoval(); card.removeFromSuperview() }
        cards = [:]; ordered = []; panel.beforeFocusLoss = nil
        panel.undoManager?.removeAllActions(); panel.makeFirstResponder(nil); panel.orderOut(nil)
    }
    func stop() {
        timer?.invalidate(); timer = nil
    }
    var hasMarkedComposition: Bool { cards.values.contains { $0.hasMarkedComposition } }
    func flushEdits() throws { for card in cards.values { try card.flushRolloverEdits() } }
    func refresh(_ notes: [Note]) {
        let ids = Set(notes.map(\.id))
        for id in Array(cards.keys) where !ids.contains(id) {
            cards[id]?.prepareForRemoval(); cards.removeValue(forKey: id)?.removeFromSuperview()
        }
        ordered = notes.map(\.id)
        for note in notes {
            if let card = cards[note.id] { card.refresh(note) }
            else {
                let card = NoteCardView(note: note, actions: actions, changed: changed, undoDelete: undo, failure: failure, reveal: true)
                card.canMutate = canMutate
                cards[note.id] = card; list.addSubview(card)
            }
        }
        heading.stringValue = "DeskNodes · \(notes.count) 张便签"
        layout()
    }
    @objc private func undoClicked() { _ = restoreDeletion() }
    private func layout() {
        root.updateColors()
        heading.frame = NSRect(x: 16, y: 14, width: max(1, root.bounds.width - 32), height: 20)
        undoButton.frame = NSRect(x: root.bounds.width - 88, y: 12, width: 76, height: 24)
        undoButton.isHidden = !actions.canUndoDeletion
        scroll.frame = NSRect(x: 16, y: 46, width: max(1, root.bounds.width - 32), height: max(1, root.bounds.height - 60))
        var y: CGFloat = 0
        for id in ordered {
            guard let card = cards[id] else { continue }
            let height = max(100, card.preferredHeight(width: scroll.contentSize.width))
            card.frame = NSRect(x: 0, y: y, width: scroll.contentSize.width, height: height)
            y += height + 12
        }
        list.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(scroll.contentSize.height, y))
    }
    private func poll() {
        guard timer != nil else { return } // stopped
        do {
            let screens = NSScreen.screens.enumerated().map { index, screen in
                DockScreen(id: "display-\((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? String(index))", visible: NoteFrame(x: screen.frame.minX, y: screen.frame.minY,
                    width: screen.frame.width, height: screen.frame.height))
            }
            let now = ProcessInfo.processInfo.systemUptime
            if now < environmentRead || now >= environmentRead + 1 {
                preference = try actions.store.settings().edgePreference
                // Read only a nonsensitive public preference. Unknown/missing -> right.
                dockOrientation = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation")
                environmentRead = now
            }
            undoButton.isHidden = !actions.canUndoDeletion
            let point = NSEvent.mouseLocation
            // Dragging a scrollbar, selection or window against the edge is not a request to reveal.
            let target = NSEvent.pressedMouseButtons != 0 && current == nil ? nil
                : RevealGeometry.target(x: point.x, y: point.y, screens: screens, side: preference.resolved(dock: dockOrientation))
            if current != nil && topology != screens { topologyChanged = true }
            topology = screens
            // Only a shown panel can hold a composition; skip the view walk while idle.
            let composing = (current != nil || panel.isVisible) && hasMarkedComposition
            // Never hide a composing panel, even during display removal. Once
            // composition ends, close and require a fresh dwell on the new topology.
            if topologyChanged && !composing {
                timing.reset(); topologyChanged = false
            }
            let next = timing.sample(time: now, target: target,
                inside: panel.isVisible && panel.frame.contains(point), editing: composing || panel.attachedSheet != nil)
            if next != current {
                if let next, let screen = screens.first(where: { $0.id == next.screen }) {
                    present(next, screen: screen)
                } else if !composing {
                    try flushEdits()
                    panel.makeFirstResponder(nil)
                    hide()
                }
                current = next
            }
            failing = false
            schedule(fast: !timing.isIdle || current != nil || topologyChanged)
        } catch {
            // Transient (e.g. SQLITE_BUSY): keep sampling with the last good settings and
            // report once per failure streak instead of disabling edge reveal for good.
            if !failing { failing = true; failure(error) }
            environmentRead = ProcessInfo.processInfo.systemUptime
        }
    }
    private func present(_ target: RevealTarget, screen: DockScreen) {
        generation += 1
        let f = screen.visible, width = min(272, max(1, f.width - 16))
        let frame = NSRect(x: target.side == .left ? f.x + 8 : f.x + f.width - width - 8,
                          y: f.y + 12, width: width, height: max(1, f.height - 24))
        panel.setFrame(frame, display: false); root.frame = NSRect(origin: .zero, size: frame.size)
        root.layer?.removeAllAnimations(); layout(); panel.orderFrontRegardless()
        animate(open: true, side: target.side)
    }
    private func hide() {
        generation += 1; let token = generation
        animate(open: false, side: current?.side ?? .right)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { panel.orderOut(nil); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
            guard let self, self.generation == token else { return }
            self.panel.orderOut(nil); self.root.layer?.removeAllAnimations()
        }
    }
    private func animate(open: Bool, side: RevealSide) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = root.layer else { return }
        layer.removeAllAnimations()
        let offset = side == .left ? -24.0 : 24.0
        let spring = CASpringAnimation(keyPath: "transform.translation.x")
        spring.fromValue = open ? offset : 0; spring.toValue = open ? 0 : offset
        spring.stiffness = 300; spring.damping = 27; spring.duration = 0.30
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = open ? 0 : 1; fade.toValue = open ? 1 : 0; fade.duration = 0.30
        if !open { for animation in [spring, fade] { animation.fillMode = .forwards; animation.isRemovedOnCompletion = false } }
        layer.add(spring, forKey: "edgeSlide"); layer.add(fade, forKey: "edgeFade")
    }
}
