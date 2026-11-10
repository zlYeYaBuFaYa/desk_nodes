import AppKit
import OSLog
import DeskNodesPersistence
import DeskNodesActions

@main
@MainActor
struct DeskNodesApplication {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var modes = WindowModes()
    private var topmostMenuItem: NSMenuItem?
    private var statusItem: NSStatusItem?
    private var panels: [NoteID: NotePanel] = [:]
    private var actions: NoteActions?
    private var docking: DockController?
    private var reveal: EdgeRevealController?
    private var toast: DeletionToast?
    private var notice: NoticeToast?
    private var emptyWindow: NSPanel?
    private let log = Logger(subsystem: "local.desknodes.native", category: "app")
    private var expiryTimer: Timer?
    private var rolloverTimer: Timer?
    private var rollingOver = false
    private var rolloverDeferred = false
    private let auxiliary = AuxiliaryWindows()
    private let login = LoginService()
    private var globalHotkey: GlobalHotkey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let symbol = NSImage(systemSymbolName: "note.text", accessibilityDescription: "DeskNodes")
        symbol?.isTemplate = true
        item.button?.image = symbol
        item.button?.toolTip = "DeskNodes"
        item.menu = makeStatusMenu()
        statusItem = item
        do {
            actions = NoteActions(store: try Store(url: NativeStorage.databaseURL()))
            if let actions {
                docking = DockController(actions: actions, canMutate: { [weak self] in self?.hasMarkedComposition == false }, changed: { [weak self] in self?.refresh() }, failure: { [weak self] in self?.report($0) })
            }
            NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
            if let actions {
                reveal = EdgeRevealController(actions: actions, changed: { [weak self] in self?.refresh() },
                    undo: { [weak self] in self?.routeDeletionUndo() ?? false },
                    restoreDeletion: { [weak self] in self?.undoDeletion() ?? false },
                    canMutate: { [weak self] in self?.hasMarkedComposition == false },
                    failure: { [weak self] in self?.report($0) })
            }
            installRolloverScheduler()
            catchUpDay()
            try actions?.reconcileScreens(DockController.screens())
            refresh()
            if let actions {
                // Registration errors must not prevent the first-launch consent question.
                do {
                    globalHotkey = try GlobalHotkey { [weak self] in self?.createNote(nil) }
                    try globalHotkey?.apply(Hotkey(actions.store.preferences().hotkey), persist: {})
                } catch { report(error) }
                do { try login.askOnFirstLaunch(store: actions.store) } catch { report(error, modal: true) }
            }
        } catch { report(error, modal: true) } // e.g. the database cannot be opened
    }

    private func installRolloverScheduler() {
        let center = NotificationCenter.default
        for name in [Notification.Name.NSSystemTimeZoneDidChange, NSNotification.Name.NSSystemClockDidChange] {
            center.addObserver(self, selector: #selector(dayEnvironmentChanged), name: name, object: nil)
        }
        // A committed composition retries on the next run-loop turn, before the next timer.
        center.addObserver(self, selector: #selector(editorChanged), name: NSText.didChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(dayEnvironmentChanged), name: NSWorkspace.didWakeNotification, object: nil)
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.catchUpDay() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        rolloverTimer = timer
    }
    @objc private func dayEnvironmentChanged() { catchUpDay() }
    @objc private func editorChanged() {
        guard rolloverDeferred else { return }
        DispatchQueue.main.async { [weak self] in self?.catchUpDay() }
    }
    private func catchUpDay() {
        guard !rollingOver, let actions else { return }
        rollingOver = true; defer { rollingOver = false }
        do {
            // Resolve the current timezone on each trigger, never cache an offset across DST.
            let calendar = try BusinessCalendar(timeZone: .current)
            let result = try actions.store.rollover(using: calendar) {
                if self.hasMarkedComposition { return false }
                for panel in self.panels.values {
                    try (panel.contentView as? NoteCardView)?.flushRolloverEdits()
                }
                try self.reveal?.flushEdits()
                return true
            }
            rolloverDeferred = result == .deferredEditing
            if case .advanced(let snapshot) = result {
                refresh(); auxiliary.reloadHistoryIfVisible()
                writeAutomaticBackup(day: snapshot.day)
            }
        } catch { report(error) }
    }
    /// One rolling SQLite copy per closed day; failure never blocks the rollover itself.
    private func writeAutomaticBackup(day: HistoryDay) {
        guard let store = actions?.store else { return }
        do { try AutomaticBackup.write(store, day: day, to: AutomaticBackup.directory()) }
        catch { log.error("automatic backup failed: \(String(describing: error), privacy: .public)") }
    }

    private var hasMarkedComposition: Bool {
        reveal?.hasMarkedComposition == true || panels.values.contains {
            ($0.contentView as? NoteCardView)?.hasMarkedComposition == true
        }
    }
    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        add("新建便签", to: menu, action: #selector(createNote(_:)))
        let toggle = NSMenuItem(title: "全部置顶", action: #selector(toggleTopmost(_:)), keyEquivalent: "")
        toggle.target = self; menu.addItem(toggle); topmostMenuItem = toggle
        let dockMenu = NSMenuItem(title: "停靠", action: nil, keyEquivalent: "")
        let submenu = NSMenu(); submenu.delegate = self; dockMenu.submenu = submenu; menu.addItem(dockMenu)
        menu.addItem(.separator())
        add("历史记录…", to: menu, action: #selector(showHistory(_:)))
        add("设置…", to: menu, action: #selector(showSettings(_:)), key: ",")
        menu.addItem(.separator())
        add("退出 DeskNodes", to: menu, action: #selector(quit(_:)), key: "q")
        return menu
    }

    private func add(_ title: String, to menu: NSMenu, action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    private func installMainMenu() {
        // Accessory apps still need a responder menu for native editing shortcuts.
        let main = NSMenu()
        let appItem = NSMenuItem(title: "DeskNodes", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "DeskNodes")
        add("新建便签", to: appMenu, action: #selector(createNote(_:)), key: "n")
        add("设置…", to: appMenu, action: #selector(showSettings(_:)), key: ",")
        appMenu.addItem(.separator())
        add("退出 DeskNodes", to: appMenu, action: #selector(quit(_:)), key: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "编辑")
        for (title, action, key) in [
            ("撤销", #selector(performUndo(_:)), "z"),
            ("剪切", #selector(NSText.cut(_:)), "x"),
            ("复制", #selector(NSText.copy(_:)), "c"),
            ("粘贴", #selector(NSText.paste(_:)), "v"),
            ("全选", #selector(NSText.selectAll(_:)), "a")
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            if key == "z" { item.target = self }
            edit.addItem(item)
        }
        let redo = NSMenuItem(title: "重做", action: Selector("redo:"), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @objc private func createNote(_ sender: Any?) {
        guard !hasMarkedComposition else { return }
        guard let actions else { return }
        do {
            // New notes open on the display under the pointer, cascading from its top centre.
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.screens.first
            let mapped = DockController.screens()
            let displayID = screen.flatMap { NSScreen.screens.firstIndex(of: $0) }.flatMap { mapped.indices.contains($0) ? mapped[$0].persistentID : nil }
            var frame: NoteFrame?
            if let visible = screen?.visibleFrame {
                let offset = Double(panels.count % 6) * 24
                frame = NoteFrame(x: visible.midX - 120 + offset, y: visible.maxY - 180 - offset)
            }
            let note = try actions.createNote(frame: frame, displayID: displayID)
            refresh()
            // A global hotkey arrives while another app is active: take keyboard focus
            // first, or the first keystrokes would still go to that app.
            NSApp.activate(ignoringOtherApps: true)
            if let panel = panels[note.id] {
                panel.makeKeyAndOrderFront(nil)
                if let editor = (panel.contentView as? NoteCardView)?.firstEditor { panel.makeFirstResponder(editor) }
            }
        }
        catch { report(error) }
    }
    private func refresh() {
        guard let actions else { return }
        do {
            let notes = try actions.store.notes()
            let ids = Set(notes.map(\.id))
            for id in Array(panels.keys) where !ids.contains(id) {
                (panels[id]?.contentView as? NoteCardView)?.prepareForRemoval()
                panels.removeValue(forKey: id)?.dismissNote()
            }
            let visible = NSScreen.screens.first?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
            for (index, note) in notes.enumerated() {
                if let panel = panels[note.id], let card = panel.contentView as? NoteCardView {
                    card.refresh(note); try configure(panel, note: note); continue
                }
                let panel = NotePanel(origin: NSPoint(x: visible.midX - 120 + CGFloat(index % 5) * 24,
                                                      y: visible.maxY - 300 - CGFloat(index % 5) * 24))
                panel.deletionUndo = { [weak self] in self?.routeDeletionUndo() ?? false }
                panel.contentView = NoteCardView(note: note, actions: actions,
                    changed: { [weak self] in self?.refresh() },
                    undoDelete: { [weak self] in self?.routeDeletionUndo() ?? false },
                    failure: { [weak self] in self?.report($0) })
                (panel.contentView as? NoteCardView)?.canMutate = { [weak self] in self?.hasMarkedComposition == false }
                panels[note.id] = panel; try configure(panel, note: note); panel.showNote()
            }
            // The empty state is created once and never takes focus; it stays out of the
            // way while the last deletion can still be undone from the toast.
            if !notes.isEmpty || actions.canUndoDeletion { emptyWindow?.close(); emptyWindow = nil }
            else if emptyWindow == nil {
                let panel = NotePanel(origin: NSPoint(x: visible.midX - 120, y: visible.midY))
                panel.setContentSize(NSSize(width: 240, height: 100))
                panel.backgroundColor = .windowBackgroundColor
                panel.deletionUndo = { [weak self] in self?.routeDeletionUndo() ?? false }
                panel.title = "还没有便签"
                panel.isReleasedWhenClosed = false
                let button = NSButton(title: "＋ 新建便签", target: self, action: #selector(createNote(_:)))
                button.frame = NSRect(x: 50, y: 30, width: 140, height: 32)
                panel.contentView?.addSubview(button); panel.orderFrontRegardless(); emptyWindow = panel
            }
            docking?.layout(panels: panels, modes: modes)
            reveal?.refresh(notes)
            updateToast()
        } catch { report(error) }
    }
    private func configure(_ panel: NotePanel, note: Note) throws {
        guard let actions else { return }
        panel.choice = note.level; panel.modes = modes; panel.applyLevel()
        var expanded: NoteFrame
        switch note.placement {
        case .free(_, let x, let y, let width, let height):
            expanded = NoteFrame(x: x, y: y, width: width, height: height)
        case .dock: return // DockController owns strip geometry; free geometry stays durable.
        }
        if note.automaticHeight {
            let availableHeight = DockGeometry.screen(note.placement.displayID, screens: DockController.screens())?.available.height ?? 480
            let height = min(availableHeight, NoteFrame.automaticHeight(content: (panel.contentView as? NoteCardView)?.preferredHeight(width: expanded.width) ?? 120))
            expanded.y += expanded.height - height; expanded.height = height
        }
        let changedCollapse = panel.frame.height == 32 ? !note.collapsed : note.collapsed
        panel.present(expanded, collapsed: note.collapsed, animate: changedCollapse)
        if case .free = note.placement {
            let placement = Placement.free(displayID: {
                if case .free(let display, _, _, _, _) = note.placement { return display }; return nil
            }(), x: expanded.x, y: expanded.y, width: expanded.width, height: expanded.height)
            if placement != note.placement, expanded.width >= 200, expanded.height >= 120 { try actions.finalGeometry(note.id, frame: expanded) }
        }
    }
    @objc private func screensChanged() {
        do { try actions?.reconcileScreens(DockController.screens()); refresh() } catch { report(error) }
    }
    @objc private func toggleTopmost(_ sender: Any?) {
        modes.allTopmost.toggle()
        topmostMenuItem?.title = modes.allTopmost ? "全部恢复" : "全部置顶"
        for panel in panels.values { panel.modes = modes; panel.applyLevel() }
        docking?.layout(panels: panels, modes: modes)
    }
    func applicationDidResignActive(_ notification: Notification) {
        for panel in panels.values { panel.temporarilyRaised = false; panel.applyLevel() }
    }
    private func updateToast() {
        guard let actions else { return }
        if actions.canUndoDeletion {
            if toast == nil {
                toast = DeletionToast { [weak self] in _ = self?.undoDeletion() }
                toast?.orderFrontRegardless()
            }
            toast?.update(count: actions.recoverableDeletionCount)
            if expiryTimer == nil {
                let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.tickExpiry() }
                }
                RunLoop.main.add(timer, forMode: .common)
                expiryTimer = timer
            }
        } else {
            toast?.dismiss(); toast = nil; expiryTimer?.invalidate(); expiryTimer = nil
        }
    }
    private func tickExpiry() {
        let before = actions?.canUndoDeletion
        actions?.expireDeletion(); updateToast()
        // When the last deletion expires, the empty state may need to appear.
        if before == true, actions?.canUndoDeletion == false { refresh() }
    }
    @discardableResult private func undoDeletion() -> Bool {
        guard !hasMarkedComposition, let actions, actions.canUndoDeletion else { return false }
        do { let restored = try actions.undoDeletion(); refresh(); return restored }
        catch { report(error); return true }
    }
    private func routeDeletionUndo() -> Bool {
        guard !hasMarkedComposition, actions?.prefersDeletionUndo == true else { return false }
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
        return undoDeletion()
    }
    @objc private func performUndo(_ sender: Any?) {
        if routeDeletionUndo() { return }
        let responder = NSApp.keyWindow?.firstResponder
        if responder?.tryToPerform(Selector("undo:"), with: sender) == true { return }
        let manager = (responder as? NSTextView)?.undoManager ?? NSApp.keyWindow?.undoManager
        if manager?.canUndo == true { manager?.undo() }
    }
    /// Background failures (timers, typing, edge polling) never block with a modal alert:
    /// they are logged and shown in a short non-activating notice. Modal is reserved for
    /// failures of an explicit one-time request.
    private func report(_ error: Error, modal: Bool = false) {
        let message = String(describing: error)
        log.error("\(message, privacy: .public)")
        guard modal else {
            if notice == nil { notice = NoticeToast { [weak self] in self?.notice = nil } }
            notice?.show("无法完成操作：\(message)")
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "无法完成操作"
        alert.informativeText = message
        alert.runModal()
    }
    @objc private func showHistory(_ sender: Any?) { auxiliary.show(.history, store: actions?.store) }
    @objc private func showSettings(_ sender: Any?) {
        guard let actions else { return }
        if auxiliary.settings == nil {
            auxiliary.settings = SettingsPresentation(actions: actions, login: login,
                changed: { [weak self] in self?.refresh(); self?.catchUpDay() },
                hotkey: { [weak self] key, persist in
                    guard let self else { throw StoreError.closed }
                    if self.globalHotkey == nil { self.globalHotkey = try GlobalHotkey { [weak self] in self?.createNote(nil) } }
                    try self.globalHotkey?.apply(key, persist: persist)
                }, export: { [weak self] in
                    guard let self else { throw StoreError.closed }
                    return try actions.store.exportBackup {
                        guard !self.hasMarkedComposition else { return false }
                        for panel in self.panels.values { try (panel.contentView as? NoteCardView)?.flushRolloverEdits() }
                        try self.reveal?.flushEdits(); return true
                    }
                }, importBackup: { [weak self] backup in
                    guard let self else { throw StoreError.closed }
                    try self.importBackup(backup)
                }, canImport: { [weak self] in self?.hasMarkedComposition == false })
        }
        auxiliary.show(.settings)
    }
    private func importBackup(_ backup: ValidatedBackup) throws {
        guard let actions, !hasMarkedComposition else { throw StoreError.invalid("请先完成输入法组词，再导入备份") }
        if globalHotkey == nil { globalHotkey = try GlobalHotkey { [weak self] in self?.createNote(nil) } }
        // A conflicting imported shortcut refuses the entire import. Failed replacement
        // retires the candidate only; old data/UI/binding remain usable.
        try globalHotkey?.apply(Hotkey(backup.contents.preferences.hotkey)) {
            try actions.store.replace(with: backup, confirmed: true, prepareEditing: { !self.hasMarkedComposition })
        }
        // Invalidate even if imported IDs match. Relinquishing focus cannot flush old data.
        for panel in panels.values { (panel.contentView as? NoteCardView)?.prepareForRemoval() }
        reveal?.invalidateAfterImport(); reveal = nil
        docking?.invalidateAfterImport()
        for panel in panels.values { panel.undoManager?.removeAllActions(); panel.close() }
        panels = [:]; actions.invalidateUndoAfterImport()
        modes = WindowModes(); topmostMenuItem?.title = "全部置顶"
        docking = DockController(actions: actions, canMutate: { [weak self] in self?.hasMarkedComposition == false }, changed: { [weak self] in self?.refresh() }, failure: { [weak self] in self?.report($0) })
        reveal = EdgeRevealController(actions: actions, changed: { [weak self] in self?.refresh() },
            undo: { [weak self] in self?.routeDeletionUndo() ?? false },
            restoreDeletion: { [weak self] in self?.undoDeletion() ?? false },
            canMutate: { [weak self] in self?.hasMarkedComposition == false }, failure: { [weak self] in self?.report($0) })
        rolloverDeferred = false
        refresh(); auxiliary.reloadHistoryIfVisible()
        // No autostart registration and no rollover/capture on import.
    }
    @objc private func quit(_ sender: Any?) { NSApp.terminate(sender) }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !hasMarkedComposition else {
            report(StoreError.invalid("请先完成输入法组词，再退出 DeskNodes。"))
            return .terminateCancel
        }
        do {
            for panel in panels.values { try (panel.contentView as? NoteCardView)?.flushRolloverEdits() }
            try reveal?.flushEdits()
            return .terminateNow
        } catch { report(error); return .terminateCancel }
    }
    func applicationWillTerminate(_ notification: Notification) {
        globalHotkey?.stop()
        expiryTimer?.invalidate()
        rolloverTimer?.invalidate()
        reveal?.stop()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        try? actions?.store.close()
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
    }
}


extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) { docking?.populateControls(menu) }
}
