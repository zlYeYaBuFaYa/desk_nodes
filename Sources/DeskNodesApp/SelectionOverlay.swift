import AppKit
import DeskNodesCore
import DeskNodesPersistence

/// 批量删除: a selection mode over the real note windows.
///
/// Bare desktop belongs to Finder and global event monitors are not used, so a marquee
/// can start only where DeskNodes receives the press: a ⌘-press on a note, or, while the
/// mode is on, the dimmed overlay laid under the lifted notes on every display. A drag
/// keeps going to the window it started in, so the pointer may cross empty desktop.
@MainActor
final class NotePicker {
    private let surfaces: () -> NoteSurfaces?
    /// Lifts the notes (like 浮起) while selecting; false puts them back.
    var lift: (Bool) -> Void = { _ in }
    var canMutate: () -> Bool = { true }
    var delete: ([NoteID]) -> Void = { _ in }
    private var overlays: [NSPanel] = []
    private var marquee: NSPanel?
    private var bar: SelectionBar?
    private var keys: Any?

    init(surfaces: @escaping () -> NoteSurfaces?) { self.surfaces = surfaces }

    var active: Bool { surfaces()?.picked != nil }

    /// Starts selecting, with `id` picked; when already selecting, `id` is toggled.
    func begin(with id: NoteID?) {
        guard let surfaces = surfaces() else { return }
        if active { if let id { toggle(id) }; return }
        guard canMutate() else { return }
        // Lifting first expands a collapsed desk, so its notes count as pickable.
        lift(true)
        guard id != nil || !surfaces.pickable.isEmpty else { lift(false); return }
        surfaces.pickedChanged = { [weak self] in self?.updateBar() }
        surfaces.setPicked(id.map { [$0] } ?? [])
        // A note must be key for Esc, Delete and ⌘A to arrive; no text editor may be
        // first responder, so typing cannot reach a note while selecting.
        NSApp.activate(ignoringOtherApps: true)
        if let key = id.flatMap({ surfaces.panels[$0] }) ?? surfaces.pickable.values.first {
            key.makeKeyAndOrderFront(nil); key.makeFirstResponder(nil)
        }
        showOverlays(); showBar(); installKeys()
        // Observe only after activating, so the switch away from the previous app is not
        // mistaken for leaving (as 浮起 does).
        DispatchQueue.main.async { [weak self] in
            guard let self, self.active else { return }
            NotificationCenter.default.addObserver(self, selector: #selector(self.resigned), name: NSApplication.didResignActiveNotification, object: nil)
        }
    }

    func end() {
        guard active else { return }
        NotificationCenter.default.removeObserver(self, name: NSApplication.didResignActiveNotification, object: nil)
        if let keys { NSEvent.removeMonitor(keys) }; keys = nil
        overlays.forEach { $0.close() }; overlays = []
        marquee?.close(); marquee = nil
        bar?.close(); bar = nil
        surfaces()?.setPicked(nil)
        surfaces()?.pickedChanged = {}
        lift(false)
    }
    @objc private func resigned() { end() }

    /// A press on note `id`. While selecting it toggles or starts a marquee; otherwise
    /// only a ⌘-press is taken, starting the mode and a marquee in one gesture.
    func press(_ event: NSEvent, on id: NoteID, in window: NSWindow) -> Bool {
        if active {
            if event.type == .leftMouseDown { track(event, in: window, toggling: id) }
            return true // no context menu or editing while selecting
        }
        guard event.type == .leftMouseDown, event.modifierFlags.contains(.command), canMutate() else { return false }
        begin(with: id)
        if active { track(event, in: window, toggling: nil) }
        return true
    }

    func selectAll() {
        guard let surfaces = surfaces(), active else { return }
        surfaces.setPicked(Set(surfaces.pickable.keys))
    }
    func deletePicked() {
        guard let picked = surfaces()?.picked, !picked.isEmpty, canMutate() else { return }
        end(); delete(Array(picked))
    }
    private func toggle(_ id: NoteID) {
        guard var picked = surfaces()?.picked else { return }
        if picked.remove(id) == nil { picked.insert(id) }
        surfaces()?.setPicked(picked)
    }

    /// Runs one press-drag-release. A drag selects what the rectangle touches (added to the
    /// current selection with ⌘); a click toggles `toggling`, or clears on bare overlay.
    func track(_ event: NSEvent, in window: NSWindow, toggling id: NoteID?) {
        guard let surfaces = surfaces(), let before = surfaces.picked else { return }
        let additive = event.modifierFlags.contains(.command)
        let base = additive ? before : []
        let origin = NSEvent.mouseLocation
        var moved = false
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), next.type == .leftMouseDragged {
            let point = NSEvent.mouseLocation
            let rect = NSRect(x: min(origin.x, point.x), y: min(origin.y, point.y),
                              width: abs(point.x - origin.x), height: abs(point.y - origin.y))
            guard moved || rect.width + rect.height >= 4 else { continue }
            moved = true
            showMarquee(rect)
            let hits = surfaces.pickable.filter { $0.value.frame.intersects(rect) }.map(\.key)
            surfaces.setPicked(base.union(hits))
        }
        marquee?.orderOut(nil)
        guard !moved else { return }
        if let id { toggle(id) } else if !additive { surfaces.setPicked([]) }
    }

    // MARK: Windows

    private func showOverlays() {
        // Just under the lifted notes (topmost = .floating), above every other app.
        let level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        overlays = NSScreen.screens.map { screen in
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.hasShadow = false
            panel.backgroundColor = NSColor.black.withAlphaComponent(0.10)
            panel.level = level; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.pressed = { [weak self, weak panel] event in
                guard let self, let panel else { return }
                self.track(event, in: panel, toggling: nil)
            }
            panel.contentView = view
            panel.orderFrontRegardless()
            return panel
        }
    }
    private func showMarquee(_ rect: NSRect) {
        if marquee == nil {
            let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.hasShadow = false
            panel.backgroundColor = .clear; panel.ignoresMouseEvents = true
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = NSView(); view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
            view.layer?.borderColor = NSColor.controlAccentColor.cgColor; view.layer?.borderWidth = 1
            panel.contentView = view
            marquee = panel
        }
        marquee?.setFrame(rect, display: true)
        marquee?.orderFrontRegardless()
    }
    private func showBar() {
        let bar = SelectionBar()
        bar.selectAll = { [weak self] in self?.selectAll() }
        bar.delete = { [weak self] in self?.deletePicked() }
        bar.done = { [weak self] in self?.end() }
        bar.orderFrontRegardless()
        self.bar = bar; updateBar()
    }
    private func updateBar() { bar?.update(count: surfaces()?.picked?.count ?? 0) }

    /// Esc, ⌘A and Delete; other plain keys are swallowed so nothing types into a note.
    /// Settings, alerts and file panels keep their own keys.
    private func installKeys() {
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window == nil || event.window is NotePanel
                    || self.overlays.contains(where: { $0 === event.window }) || event.window === self.bar
            else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            switch event.keyCode {
            case 53: self.end(); return nil // Esc
            case 51, 117: self.deletePicked(); return nil // Delete, Forward Delete
            default: break
            }
            if flags == .command, event.charactersIgnoringModifiers == "a" { self.selectAll(); return nil }
            return flags.contains(.command) ? event : nil
        }
    }
}

private final class OverlayView: NSView {
    var pressed: ((NSEvent) -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { pressed?(event) }
}

/// "已选择 N 张便签 │ 全选 删除 完成" at the bottom of the main display.
final class SelectionBar: NSPanel {
    private static let size = NSSize(width: 380, height: 46)
    var selectAll: () -> Void = {}
    var delete: () -> Void = {}
    var done: () -> Void = {}
    private let label = NSTextField(labelWithString: "")
    private let deleteButton = NSButton(title: "删除", target: nil, action: nil)
    init() {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        super.init(contentRect: NSRect(x: visible.midX - Self.size.width / 2, y: visible.minY + 28, width: Self.size.width, height: Self.size.height),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        isReleasedWhenClosed = false; isOpaque = false; backgroundColor = .clear; hasShadow = true
        let view = ToastSurface(frame: NSRect(origin: .zero, size: Self.size))
        label.font = .systemFont(ofSize: 13); label.textColor = NoteTheme.primary
        label.frame = NSRect(x: 16, y: 14, width: 170, height: 18); label.lineBreakMode = .byTruncatingTail
        let rule = NSView(frame: NSRect(x: 192, y: 12, width: 1, height: 22))
        rule.wantsLayer = true; rule.layer?.backgroundColor = NSColor.separatorColor.cgColor
        let all = NSButton(title: "全选", target: self, action: #selector(tapAll))
        deleteButton.target = self; deleteButton.action = #selector(tapDelete)
        let finish = NSButton(title: "完成", target: self, action: #selector(tapDone))
        for (index, button) in [all, deleteButton, finish].enumerated() {
            button.isBordered = false; button.font = .systemFont(ofSize: 13, weight: .medium)
            button.frame = NSRect(x: 200 + CGFloat(index) * 58, y: 9, width: 54, height: 28)
        }
        [label, rule, all, deleteButton, finish].forEach { view.addSubview($0) }
        contentView = view
    }
    func update(count: Int) {
        label.stringValue = count > 0 ? "已选择 \(count) 张便签" : "单击便签勾选，或拖动框选"
        deleteButton.isEnabled = count > 0
        deleteButton.attributedTitle = NSAttributedString(string: "删除", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: count > 0 ? NSColor.systemRed : NSColor.tertiaryLabelColor])
        setAccessibilityLabel(label.stringValue)
    }
    @objc private func tapAll() { selectAll() }
    @objc private func tapDelete() { delete() }
    @objc private func tapDone() { done() }
}
