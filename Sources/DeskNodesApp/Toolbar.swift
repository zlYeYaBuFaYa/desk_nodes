import AppKit
import QuartzCore
import DeskNodesCore
import DeskNodesActions
import DeskNodesPersistence

/// The resident toolbar never becomes key or activates the app: arranging or collapsing
/// leaves keyboard focus where it was. Actions that need typing activate explicitly.
final class ToolbarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// Any press or scroll on the toolbar: it counts as use, so idle timing starts over.
    var interacted: () -> Void = {}
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: ToolbarMetrics.width, height: ToolbarMetrics.height(paged: false)),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false; isOpaque = false; backgroundColor = .clear; hasShadow = true
        hidesOnDeactivate = false; isFloatingPanel = true; level = .floating; isMovable = false
        acceptsMouseMovedEvents = true
        // Above ordinary windows on every desktop and over fullscreen apps, so "取消置顶"
        // stays reachable wherever topmost notes are showing.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        title = "DeskNodes 工具条"
    }
    override func sendEvent(_ event: NSEvent) {
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel].contains(event.type) { interacted() }
        super.sendEvent(event)
    }
}

/// The capsule toolbar and, while snapped to an edge, its round entry. Placement is owned
/// by `DesktopController`; this class owns the shape, its motion, hit testing and idle timing.
///
/// Every frame is drawn from one state: the shell's screen rect plus the entry icon's and the
/// controls' opacity. Interrupting a transition simply starts the next one from that state.
@MainActor
final class Toolbar {
    enum Action: Int { case create, delete, arrange, collapse, topmost, settings }
    enum Shape: Equatable { case expanded, collapsing, round, expanding }
    /// Resolved rest frames in screen points. `circle` exists only while snapped.
    struct Frames: Equatable {
        var target: NSRect
        var circle: NSRect?
        var edge: ToolbarEdge?
    }

    let panel = ToolbarPanel()
    private let root = ToolbarRoot()
    var perform: (Action) -> Void = { _ in }
    var turnPage: (Int) -> Void = { _ in }
    /// A drag ended with `visible` on screen; the owner stores and returns the new rest frames.
    var released: (_ visible: NSRect, _ round: Bool, _ pointer: NSPoint) -> Frames? = { _, _, _ in nil }
    /// While dragging: where a release now would snap the capsule, or nil when it would stay free.
    var snapPreview: (_ visible: NSRect, _ round: Bool, _ pointer: NSPoint) -> NSRect? = { _, _, _ in nil }
    private let preview = SnapPreview()
    /// Each drawn frame: the visible shape and how visible the controls are (0–1).
    var presented: (_ visible: NSRect, _ controls: CGFloat) -> Void = { _, _ in }
    /// Idle blockers owned elsewhere, such as a visible settings window.
    var busy: () -> Bool = { false }
    /// Seconds before a snapped, idle toolbar shrinks; 0 is off.
    var autoShrink = ToolbarMetrics.defaultAutoShrink {
        didSet {
            if autoShrink == 0 && (shape == .round || shape == .collapsing) { expand() }
            restartIdle()
        }
    }
    private(set) var paged = false
    private(set) var frames: Frames?
    private(set) var shape: Shape = .expanded
    var buttons: [ToolbarButton] { root.content.buttons }
    var orientation: ToolbarOrientation { root.content.orientation }

    private var shell = NSRect.zero
    private var iconAlpha: CGFloat = 0
    private var controlsAlpha: CGFloat = 1
    private var badge: Int?
    private var animation: Transition?
    private var link: CADisplayLink?
    private lazy var linkTarget = FrameLink { [weak self] in self?.tick() }
    /// A press on the grip or the entry; it owns the pointer until release.
    private var gesture = false
    private var idleTimer: Timer?
    /// Looks at the pointer while it rests on the toolbar, so the wait never hinges on an
    /// exit event that may not come (a window can move out from under a still pointer).
    private var pointerCheck: Timer?
    private var intentTimer: Timer?
    /// Opened by hovering and not used yet: leaving shrinks it after a short grace.
    private var hoverOpened = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var voiceOver: NSKeyValueObservation?

    init() {
        panel.contentView = root
        root.owner = self
        root.content.grip.pressed = { [weak self] in self?.track(activate: false) }
        for (index, button) in root.content.buttons.enumerated() {
            button.target = self; button.action = #selector(clicked(_:)); button.tag = index
        }
        root.content.pager.turn = { [weak self] delta in self?.turnPage(delta) }
        root.entry.activate = { [weak self] in self?.expand() }
        panel.interacted = { [weak self] in self?.interacted() }
        observe()
    }
    @objc private func clicked(_ sender: ToolbarButton) {
        guard let action = Action(rawValue: sender.tag) else { return }
        perform(action)
        restartIdle()
    }

    struct State: Equatable {
        var count = 0
        var canDelete = false
        var collapsed = false
        var topmost = false
        /// (current, total) while an arrangement overflows.
        var page: (Int, Int)? = nil
        static func == (a: Self, b: Self) -> Bool {
            a.count == b.count && a.canDelete == b.canDelete && a.collapsed == b.collapsed && a.topmost == b.topmost
                && a.page?.0 == b.page?.0 && a.page?.1 == b.page?.1
        }
    }
    private var state: State?
    /// Refreshes labels and the pager. A pager change alters the target size; the owner
    /// re-resolves frames when `paged` flips.
    func update(_ new: State) {
        guard new != state else { return }
        state = new
        let view = root.content, empty = new.count == 0
        view.buttons[Action.delete.rawValue].isEnabled = new.canDelete
        view.buttons[Action.arrange.rawValue].isEnabled = !empty
        let collapse = view.buttons[Action.collapse.rawValue]
        collapse.isEnabled = !empty
        collapse.symbol = new.collapsed ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left"
        collapse.label = new.collapsed ? "展开" : "收起"
        collapse.help = new.collapsed ? "展开全部便签，恢复到收起前的位置" : "把全部便签收拢到工具条旁"
        let topmost = view.buttons[Action.topmost.rawValue]
        topmost.isOn = new.topmost
        topmost.symbol = new.topmost ? "pin.slash" : "pin"
        topmost.label = new.topmost ? "取消置顶" : "置顶"
        topmost.help = new.topmost ? "便签恢复各自的层级" : "全部便签显示在其他应用上方，包括全屏应用"
        view.count.stringValue = "\(new.count) 张便签"
        view.count.setAccessibilityLabel("当前共 \(new.count) 张便签")
        view.pager.isHidden = new.page == nil
        if let page = new.page { view.pager.show(current: page.0, total: page.1) }
        paged = new.page != nil
        view.needsLayout = true
        // The count badge appears beside the entry only while notes are gathered.
        badge = new.collapsed && new.count > 0 ? new.count : nil
        root.badge.text = badge.map { $0 > 99 ? "99+" : "\($0)" } ?? ""
        render()
    }

    func setOrientation(_ orientation: ToolbarOrientation) {
        guard orientation != root.content.orientation else { return }
        // The old layout must not be seen in the new shape: controls return once it settles.
        if shape == .expanded || shape == .expanding { controlsAlpha = 0 }
        root.content.orientation = orientation
    }

    // MARK: Placement

    /// New rest frames from the owner (start, drag release, orientation, pager or display
    /// change). A round toolbar stays round and only moves; it is never woken by this.
    /// Without animation (display changes, the pager) a running transition settles at once,
    /// so the toolbar never keeps moving from a place that is no longer valid.
    func place(_ new: Frames, animated: Bool) {
        frames = new
        guard !gesture else { return } // the release re-resolves with the latest state
        let round = (shape == .round || shape == .collapsing) && new.circle != nil
        if !animated || Motion.reduced || shape == .round && round { settle(round ? .round : .expanded) }
        else if round { collapse(force: true) }
        else if !(shape == .expanded && animation == nil && shell == new.target) { expand(force: true) }
        restartIdle()
    }
    private func settle(_ end: Shape) {
        guard let frames else { return }
        stopAnimation()
        shape = end
        shell = end == .round ? frames.circle ?? frames.target : frames.target
        iconAlpha = end == .round ? 1 : 0; controlsAlpha = end == .round ? 0 : 1
        render()
    }
    /// Shows the full toolbar at once, without motion; used on launch.
    func show() {
        settle(.expanded); panel.orderFrontRegardless(); restartIdle()
    }

    // MARK: Shape transitions

    func expand(hover: Bool = false, force: Bool = false) {
        guard let frames else { return }
        hoverOpened = hover
        cancelIntent()
        if !force {
            if shape == .expanding { return } // repeated activation keeps the running target
            if shape == .expanded && animation == nil && shell == frames.target { restartIdle(); return }
        }
        shape = .expanding
        start(.expand(from: shell, to: frames.target, circle: frames.circle, icon: iconAlpha, controls: controlsAlpha))
    }
    func collapse(force: Bool = false) {
        guard let frames, let circle = frames.circle else { return }
        guard force || shape == .expanded || shape == .expanding else { return }
        hoverOpened = false
        shape = .collapsing
        start(.collapse(from: shell, to: circle, target: frames.target, icon: iconAlpha, controls: controlsAlpha))
    }
    private func start(_ transition: Transition) {
        cancelIdle()
        animation = transition
        if link == nil {
            let link = root.displayLink(target: linkTarget, selector: #selector(FrameLink.step(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
        tick()
    }
    private func stopAnimation() {
        animation = nil
        link?.invalidate(); link = nil
    }
    private func tick() {
        guard let transition = animation else { stopAnimation(); return }
        let t = CACurrentMediaTime() - transition.began
        shell = transition.shell(at: t)
        iconAlpha = transition.icon.value(at: t)
        controlsAlpha = transition.controls.value(at: t)
        if t >= transition.duration {
            stopAnimation()
            shape = shape == .collapsing ? .round : .expanded
            render()
            restartIdle()
        } else { render() }
    }

    // MARK: Drawing

    private var badgeFrame: NSRect? {
        guard badge != nil, iconAlpha > 0 else { return nil }
        let size = root.badge.fittingSize
        let inward: CGFloat = frames?.edge == .right ? -1 : 1
        let down = frames?.edge == .top
        // Over the entry's corner that faces into the display.
        let x = inward > 0 ? shell.maxX - size.width + 8 : shell.minX - 8
        let y = down ? shell.minY - 6 : shell.maxY - size.height + 6
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
    private func render() {
        guard let frames else { return }
        let badgeRect = badgeFrame
        var window = animation?.window ?? shell
        if let badgeRect { window = window.union(badgeRect) }
        // Controls ride along with the shell only once it has the capsule's size.
        let capsule = shell.size == frames.target.size
        let controls = NSRect(origin: capsule ? shell.origin : frames.target.origin, size: frames.target.size)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if panel.frame != window { panel.setFrame(window, display: false) }
        root.frame = NSRect(origin: .zero, size: window.size)
        root.arrange(shell: shell.offsetBy(dx: -window.minX, dy: -window.minY),
                     controls: controls.offsetBy(dx: -window.minX, dy: -window.minY), controlsAlpha: capsule ? controlsAlpha : 0,
                     badge: badgeRect?.offsetBy(dx: -window.minX, dy: -window.minY), iconAlpha: iconAlpha)
        root.interactive = shape == .expanded && animation == nil && !gesture
        CATransaction.commit()
        root.displayIfNeeded()
        panel.invalidateShadow()
        presented(shell, capsule ? controlsAlpha : 0)
    }
    /// The visible stadium and badge, in screen points: the only area that takes the pointer.
    func contains(_ point: NSPoint) -> Bool {
        let radius = min(shell.width, shell.height) / 2
        if NSBezierPath(roundedRect: shell, xRadius: radius, yRadius: radius).contains(point) { return true }
        return badgeFrame?.contains(point) ?? false
    }
    var visibleFrame: NSRect { shell }
    var isRound: Bool { shape == .round }

    // MARK: Pointer

    /// Tracking-area callback: entering, moving in or leaving the toolbar's window.
    func pointerChanged() {
        if contains(NSEvent.mouseLocation) {
            reconsiderIdle()
            if shape == .collapsing && !gesture { expand() }
            else if shape == .round && intentTimer == nil { armIntent(ToolbarMetrics.hoverIntent) }
        } else {
            cancelIntent()
            restartIdle()
        }
    }
    /// Expands after a dwell. A button held down elsewhere (another app's drag passing over)
    /// keeps waiting; the entry opens only if the pointer is still on it after release.
    private func armIntent(_ delay: TimeInterval) {
        intentTimer?.invalidate()
        intentTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.intentTimer = nil
                guard self.shape == .round, !self.gesture, self.panel.frame.contains(NSEvent.mouseLocation) else { return }
                if NSEvent.pressedMouseButtons != 0 || !self.contains(NSEvent.mouseLocation) { self.armIntent(0.1) }
                else { self.expand(hover: true) }
            }
        }
    }
    private func cancelIntent() { intentTimer?.invalidate(); intentTimer = nil }
    private func interacted() {
        hoverOpened = false
        cancelIdle()
    }

    /// One press on the grip (`activate == false`) or on the entry and its transition.
    /// The press is locked to this gesture: the motion pauses, travel past the threshold
    /// drags the visible shape, and the release never reaches a button that appeared under it.
    func track(activate: Bool) {
        gesture = true
        cancelIntent(); cancelIdle()
        animation = nil; link?.invalidate(); link = nil
        render()
        let start = NSEvent.mouseLocation, origin = shell.origin
        var dragging = false
        while let next = panel.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let point = NSEvent.mouseLocation
            if !dragging && max(abs(point.x - start.x), abs(point.y - start.y)) >= ToolbarMetrics.dragThreshold {
                dragging = true; NSCursor.closedHand.push()
            }
            if dragging {
                var moved = NSRect(origin: NSPoint(x: origin.x + point.x - start.x, y: origin.y + point.y - start.y), size: shell.size)
                // The shape never leaves the display under the pointer.
                let screens = DockController.screens()
                if let screen = screens.first(where: { DockGeometry.contains($0.visible, x: point.x, y: point.y) }) ?? screens.first {
                    let clamped = Arrangement.clampToolbar(NoteFrame(x: moved.minX, y: moved.minY, width: moved.width, height: moved.height), to: screen)
                    moved.origin = NSPoint(x: clamped.x, y: clamped.y)
                }
                if moved != shell { shell = moved; render() }
                preview.show(snapPreview(shell, shape != .expanded, point), below: panel)
            }
            if next.type == .leftMouseUp { break }
        }
        preview.orderOut(nil)
        if dragging { NSCursor.pop() }
        gesture = false
        if dragging, let frames = released(shell, shape != .expanded, NSEvent.mouseLocation) { self.frames = frames }
        if dragging || activate || shape != .expanded { expand(force: true) } else { render(); restartIdle() }
    }

    // MARK: Idle shrink

    /// Every condition but the pointer's position.
    private var idleEligible: Bool {
        shape == .expanded && animation == nil && !gesture && frames?.edge != nil && autoShrink > 0
            && panel.isVisible && !busy() && !NSWorkspace.shared.isVoiceOverEnabled
    }
    private var idleAllowed: Bool { idleEligible && !contains(NSEvent.mouseLocation) }
    private func cancelIdle() {
        idleTimer?.invalidate(); idleTimer = nil
        pointerCheck?.invalidate(); pointerCheck = nil
    }
    /// Starts a full wait when every condition holds and none is running; cancels otherwise.
    /// With only the pointer in the way, it checks the pointer again every half second.
    func reconsiderIdle() {
        guard idleEligible else { cancelIdle(); return }
        if contains(NSEvent.mouseLocation) {
            idleTimer?.invalidate(); idleTimer = nil
            guard pointerCheck == nil else { return }
            pointerCheck = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.idleEligible || !self.contains(NSEvent.mouseLocation) else { return }
                    self.pointerCheck?.invalidate(); self.pointerCheck = nil
                    self.reconsiderIdle()
                }
            }
            return
        }
        pointerCheck?.invalidate(); pointerCheck = nil
        guard idleTimer == nil else { return }
        let delay = hoverOpened ? ToolbarMetrics.hoverGrace : TimeInterval(autoShrink)
        idleTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.idleTimer = nil
                // Check again at expiry: never trust the last enter/exit event.
                if self.idleAllowed { self.collapse() } else { self.reconsiderIdle() }
            }
        }
    }
    func restartIdle() {
        cancelIdle()
        reconsiderIdle()
    }
    private func observe() {
        let center = NotificationCenter.default, workspace = NSWorkspace.shared.notificationCenter
        // Another window opening or closing (settings among them) can block or release the wait.
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification] {
            observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.reconsiderIdle() } }
            }))
        }
        // Sleep cancels the wait; waking starts over rather than shrinking for time spent asleep.
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelIdle(); self?.cancelIntent() }
        }))
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartIdle() }
        }))
        voiceOver = NSWorkspace.shared.observe(\.isVoiceOverEnabled) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.restartIdle() } }
        }
    }
    /// Removes observers, timers and the frame link; the toolbar lives for the whole app,
    /// so this is for tests and teardown.
    func invalidate() {
        for (center, token) in observers { center.removeObserver(token) }
        observers = []; voiceOver = nil
        cancelIdle(); cancelIntent(); stopAnimation(); preview.orderOut(nil)
    }
}

/// A shape transition as timed tracks, built from the current state so an interrupted
/// transition continues from what is on screen. The shell moves in a straight line with
/// ease-in-out timing; the controls only show over a settled capsule.
private struct Transition {
    struct Track {
        var segments: [(start: Double, duration: Double, from: CGFloat, to: CGFloat)] = []
        var initial: CGFloat
        func value(at t: Double) -> CGFloat {
            var value = initial
            for s in segments where t >= s.start {
                let p = s.duration <= 0 ? 1 : min(1, (t - s.start) / s.duration)
                value = s.from + (s.to - s.from) * CGFloat(p)
            }
            return value
        }
        var end: Double { segments.map { $0.start + $0.duration }.max() ?? 0 }
    }
    let began = CACurrentMediaTime()
    var from: NSRect, to: NSRect
    var shellStart: Double, shellDuration: Double
    var icon: Track, controls: Track
    /// Fixed window for the whole transition when the size changes: the union of both
    /// shapes, released as soon as the transition ends. A plain move follows the shell.
    var window: NSRect?
    var duration: Double { max(shellStart + shellDuration, icon.end, controls.end) }

    func shell(at t: Double) -> NSRect {
        let raw = shellDuration <= 0 ? (t >= shellStart ? 1 : 0) : min(1, max(0, (t - shellStart) / shellDuration))
        let p = raw < 0.5 ? 2 * raw * raw : 1 - pow(-2 * raw + 2, 2) / 2
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * CGFloat(p) }
        return NSRect(x: mix(from.minX, to.minX), y: mix(from.minY, to.minY),
                      width: mix(from.width, to.width), height: mix(from.height, to.height))
    }

    private static let shellPhase = MotionPolicy.toolbarMorph - 0.08 // 180ms of the 260
    private static let fade = 0.08
    /// How much of a full entry↔capsule change remains, so a reversal takes only what is left.
    private static func remaining(_ from: NSRect, _ to: NSRect, full: NSRect?) -> Double {
        func distance(_ a: NSRect, _ b: NSRect) -> CGFloat {
            max(abs(a.minX - b.minX), abs(a.minY - b.minY), abs(a.maxX - b.maxX), abs(a.maxY - b.maxY))
        }
        let total = full.map { distance($0, to) } ?? 0
        let left = distance(from, to)
        guard left > 0.5 else { return 0 }
        return total > 0.5 ? min(1, Double(left / total)) : 1
    }

    @MainActor static func expand(from: NSRect, to: NSRect, circle: NSRect?, icon: CGFloat, controls: CGFloat) -> Transition {
        let reduced = Motion.reduced
        let resize = from.size != to.size
        var iconTrack = Track(initial: icon), controlsTrack = Track(initial: controls)
        if !resize {
            // Snap or move of the capsule: controls stay, the window travels with it.
            let move = from == to ? 0 : (reduced ? 0 : MotionPolicy.toolbarSnap)
            if icon > 0 { iconTrack.segments.append((0, Double(icon) * 0.1, icon, 0)) }
            if controls < 1 { controlsTrack.segments.append((move, reduced ? MotionPolicy.reducedFade : fade * Double(1 - controls), controls, 1)) }
            return Transition(from: from, to: to, shellStart: 0, shellDuration: move, icon: iconTrack, controls: controlsTrack, window: nil)
        }
        let shell = reduced ? 0 : shellPhase * remaining(from, to, full: circle)
        // Controls laid out for another size cannot be shown while the shell changes.
        let pre = controls > 0 && !reduced ? fade * Double(controls) : 0
        if controls > 0 { controlsTrack.segments.append((0, pre, controls, 0)) }
        if icon > 0 { iconTrack.segments.append((pre, reduced ? MotionPolicy.reducedFade : min(0.1, max(shell, 0.04)), icon, 0)) }
        controlsTrack.segments.append((pre + shell, reduced ? MotionPolicy.reducedFade : fade, 0, 1))
        return Transition(from: from, to: to, shellStart: pre, shellDuration: shell, icon: iconTrack, controls: controlsTrack,
                          window: from.union(to))
    }
    @MainActor static func collapse(from: NSRect, to: NSRect, target: NSRect, icon: CGFloat, controls: CGFloat) -> Transition {
        let reduced = Motion.reduced
        var iconTrack = Track(initial: icon), controlsTrack = Track(initial: controls)
        let pre = controls > 0 ? (reduced ? MotionPolicy.reducedFade : fade * Double(controls)) : 0
        if controls > 0 { controlsTrack.segments.append((0, pre, controls, 0)) }
        let shell = reduced ? 0 : shellPhase * remaining(from, to, full: target)
        let fadeIn = reduced ? MotionPolicy.reducedFade : 0.1
        if icon < 1 { iconTrack.segments.append((pre + max(0, shell - fadeIn), fadeIn * Double(1 - icon), icon, 1)) }
        return Transition(from: from, to: to, shellStart: pre, shellDuration: shell, icon: iconTrack, controls: controlsTrack,
                          window: from.union(to))
    }
}

/// Outline of where a release would snap, shown under the dragged toolbar so the user can
/// tell "on the edge" from "near it" before letting go.
final class SnapPreview: NSPanel {
    private let outline = SnapOutline()
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isReleasedWhenClosed = false; isOpaque = false; backgroundColor = .clear; hasShadow = false
        ignoresMouseEvents = true; hidesOnDeactivate = false; level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        contentView = outline
        setAccessibilityElement(false)
    }
    override var canBecomeKey: Bool { false }
    func show(_ frame: NSRect?, below toolbar: NSWindow) {
        guard let frame else { orderOut(nil); return }
        if self.frame != frame { setFrame(frame, display: true) }
        if !isVisible { order(.below, relativeTo: toolbar.windowNumber) }
    }
}

private final class SnapOutline: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1), radius = min(rect.width, rect.height) / 2
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NoteTheme.accent.withAlphaComponent(0.14).setFill(); path.fill()
        path.lineWidth = 1.5; path.setLineDash([5, 4], count: 2, phase: 0)
        NoteTheme.accent.withAlphaComponent(0.8).setStroke(); path.stroke()
    }
}

/// CADisplayLink needs an Objective-C target.
private final class FrameLink: NSObject {
    private let action: () -> Void
    init(_ action: @escaping @MainActor () -> Void) { self.action = { MainActor.assumeIsolated { action() } } }
    @objc func step(_ link: CADisplayLink) { action() }
}

/// The window's content: the shell (background, border and rounded outline), the controls,
/// the round entry's icon and its count badge, each placed by `Toolbar.render`. Outside the
/// visible shape it takes no events.
final class ToolbarRoot: NSView {
    weak var owner: Toolbar?
    let shell = NSView()
    let content = ToolbarView()
    let entry = ToolbarEntry()
    let badge = ToolbarBadge()
    /// Stable, fully expanded and not in a gesture: only then do the controls take presses.
    var interactive = true
    private var tracking: NSTrackingArea?
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        shell.wantsLayer = true; shell.layer?.masksToBounds = true; shell.layer?.borderWidth = 0.5
        [shell, content, entry, badge].forEach { addSubview($0) }
        colors()
    }
    required init?(coder: NSCoder) { fatalError() }
    func arrange(shell rect: NSRect, controls: NSRect, controlsAlpha: CGFloat, badge badgeRect: NSRect?, iconAlpha: CGFloat) {
        shell.frame = rect
        shell.layer?.cornerRadius = min(rect.width, rect.height) / 2
        if content.frame != controls { content.frame = controls }
        content.alphaValue = controlsAlpha; content.isHidden = controlsAlpha <= 0
        let side = ToolbarMetrics.circleDiameter
        entry.frame = NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        entry.alphaValue = iconAlpha; entry.isHidden = iconAlpha <= 0
        if let badgeRect { badge.frame = badgeRect }
        badge.alphaValue = iconAlpha; badge.isHidden = badgeRect == nil
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let window, let owner else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        let screen = window.convertPoint(toScreen: convert(local, to: nil))
        guard owner.contains(screen) else { return nil }
        return interactive ? (super.hitTest(point) ?? self) : self
    }
    override func mouseDown(with event: NSEvent) {
        // A stable capsule only moves by its grip; elsewhere the press belongs to the entry.
        guard !interactive else { return }
        owner?.track(activate: true)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { owner?.pointerChanged() }
    override func mouseMoved(with event: NSEvent) { owner?.pointerChanged() }
    override func mouseExited(with event: NSEvent) { owner?.pointerChanged() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); colors() }
    private func colors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            shell.layer?.backgroundColor = NoteTheme.toolbarBackground.cgColor
            shell.layer?.borderColor = NoteTheme.toolbarBorder.cgColor
        }
    }
}

/// The round entry's note icon. Accessibility sees a button that expands the toolbar.
final class ToolbarEntry: NSView {
    var activate: () -> Void = {}
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel("展开 DeskNodes 工具条")
        toolTip = "展开工具条"
    }
    required init?(coder: NSCoder) { fatalError() }
    override func accessibilityPerformPress() -> Bool { activate(); return true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 19, weight: .medium).applying(.init(paletteColors: [NoteTheme.toolbarInk]))
        guard let image = NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
        let size = image.size
        image.draw(in: NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height))
    }
}

/// Gathered-note count beside the round entry; over 99 reads "99+".
final class ToolbarBadge: NSView {
    var text = "" { didSet { needsDisplay = true; setAccessibilityLabel("已收起 \(text) 张便签") } }
    private var attributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.white]
    }
    override var fittingSize: NSSize {
        NSSize(width: max(18, ceil((text as NSString).size(withAttributes: attributes).width) + 10), height: 18)
    }
    override func draw(_ dirtyRect: NSRect) {
        NoteTheme.accent.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }
}

/// Grip, buttons, pager and count at their final coordinates for the target size. It never
/// re-lays out for an intermediate shell size: the shell animates, this only fades.
final class ToolbarView: NSView {
    let grip = ToolbarGrip()
    let buttons: [ToolbarButton] = [
        ToolbarButton(symbol: "plus", label: "新建", help: "新建便签"),
        ToolbarButton(symbol: "trash", label: "删除", help: "删除选中的便签", destructive: true),
        ToolbarButton(symbol: "square.grid.2x2", label: "整理", help: "把便签按屏幕从左到右排整齐"),
        ToolbarButton(symbol: "arrow.down.right.and.arrow.up.left", label: "收起", help: "把全部便签收拢到工具条旁"),
        ToolbarButton(symbol: "pin", label: "置顶", help: "全部便签显示在其他应用上方，包括全屏应用"),
        ToolbarButton(symbol: "gearshape", label: "设置", help: "打开设置")
    ]
    let pager = ToolbarPager()
    let count = NSTextField(labelWithString: "")
    private let rule = NSView()
    /// Everything after the grip; it scrolls when the display is too small for all of it.
    private let strip = NSScrollView()
    private let items = FlippedView()
    var orientation: ToolbarOrientation = .vertical {
        didSet { pager.horizontal = orientation == .horizontal; needsLayout = true }
    }
    override var isFlipped: Bool { true }
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        count.font = .systemFont(ofSize: 11, weight: .medium); count.textColor = NoteTheme.toolbarSecondary; count.alignment = .center
        rule.wantsLayer = true
        strip.drawsBackground = false; strip.hasVerticalScroller = false; strip.hasHorizontalScroller = false
        strip.verticalScrollElasticity = .none; strip.horizontalScrollElasticity = .none
        strip.automaticallyAdjustsContentInsets = false; strip.contentInsets = NSEdgeInsetsZero
        strip.documentView = items
        [rule, count, pager].forEach { items.addSubview($0) }
        buttons.forEach { items.addSubview($0) }
        [grip, strip].forEach { addSubview($0) }
        pager.isHidden = true
        setAccessibilityElement(true); setAccessibilityRole(.toolbar); setAccessibilityLabel("DeskNodes 工具条")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        let inset = CGFloat(ToolbarMetrics.inset), lead = inset + CGFloat(ToolbarMetrics.endCap)
        let grip = CGFloat(ToolbarMetrics.gripHeight)
        let paged = !pager.isHidden
        if orientation == .vertical {
            let width = bounds.width - inset * 2
            self.grip.frame = NSRect(x: inset, y: lead, width: width, height: grip)
            strip.frame = NSRect(x: 0, y: lead + grip, width: bounds.width, height: max(0, bounds.height - lead * 2 - grip))
            var y: CGFloat = 0
            for button in buttons {
                button.frame = NSRect(x: inset, y: y, width: width, height: CGFloat(ToolbarMetrics.buttonHeight)); y += button.frame.height
            }
            if paged { pager.frame = NSRect(x: inset, y: y, width: width, height: CGFloat(ToolbarMetrics.pagerHeight)); y += pager.frame.height }
            rule.frame = NSRect(x: inset + 6, y: y + 2, width: width - 12, height: 1)
            count.frame = NSRect(x: 2, y: y + 10, width: bounds.width - 4, height: 15)
            items.frame = NSRect(x: 0, y: 0, width: bounds.width, height: y + CGFloat(ToolbarMetrics.footerHeight))
        } else {
            let height = bounds.height - inset * 2
            self.grip.frame = NSRect(x: lead, y: inset, width: grip, height: height)
            strip.frame = NSRect(x: lead + grip, y: 0, width: max(0, bounds.width - lead * 2 - grip), height: bounds.height)
            var x: CGFloat = 0
            for button in buttons {
                button.frame = NSRect(x: x, y: inset, width: CGFloat(ToolbarMetrics.buttonWidth), height: height); x += button.frame.width
            }
            if paged { pager.frame = NSRect(x: x, y: (bounds.height - 28) / 2, width: CGFloat(ToolbarMetrics.pagerWidth), height: 28); x += pager.frame.width }
            rule.frame = NSRect(x: x + 2, y: inset + 10, width: 1, height: height - 20)
            count.frame = NSRect(x: x + 4, y: (bounds.height - 15) / 2, width: CGFloat(ToolbarMetrics.footerWidth) - 6, height: 15)
            items.frame = NSRect(x: 0, y: 0, width: x + CGFloat(ToolbarMetrics.footerWidth), height: bounds.height)
        }
        colors()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); colors() }
    private func colors() {
        effectiveAppearance.performAsCurrentDrawingAppearance { rule.layer?.backgroundColor = NoteTheme.hairline.cgColor }
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Dot grip at the leading end. Pressing it hands the drag to the toolbar, which moves the
/// window live with the pointer, without easing.
final class ToolbarGrip: NSView {
    var pressed: () -> Void = {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true); setAccessibilityRole(.handle); setAccessibilityLabel("拖动工具条")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        NoteTheme.toolbarSecondary.setFill()
        // Three dots across the long side's direction, two along it.
        let across = bounds.width >= bounds.height
        for row in 0..<2 {
            for column in 0..<3 {
                let x = across ? bounds.midX - 7 + CGFloat(column) * 5.5 : bounds.midX - 4 + CGFloat(row) * 5
                let y = across ? bounds.midY - 4 + CGFloat(row) * 5 : bounds.midY - 7 + CGFloat(column) * 5.5
                NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 3, height: 3)).fill()
            }
        }
    }
    override func mouseDown(with event: NSEvent) { pressed() }
}

/// Icon plus a short label; hover and press are quiet tints, disabled is dimmed.
final class ToolbarButton: NSControl {
    var symbol: String { didSet { needsDisplay = true } }
    var label: String { didSet { needsDisplay = true; setAccessibilityLabel(label) } }
    var help: String { didSet { toolTip = help; setAccessibilityHelp(help) } }
    /// A toggle that is on keeps a tinted plate, like a pressed-in key.
    var isOn = false { didSet { needsDisplay = true; setAccessibilityValue(isOn ? "开" : "关") } }
    private let destructive: Bool
    private var hovering = false { didSet { needsDisplay = true } }
    private var pressing = false { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    override var isEnabled: Bool { didSet { needsDisplay = true; setAccessibilityEnabled(isEnabled) } }
    init(symbol: String, label: String, help: String, destructive: Bool = false) {
        self.symbol = symbol; self.label = label; self.help = help; self.destructive = destructive
        super.init(frame: .zero)
        toolTip = help
        setAccessibilityElement(true); setAccessibilityRole(.button)
        setAccessibilityLabel(label); setAccessibilityHelp(help)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        return sendAction(action, to: target)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let window else { return }
        pressing = true
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let inside = bounds.contains(convert(next.locationInWindow, from: nil))
            pressing = inside
            if next.type == .leftMouseUp { break }
        }
        let fire = pressing
        pressing = false
        if fire { sendAction(action, to: target) }
    }
    override func draw(_ dirtyRect: NSRect) {
        let plate = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 2), xRadius: 10, yRadius: 10)
        if isOn {
            NoteTheme.accent.withAlphaComponent(pressing ? 0.26 : hovering ? 0.22 : 0.18).setFill(); plate.fill()
        } else if isEnabled && (pressing || hovering) {
            NoteTheme.toolbarInk.withAlphaComponent(pressing ? 0.12 : 0.06).setFill(); plate.fill()
        }
        let ink: NSColor = !isEnabled ? NoteTheme.toolbarDisabled
            : destructive && hovering ? NSColor.systemRed : NoteTheme.toolbarInk
        let configuration = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium).applying(.init(paletteColors: [ink]))
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
            let size = image.size
            image.draw(in: NSRect(x: bounds.midX - size.width / 2, y: 18 - size.height / 2, width: size.width, height: size.height),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        (label as NSString).draw(in: NSRect(x: 0, y: 31, width: bounds.width, height: 18), withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: ink, .paragraphStyle: paragraph])
    }
}

/// Shown only while the last arrangement overflowed a display.
final class ToolbarPager: NSView {
    var turn: (Int) -> Void = { _ in }
    private let previous = PagerArrow(symbol: "chevron.up", label: "上一页")
    private let next = PagerArrow(symbol: "chevron.down", label: "下一页")
    /// Arrows point along the toolbar: up/down vertically, left/right horizontally.
    var horizontal = false {
        didSet {
            previous.symbol = horizontal ? "chevron.left" : "chevron.up"
            next.symbol = horizontal ? "chevron.right" : "chevron.down"
        }
    }
    private let label = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium); label.alignment = .center
        label.textColor = NoteTheme.toolbarSecondary
        previous.target = self; previous.action = #selector(back)
        next.target = self; next.action = #selector(forward)
        [previous, label, next].forEach { addSubview($0) }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        previous.frame = NSRect(x: 0, y: (bounds.height - 22) / 2, width: 16, height: 22)
        next.frame = NSRect(x: bounds.width - 16, y: (bounds.height - 22) / 2, width: 16, height: 22)
        label.frame = NSRect(x: 14, y: (bounds.height - 14) / 2, width: bounds.width - 28, height: 14)
    }
    func show(current: Int, total: Int) {
        label.stringValue = "\(current + 1)/\(total)"
        label.setAccessibilityLabel("第 \(current + 1) 页，共 \(total) 页")
        previous.isEnabled = current > 0; next.isEnabled = current < total - 1
    }
    @objc private func back() { turn(-1) }
    @objc private func forward() { turn(1) }
}

private final class PagerArrow: NSButton {
    private let label: String
    var symbol: String {
        didSet { image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?.withSymbolConfiguration(.init(pointSize: 9, weight: .semibold)) }
    }
    init(symbol: String, label: String) {
        self.label = label; self.symbol = symbol
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?.withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        isBordered = false; contentTintColor = NoteTheme.toolbarSecondary; toolTip = label; setAccessibilityLabel(label)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The small stack beside the toolbar while notes are collapsed: up to three colour
/// cards and a count, never note content. Clicking it expands.
final class StackHint: NSPanel {
    static let size = NSSize(width: 136, height: 118)
    private let view = StackHintView(frame: NSRect(origin: .zero, size: StackHint.size))
    var expand: () -> Void = {}
    override var canBecomeKey: Bool { false }
    init() {
        super.init(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false; isOpaque = false; backgroundColor = .clear; hasShadow = false
        hidesOnDeactivate = false; level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        contentView = view
        view.clicked = { [weak self] in self?.expand() }
    }
    func show(colors: [NotePalette], count: Int) { view.colors = Array(colors.prefix(3)); view.count = count }
}

private final class StackHintView: NSView {
    var colors: [NotePalette] = [] { didSet { needsDisplay = true } }
    var count = 0 { didSet { needsDisplay = true; setAccessibilityLabel("展开 \(count) 张便签") } }
    var clicked: () -> Void = {}
    private var hovering = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true); setAccessibilityRole(.button)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
        toolTip = "展开便签"
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool { clicked(); return true }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseUp(with event: NSEvent) { if bounds.contains(convert(event.locationInWindow, from: nil)) { clicked() } }
    override func draw(_ dirtyRect: NSRect) {
        let card = NSSize(width: 100, height: 70)
        let lift: CGFloat = hovering ? 2 : 0
        // Back to front: the first note is the front card, bottom-left.
        let behind = CGFloat(max(0, colors.count - 1))
        for (index, palette) in colors.enumerated().reversed() {
            let depth = CGFloat(index)
            let rect = NSRect(x: 8 + depth * 11, y: 8 + (behind - depth) * 8 - lift, width: card.width, height: card.height)
            let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowBlurRadius = 6; shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.16); shadow.set()
            NoteTheme.background(palette).setFill(); path.fill()
            NSGraphicsContext.restoreGraphicsState()
            NoteTheme.border.setStroke(); path.lineWidth = 1; path.stroke()
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        let text = NSAttributedString(string: "\(count) 张便签", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white, .paragraphStyle: paragraph,
            .shadow: { let s = NSShadow(); s.shadowBlurRadius = 3; s.shadowColor = NSColor.black.withAlphaComponent(0.55); return s }()])
        text.draw(in: NSRect(x: 0, y: bounds.height - 22, width: bounds.width, height: 18))
    }
}
