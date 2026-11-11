import AppKit
import OSLog
import DeskNodesCore
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
    private var topmostMenuItem: NSMenuItem?
    private var statusItem: NSStatusItem?
    private var surfaces: NoteSurfaces?
    private var actions: NoteActions?
    private var docking: DockController?
    private var reveal: EdgeRevealController?
    private var toast: DeletionToast?
    private var notice: NoticeToast?
    /// The resident toolbar and desktop-wide presentation; it replaces the old empty-state window.
    private var desk: DesktopController?
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
        auxiliary.configureHistory = { [weak self] in self?.configureHistory($0) }
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
                surfaces = makeSurfaces(actions)
                desk = makeDesk(actions)
                docking = makeDocking(actions)
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
            refresh(.all)
            desk?.start()
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
                try self.surfaces?.flushEdits()
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
        reveal?.hasMarkedComposition == true || surfaces?.hasMarkedComposition == true
    }
    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        add("新建便签", to: menu, action: #selector(createNote(_:)))
        add("显示工具条", to: menu, action: #selector(revealToolbar(_:)))
        let toggle = NSMenuItem(title: "全部置顶", action: #selector(toggleTopmost(_:)), keyEquivalent: "")
        toggle.target = self; menu.addItem(toggle); topmostMenuItem = toggle
        let dockMenu = NSMenuItem(title: "停靠", action: nil, keyEquivalent: "")
        let submenu = NSMenu(); submenu.delegate = self; dockMenu.submenu = submenu; menu.addItem(dockMenu)
        menu.addItem(.separator())
        add("历史记录…", to: menu, action: #selector(showHistory(_:)))
        add("最近删除…", to: menu, action: #selector(showRecentlyDeleted(_:)))
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
        guard let actions, let desk else { return }
        do {
            // Creating while collapsed brings the existing notes back first.
            desk.expand()
            let height = NoteFrame.automaticHeight(content: NoteMetrics.headerHeight + NoteMetrics.rowHeight + NoteMetrics.footerHeight + 6)
            let (frame, displayID) = desk.newNoteFrame(height: height)
            let note = try actions.createNote(frame: frame, displayID: displayID)
            refresh()
            surfaces?.select(note.id)
            // A global hotkey or the non-activating toolbar arrives while another app is
            // active: take keyboard focus first, or the first keystrokes would go there.
            NSApp.activate(ignoringOtherApps: true)
            if let panel = surfaces?.panels[note.id] {
                panel.makeKeyAndOrderFront(nil)
                if let editor = (panel.contentView as? NoteCardView)?.firstEditor { panel.makeFirstResponder(editor) }
            }
        }
        catch { report(error) }
    }
    /// Toolbar "删除": only the selected, visible note. Typed text is committed first so
    /// the undo toast restores it; a composition in progress is never discarded.
    private func deleteSelected() {
        guard let actions, let surfaces, let desk, desk.state == .expanded, let id = surfaces.selection,
              let panel = surfaces.panels[id], !panel.suppressed else { return }
        guard !hasMarkedComposition else { report(StoreError.invalid("请先完成输入法组词，再删除便签")); return }
        (panel.contentView as? NoteCardView)?.flushBeforeFocusLoss()
        do { try actions.deleteNote(id); refresh() } catch { report(error) }
    }
    @objc private func revealToolbar(_ sender: Any?) { desk?.revealToolbar() }
    /// Reconciles windows with the store; see `NoteSurfaces` for what each scope touches.
    private func refresh(_ scope: RefreshScope = .changes) {
        guard let surfaces else { return }
        do {
            let notes = try surfaces.refresh(scope).notes
            desk?.sync(notes)
            updateToast()
        } catch { report(error) }
    }
    private func makeDesk(_ actions: NoteActions) -> DesktopController {
        let desk = DesktopController(actions: actions, defaults: .standard())
        desk.surfaces = { [weak self] in self?.surfaces }
        desk.docking = { [weak self] in self?.docking }
        desk.refresh = { [weak self] scope in self?.refresh(scope) }
        desk.canMutate = { [weak self] in self?.hasMarkedComposition == false }
        desk.failure = { [weak self] in self?.report($0) }
        desk.toolbar.perform = { [weak self] action in
            switch action {
            case .create: self?.createNote(nil)
            case .delete: self?.deleteSelected()
            case .arrange: self?.desk?.arrange()
            case .collapse: self?.desk?.toggleCollapse()
            case .settings: self?.showSettings(nil)
            }
        }
        surfaces?.hidden = { [weak desk] in desk?.isHidden($0) ?? false }
        surfaces?.selectionChanged = { [weak desk] in desk?.updateToolbar() }
        return desk
    }
    private func makeSurfaces(_ actions: NoteActions) -> NoteSurfaces {
        let surfaces = NoteSurfaces(actions: actions, changed: { [weak self] in self?.refresh() },
            undo: { [weak self] in self?.routeDeletionUndo() ?? false },
            canMutate: { [weak self] in self?.hasMarkedComposition == false },
            failure: { [weak self] in self?.report($0) })
        surfaces.layoutDock = { [weak self] panels, modes, changed, strips in
            self?.docking?.layout(panels: panels, modes: modes, changed: changed, strips: strips)
        }
        surfaces.refreshReveal = { [weak self] notes, items, changed in
            self?.reveal?.refresh(notes, items: items, changed: changed)
        }
        return surfaces
    }
    private func makeDocking(_ actions: NoteActions) -> DockController {
        // Tab selection, paging and drags are UI state the store diff cannot see.
        let docking = DockController(actions: actions, canMutate: { [weak self] in self?.hasMarkedComposition == false },
                       changed: { [weak self] in self?.refresh(.layout) }, failure: { [weak self] in self?.report($0) })
        docking.suppressed = desk?.state.targetsCollapsed ?? false
        return docking
    }
    @objc private func screensChanged() {
        desk?.screensChanged()
        do { try actions?.reconcileScreens(DockController.screens()); refresh(.all) } catch { report(error) }
    }
    @objc private func toggleTopmost(_ sender: Any?) {
        guard let surfaces else { return }
        var modes = surfaces.modes; modes.allTopmost.toggle()
        topmostMenuItem?.title = modes.allTopmost ? "全部恢复" : "全部置顶"
        surfaces.apply(modes)
    }
    func applicationDidResignActive(_ notification: Notification) {
        surfaces?.lowerTransientRaises()
    }
    private func updateToast() {
        guard let actions else { return }
        if actions.canUndoDeletion {
            if toast == nil {
                toast = DeletionToast { [weak self] in _ = self?.undoDeletion() }
                toast?.orderFrontRegardless()
            }
            toast?.update(count: actions.recoverableDeletionCount, note: actions.latestDeletionIsNote)
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
        actions?.expireDeletion(); updateToast()
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
    @objc private func showRecentlyDeleted(_ sender: Any?) {
        auxiliary.show(.history, store: actions?.store, historyMode: .deleted)
    }
    private func configureHistory(_ history: HistoryPresentation) {
        history.loadDeleted = { [weak self] in
            guard let actions = self?.actions else { throw StoreError.closed }
            return try actions.recentlyDeleted()
        }
        history.restoreDeleted = { [weak self] target in try self?.restoreDeleted(target) }
    }
    private func restoreDeleted(_ target: DeletedTarget) throws {
        guard let actions else { throw StoreError.closed }
        guard !hasMarkedComposition else { throw StoreError.invalid("请先完成输入法组词，再恢复") }
        switch target {
        case .note(let id):
            // An explicit restore should be seen, so a collapsed desk opens first.
            desk?.expand()
            try actions.restoreDeletedNote(id)
            // The display it lived on may be gone; bring it back on screen.
            try actions.reconcileScreens(DockController.screens())
            refresh(); surfaces?.panels[id]?.orderFrontRegardless()
        case .item(let id):
            try actions.restoreDeletedItem(id)
            refresh()
        }
    }
    @objc private func showSettings(_ sender: Any?) {
        guard let actions else { return }
        if auxiliary.settings == nil {
            auxiliary.settings = SettingsPresentation(actions: actions, login: login,
                changed: { [weak self] in self?.refresh(.layout); self?.catchUpDay() },
                hotkey: { [weak self] key, persist in
                    guard let self else { throw StoreError.closed }
                    if self.globalHotkey == nil { self.globalHotkey = try GlobalHotkey { [weak self] in self?.createNote(nil) } }
                    try self.globalHotkey?.apply(key, persist: persist)
                }, export: { [weak self] in
                    guard let self else { throw StoreError.closed }
                    return try actions.store.exportBackup {
                        guard !self.hasMarkedComposition else { return false }
                        try self.surfaces?.flushEdits()
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
        for card in surfaces?.cards ?? [] { card.prepareForRemoval() }
        reveal?.invalidateAfterImport(); reveal = nil
        docking?.invalidateAfterImport()
        surfaces?.discardAll(); actions.invalidateUndoAfterImport()
        topmostMenuItem?.title = "全部置顶"
        docking = makeDocking(actions)
        reveal = EdgeRevealController(actions: actions, changed: { [weak self] in self?.refresh() },
            undo: { [weak self] in self?.routeDeletionUndo() ?? false },
            restoreDeletion: { [weak self] in self?.undoDeletion() ?? false },
            canMutate: { [weak self] in self?.hasMarkedComposition == false }, failure: { [weak self] in self?.report($0) })
        rolloverDeferred = false
        refresh(.all); auxiliary.reloadHistoryIfVisible()
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
            try surfaces?.flushEdits()
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
