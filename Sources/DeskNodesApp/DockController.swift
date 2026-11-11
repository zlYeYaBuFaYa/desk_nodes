import AppKit
import QuartzCore
import ColorSync
import DeskNodesCore
import DeskNodesActions
import DeskNodesPersistence

/// All preview state lives here. Existing panels and NSTextViews are never reparented.
@MainActor
final class DockController: NSObject {
    let actions: NoteActions
    let canMutate: () -> Bool
    let changed: () -> Void
    let failure: (Error) -> Void
    private var panels: [NoteID: NotePanel] = [:]
    /// Overflow tab windows per strip, reused while their content is unchanged.
    private var rails: [String: (signature: String, windows: [NSPanel])] = [:]
    private var railsInUse: Set<String> = []
    private var selected: [String: NoteID] = [:]
    private var dragging: NoteID?
    private var promoting = false
    private var placeholder: NSPanel?
    private var dragOrigin: NoteFrame?
    private var layouts: [String: DockLayout] = [:]
    private var pages: [String: Int] = [:]
    private var controls: [(DockEdge, String?)] = []
    /// Global collapse: strips keep their geometry but their overflow tab windows close.
    var suppressed = false
    init(actions: NoteActions, canMutate: @escaping () -> Bool = { true }, changed: @escaping () -> Void, failure: @escaping (Error) -> Void) {
        self.canMutate = canMutate
        self.actions = actions; self.changed = changed; self.failure = failure
    }
    func invalidateAfterImport() {
        for panel in panels.values {
            panel.dockingAction = nil; panel.dragBegin = nil; panel.dragUpdate = nil
            panel.dragCancel = nil; panel.dragEnd = nil
        }
        rails.values.flatMap(\.windows).forEach { $0.close() }; rails = [:]; placeholder?.close(); placeholder = nil
        panels = [:]; dragging = nil; selected = [:]; layouts = [:]
    }
    /// NSScreen.screens[0] is the menu-bar/primary screen; NSScreen.main is the key-window screen.
    static func screens() -> [DockScreen] {
        let mapped = NSScreen.screens.enumerated().map { index, screen in
            let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            let uuid = number.flatMap { CGDisplayCreateUUIDFromDisplayID($0)?.takeRetainedValue() }
            let stable = uuid.flatMap { value -> String? in
                guard let string = CFUUIDCreateString(nil, value) else { return nil }
                return string as String
            }
            // Session-only fallback must not masquerade as a persistent hardware identity.
            let id = stable ?? "session-screen-\(number.map { String($0) } ?? String(index))"
            let f = screen.visibleFrame
            return DockScreen(id: id, visible: NoteFrame(x: f.minX, y: f.minY, width: f.width, height: f.height))
        }
        return mapped.enumerated().map { index, screen in
            guard mapped.filter({ $0.id == screen.id }).count > 1 else { return screen }
            return DockScreen(id: "session-screen-ambiguous-\(index)", visible: screen.visible)
        }
    }
    private func key(_ edge: DockEdge, _ screen: DockScreen) -> String { edge.rawValue + ":" + screen.id }
    /// `changed`: free panels to re-clamp (nil = all). `strips == false` keeps every strip,
    /// its tab windows and cached slots as they are (no docked note was affected).
    func layout(panels: [NoteID: NotePanel], modes: WindowModes, changed: Set<NoteID>? = nil, strips: Bool = true) {
        guard dragging == nil else { return }
        self.panels = panels
        if strips { layouts = [:]; railsInUse = [] } else { railsInUse = Set(rails.keys) }
        // Strips that no longer overflow drop their tab windows after this pass.
        defer {
            for key in rails.keys where !railsInUse.contains(key) { rails.removeValue(forKey: key)?.windows.forEach { $0.close() } }
        }
        do {
            let notes = try actions.store.notes(), settings = try actions.store.settings(), screens = Self.screens()
            for note in notes {
                guard let panel = panels[note.id] else { continue }
                if case .dock = note.placement { panel.docked = true } else { panel.docked = false }
                panel.dockingAction = { [weak self] edge in self?.changeDock(note.id, edge: edge) }
                panel.dragBegin = { [weak self] in self?.begin(note.id) }
                panel.dragUpdate = { [weak self] frame, point in self?.preview(note.id, frame: frame, point: point) }
                panel.dragCancel = { [weak self] in self?.cancel() }
                panel.dragEnd = { [weak self] frame, point in self?.end(note.id, frame: frame, point: point) }
                if !panel.docked {
                    guard changed?.contains(note.id) ?? true else { continue }
                    if let expanded = panel.expandedFrame,
                       let screen = screens.first(where: { $0.id == note.placement.displayID }) ?? screens.first {
                        let projected = DockGeometry.clamp(expanded.presenting(collapsed: note.collapsed), to: screen)
                        var fitted = projected
                        if note.collapsed { fitted.height = expanded.height; fitted.y = projected.y + projected.height - expanded.height }
                        panel.present(fitted, collapsed: note.collapsed, animate: false)
                        if note.collapsed && projected.height < 32 { panel.setFrame(rect(projected), display: true) }
                    }
                    if !panel.isVisible { panel.orderFrontRegardless() }; continue
                }
            }
            for screen in screens where strips {
                for edge in [DockEdge.top, .left, .right] {
                    let group = notes.filter {
                        guard case .dock(let e, let id) = $0.placement else { return false }
                        return e == edge && DockGeometry.screen(id, screens: screens, preferred: settings.displayID)?.id == screen.id
                    }
                    guard !group.isEmpty else { continue }
                    let k = key(edge, screen)
                    let heights = Dictionary(uniqueKeysWithValues: group.map { ($0.id, (panels[$0.id]?.contentView as? NoteCardView)?.preferredHeight(width: 240) ?? 120) })
                    let occupied = Set(notes.compactMap { note -> DockEdge? in
                        guard case .dock(let e, let d) = note.placement,
                              DockGeometry.screen(d, screens: screens, preferred: settings.displayID)?.id == screen.id else { return nil }
                        return e
                    })
                    let region = DockGeometry.region(edge: edge, occupied: occupied, screen: screen)
                    let compact = Set(group.filter(\.collapsed).map(\.id))
                    let base = DockGeometry.layout(ids: group.map(\.id), edge: edge, screen: region, heights: heights, collapsed: compact)
                    if let chosen = selected[k], !base.overflow.contains(chosen) { selected[k] = nil }
                    if !promoting, let active = group.first(where: { panels[$0.id]?.isKeyWindow == true }), base.overflow.contains(active.id) { selected[k] = active.id }
                    let result = DockGeometry.layout(ids: group.map(\.id), edge: edge, screen: region, heights: heights,
                        collapsed: compact, selected: selected[k])
                    layouts[k] = result
                    for slot in result.slots {
                        guard let panel = panels[slot.id], let note = group.first(where: { $0.id == slot.id }) else { continue }
                        present(panel, frame: slot.frame, collapsed: note.collapsed)
                        if !panel.isVisible { panel.orderFrontRegardless() }
                    }
                    for id in result.overflow {
                        // Overflow is a compact tab presentation, never a durable hide state.
                        if promoting || panels[id]?.isKeyWindow != true { panels[id]?.orderOut(nil) }
                    }
                    if let frame = result.tabs { makeRail(frame, notes: group.filter { result.overflow.contains($0.id) }, key: k, modes: modes) }
                    // Pathological narrow/short region: selected tab opens the retained panel over the strip.
                    if result.slots.isEmpty, let id = selected[k], let panel = panels[id], let note = group.first(where: { $0.id == id }) {
                        present(panel, frame: DockGeometry.clamp(NoteFrame(x: screen.available.x, y: screen.available.y, height: 200), to: screen), collapsed: note.collapsed)
                        panel.makeKeyAndOrderFront(nil)
                    }
                }
            }
        } catch { failure(error) }
    }
    private func present(_ panel: NotePanel, frame: NoteFrame, collapsed: Bool) {
        // Slots already account for collapsed height. Keep expanded geometry independent.
        var expanded = frame
        if collapsed { expanded.height = 260; expanded.y = frame.y + frame.height - 260 }
        let old = panel.frame.origin
        panel.present(expanded, collapsed: collapsed, animate: false)
        if collapsed && frame.height < 32 { panel.setFrame(rect(frame), display: true) }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = panel.contentView?.layer,
              old != panel.frame.origin else { return }
        let spring = CASpringAnimation(keyPath: "transform.translation")
        spring.fromValue = NSValue(point: NSPoint(x: old.x - panel.frame.minX, y: old.y - panel.frame.minY))
        spring.toValue = NSValue(point: .zero); spring.stiffness = 300; spring.damping = 27; spring.duration = 0.30
        layer.add(spring, forKey: "dockSnap")
    }
    private func makeRail(_ frame: NoteFrame, notes: [Note], key: String, modes: WindowModes) {
        guard !suppressed else { return } // not in use: the pass closes this strip's tabs
        railsInUse.insert(key)
        let allocation = DockGeometry.tabs(ids: notes.map(\.id), frame: frame, page: pages[key] ?? 0)
        var titles: [NoteID: String] = [:]
        for note in notes {
            let first = (try? actions.store.items(in: note.id))?.first?.text
            let text = WindowModes.collapsedTitle(note.title, firstItem: first)
            titles[note.id] = text.isEmpty ? "空便签" : text
        }
        func title(_ note: Note) -> String { titles[note.id] ?? "空便签" }
        // Everything a tab window or its closures show; equal signature -> keep the windows.
        let signature = ([String(describing: allocation), String(describing: modes.allTopmost)] + notes.map {
            "\($0.id.rawValue)|\(title($0))|\($0.color.rawValue)|\($0.level.rawValue)"
        }).joined(separator: "\n")
        if rails[key]?.signature == signature { return }
        rails.removeValue(forKey: key)?.windows.forEach { $0.close() }
        var windows: [NSPanel] = []
        defer { rails[key] = (signature, windows) }
        func choose(_ id: NoteID) {
            selected[key] = id; promoting = true
            changed(); promoting = false; panels[id]?.makeKeyAndOrderFront(nil)
        }
        func window(_ frame: NoteFrame, button: DockTab, choice: WindowLevel) {
            let tab = NSPanel(contentRect: rect(frame), styleMask: [.borderless], backing: .buffered, defer: false)
            tab.isReleasedWhenClosed = false; tab.isOpaque = false; tab.backgroundColor = .clear
            tab.hasShadow = true; tab.hidesOnDeactivate = false
            tab.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone]
            switch modes.effective(choice) {
            case .desktop: tab.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            case .ordinary: tab.level = .normal
            case .topmost: tab.level = .floating
            }
            button.frame = NSRect(origin: .zero, size: rect(frame).size)
            button.isBordered = false; button.font = .systemFont(ofSize: 13, weight: .semibold)
            button.lineBreakMode = .byTruncatingTail; button.toolTip = button.title
            button.target = button; button.action = #selector(DockTab.selectTab)
            button.turnPage = { [weak self] delta in
                guard let self else { return }
                self.pages[key] = min(max(0, (self.pages[key] ?? 0) + delta), allocation.pageCount - 1)
                self.changed()
            }
            tab.contentView = button; tab.orderFrontRegardless(); windows.append(tab)
        }
        for slot in allocation.slots {
            guard let note = notes.first(where: { $0.id == slot.id }) else { continue }
            let button = DockTab(frame: .zero); button.title = title(note); button.palette = note.color
            button.choose = { choose(note.id) }
            window(slot.frame, button: button, choice: note.level)
        }
        let more = DockTab(frame: .zero); more.title = "更多 · \(notes.count)"
        more.choose = { [weak more] in
            guard let more else { return }
            let menu = NSMenu()
            for note in notes {
                let item = NSMenuItem(title: title(note), action: #selector(DockMenuChoice.performChoice), keyEquivalent: "")
                let target = DockMenuChoice { choose(note.id) }
                item.representedObject = target; item.target = target; menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: more.bounds.height), in: more)
        }
        window(allocation.control, button: more, choice: .desktop)
    }
    private func begin(_ id: NoteID) {
        dragging = id
        guard let panel = panels[id] else { return }
        if panel.docked { dragOrigin = NoteFrame(x: panel.frame.minX, y: panel.frame.minY, width: panel.frame.width, height: panel.frame.height) }
        else { dragOrigin = nil }
        // No scaling while dragging: a scaled editor layer blurs text and misplaces the caret.
        guard panel.docked else { return }
        panel.contentView?.layer?.shadowColor = NSColor.black.cgColor
        panel.contentView?.layer?.shadowOpacity = 0.28; panel.contentView?.layer?.shadowRadius = 24
        panel.contentView?.layer?.masksToBounds = false
    }
    private func destination(_ id: NoteID, frame: NoteFrame, point: NSPoint) throws -> (DockEdge, DockScreen, String?)? {
        let screens = Self.screens(), settings = try actions.store.settings()
        guard let note = try actions.store.notes().first(where: { $0.id == id }) else { return nil }
        // Free notes stay free wherever they are dropped; docking is an explicit menu
        // choice. Notes already in a strip can still be reordered or moved between strips.
        guard case .dock(let edge, let display) = note.placement else { return nil }
        if let screen = DockGeometry.screen(display, screens: screens, preferred: settings.displayID) {
            let x = edge == .left ? frame.x : frame.x + frame.width
            let y = frame.y + frame.height
            if DockGeometry.retains(edge: edge, x: edge == .top ? point.x : x, y: edge == .top ? y : point.y, screen: screen) { return (edge, screen, display) }
        }
        guard let screen = screens.first(where: { DockGeometry.contains($0.visible, x: point.x, y: point.y) }),
              let edge = DockGeometry.snap(x: point.x, y: point.y, screen: screen) else { return nil }
        let preferred = DockGeometry.screen(nil, screens: screens, preferred: settings.displayID)
        return (edge, screen, preferred?.id == screen.id ? nil : screen.persistentID)
    }
    private func group(edge: DockEdge, screen: DockScreen) throws -> [Note] {
        let preferred = try actions.store.settings().displayID
        return try actions.store.notes().filter {
            guard case .dock(let e, let d) = $0.placement else { return false }
            return e == edge && DockGeometry.screen(d, screens: Self.screens(), preferred: preferred)?.id == screen.id
        }
    }
    private func targetIndex(_ id: NoteID, edge: DockEdge, screen: DockScreen, point: NSPoint) throws -> Int {
        DockGeometry.insertion(x: point.x, y: point.y, edge: edge, slots: layouts[key(edge, screen)]?.slots ?? [],
                               ordered: try group(edge: edge, screen: screen).map(\.id), excluding: id)
    }
    private func preview(_ id: NoteID, frame: NoteFrame, point: NSPoint) {
        placeholder?.close(); placeholder = nil
        var proposed = Dictionary(uniqueKeysWithValues: layouts.values.flatMap(\.slots).filter { $0.id != id }.map { ($0.id, $0.frame) })
        var target = dragOrigin
        defer {
            for (other, frame) in proposed { if let panel = panels[other] { present(panel, frame: frame, collapsed: panel.frame.height == 32) } }
            if let target { showPlaceholder(target, id: id) }
        }
        do {
            guard let (edge, screen, _) = try destination(id, frame: frame, point: point) else { return }
            let group = try group(edge: edge, screen: screen)
            let index = try targetIndex(id, edge: edge, screen: screen, point: point)
            var ids = group.map(\.id).filter { $0 != id }; ids.insert(id, at: min(index, ids.count))
            let all = try actions.store.notes(), preferred = try actions.store.settings().displayID
            let occupied = Set(all.compactMap { note -> DockEdge? in
                guard case .dock(let e, let d) = note.placement,
                      DockGeometry.screen(d, screens: Self.screens(), preferred: preferred)?.id == screen.id else { return nil }
                return e
            }).union([edge])
            let region = DockGeometry.region(edge: edge, occupied: occupied, screen: screen)
            let heights = Dictionary(uniqueKeysWithValues: ids.map { ($0, (panels[$0]?.contentView as? NoteCardView)?.preferredHeight(width: 240) ?? 120) })
            let result = DockGeometry.layout(ids: ids, edge: edge, screen: region, heights: heights,
                collapsed: Set(all.filter(\.collapsed).map(\.id)))
            for slot in result.slots where slot.id != id { proposed[slot.id] = slot.frame }
            target = result.slots.first(where: { $0.id == id })?.frame ?? dragOrigin
        } catch { failure(error) }
    }
    private func showPlaceholder(_ frame: NoteFrame, id: NoteID) {
        let slot = NSPanel(contentRect: rect(frame), styleMask: [.borderless], backing: .buffered, defer: false)
        slot.isReleasedWhenClosed = false; slot.isOpaque = false; slot.backgroundColor = .clear; slot.ignoresMouseEvents = true
        slot.level = panels[id]?.level ?? .normal; slot.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone]
        slot.contentView = DockPlaceholder(frame: NSRect(origin: .zero, size: rect(frame).size))
        slot.orderFrontRegardless(); placeholder = slot
    }
    private func cancel() {
        if let id = dragging {
            panels[id]?.contentView?.layer?.setAffineTransform(.identity)
            panels[id]?.contentView?.layer?.shadowOpacity = 0
            panels[id]?.contentView?.layer?.masksToBounds = true
        }
        dragging = nil; placeholder?.close(); placeholder = nil; changed()
    }
    private func end(_ id: NoteID, frame: NoteFrame, point: NSPoint) {
        defer { dragging = nil; placeholder?.close(); placeholder = nil; changed() }
        panels[id]?.contentView?.layer?.setAffineTransform(.identity)
        panels[id]?.contentView?.layer?.shadowOpacity = 0
        panels[id]?.contentView?.layer?.masksToBounds = true
        do {
            if let (edge, screen, display) = try destination(id, frame: frame, point: point) {
                let index = try targetIndex(id, edge: edge, screen: screen, point: point)
                try actions.dock(id, edge: edge, displayID: display, index: index, screens: Self.screens())
                selected[key(edge, screen)] = nil
            } else {
                let screens = Self.screens()
                guard let screen = screens.first(where: { DockGeometry.contains($0.visible, x: point.x, y: point.y) }) ?? screens.first else { return }
                // Keep the saved manual width/height when pulling a docked card out.
                let note = try actions.store.notes().first { $0.id == id }
                var free = frame
                if panels[id]?.docked == true, let saved = note?.freeRestore?.freeFrame {
                    free.width = saved.width; free.height = saved.height
                    free.y = frame.y + frame.height - free.height
                } else if panels[id]?.docked == true { free.width = NoteMetrics.width }
                try actions.detach(id, frame: DockGeometry.clamp(free, to: screen), displayID: screen.persistentID)
            }
        } catch { failure(error) }
    }
    private func changeDock(_ id: NoteID, edge: DockEdge?) {
        guard canMutate() else { return }
        do {
            if let edge { try actions.dock(id, edge: edge, displayID: nil, index: Int.max, screens: Self.screens()) }
            else { try actions.detach(id); try actions.reconcileScreens(Self.screens()) }
            changed()
        } catch { failure(error) }
    }
    func populateControls(_ menu: NSMenu) {
        menu.removeAllItems(); controls = []
        guard let settings = try? actions.store.settings() else { return }
        let screens = Self.screens()
        let displays: [(String, String?)] = [("主屏幕（默认）", nil)] + NSScreen.screens.enumerated().compactMap { index, screen in
            guard screens.indices.contains(index) else { return nil }
            return screens[index].persistentID.map { (screen.localizedName, Optional($0)) }
        }
        if let chosen = settings.displayID, !screens.contains(where: { $0.id == chosen }) {
            let unavailable = NSMenuItem(title: "所选显示器不可用，暂用主屏幕", action: nil, keyEquivalent: "")
            unavailable.isEnabled = false; menu.addItem(unavailable)
        }
        for (label, display) in displays {
            let parent = NSMenuItem(title: label, action: nil, keyEquivalent: ""), submenu = NSMenu()
            parent.state = settings.displayID == display ? .on : .off
            for (edge, title) in [(DockEdge.top, "顶部"), (.left, "左侧"), (.right, "右侧")] {
                let item = NSMenuItem(title: title, action: #selector(preference(_:)), keyEquivalent: "")
                item.target = self; item.tag = controls.count; controls.append((edge, display)); submenu.addItem(item)
                item.state = settings.displayID == display && settings.dockEdge == edge ? .on : .off
            }
            parent.submenu = submenu; menu.addItem(parent)
        }
    }
    @objc private func preference(_ sender: NSMenuItem) {
        guard canMutate(), controls.indices.contains(sender.tag) else { return }
        do { let value = controls[sender.tag]; try actions.dockPreference(edge: value.0, displayID: value.1); changed() } catch { failure(error) }
    }
    private func rect(_ frame: NoteFrame) -> NSRect { NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height) }
}

private final class DockTab: NSButton {
    var palette: NotePalette = .paper
    var choose: (() -> Void)?
    var turnPage: ((Int) -> Void)?
    @objc func selectTab() { choose?() }
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) > 1 { turnPage?(event.scrollingDeltaY < 0 ? 1 : -1) }
    }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        NoteTheme.background(palette).setFill(); path.fill()
        NoteTheme.border.setStroke(); path.lineWidth = 1; path.stroke()
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        (title as NSString).draw(in: NSRect(x: 10, y: (bounds.height - 18) / 2, width: max(1, bounds.width - 20), height: 18),
            withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NoteTheme.primary, .paragraphStyle: paragraph])
    }
}
private final class DockMenuChoice: NSObject {
    let choose: () -> Void
    init(_ choose: @escaping () -> Void) { self.choose = choose }
    @objc func performChoice() { choose() }
}
private final class DockPlaceholder: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 12, yRadius: 12)
        NSColor.white.withAlphaComponent(0.12).setFill(); path.fill()
        NSColor.white.withAlphaComponent(0.7).setStroke(); path.lineWidth = 1.5
        path.setLineDash([5, 4], count: 2, phase: 0); path.stroke()
    }
}
