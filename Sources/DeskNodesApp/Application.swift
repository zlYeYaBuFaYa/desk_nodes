import AppKit
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
    private var statusItem: NSStatusItem?
    private var panels: [NoteID: NotePanel] = [:]
    private var actions: NoteActions?
    private var toast: DeletionToast?
    private var emptyWindow: NSPanel?
    private var expiryTimer: Timer?
    private let auxiliary = AuxiliaryWindows()

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
            refresh()
        } catch { report(error) }
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        add("新建便签", to: menu, action: #selector(createNote(_:)))
        let unfinished = NSMenuItem(title: "全部置顶 / 全部恢复（尚未实现）", action: nil, keyEquivalent: "")
        unfinished.isEnabled = false
        menu.addItem(unfinished)
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
        guard let actions else { return }
        do { let note = try actions.createNote(); refresh(); panels[note.id]?.makeKeyAndOrderFront(nil) }
        catch { report(error) }
    }
    private func refresh() {
        guard let actions else { return }
        do {
            let notes = try actions.store.notes()
            let ids = Set(notes.map(\.id))
            for id in Array(panels.keys) where !ids.contains(id) { panels.removeValue(forKey: id)?.close() }
            let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
            for (index, note) in notes.enumerated() {
                if let card = panels[note.id]?.contentView as? NoteCardView { card.refresh(note); continue }
                let panel = NotePanel(origin: NSPoint(x: visible.midX - 120 + CGFloat(index % 5) * 24,
                                                      y: visible.maxY - 300 - CGFloat(index % 5) * 24))
                panel.deletionUndo = { [weak self] in self?.routeDeletionUndo() ?? false }
                panel.contentView = NoteCardView(note: note, actions: actions,
                    changed: { [weak self] in self?.refresh() },
                    undoDelete: { [weak self] in self?.routeDeletionUndo() ?? false },
                    failure: { [weak self] in self?.report($0) })
                panels[note.id] = panel; panel.showNote()
            }
            emptyWindow?.close(); emptyWindow = nil
            if notes.isEmpty {
                let panel = NotePanel(origin: NSPoint(x: visible.midX - 120, y: visible.midY))
                panel.setContentSize(NSSize(width: 240, height: 100))
                panel.backgroundColor = .windowBackgroundColor
                panel.deletionUndo = { [weak self] in self?.routeDeletionUndo() ?? false }
                panel.title = "还没有便签"
                panel.isReleasedWhenClosed = false
                let button = NSButton(title: "＋ 新建便签", target: self, action: #selector(createNote(_:)))
                button.frame = NSRect(x: 50, y: 30, width: 140, height: 32)
                panel.contentView?.addSubview(button); panel.makeKeyAndOrderFront(nil); emptyWindow = panel
            }
            updateToast()
        } catch { report(error) }
    }
    private func updateToast() {
        guard let actions else { return }
        if actions.canUndoDeletion {
            if toast == nil {
                toast = DeletionToast { [weak self] in _ = self?.undoDeletion() }
                toast?.orderFrontRegardless()
            }
            if expiryTimer == nil {
                let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.tickExpiry() }
                }
                RunLoop.main.add(timer, forMode: .common)
                expiryTimer = timer
            }
        } else {
            toast?.close(); toast = nil; expiryTimer?.invalidate(); expiryTimer = nil
        }
    }
    private func tickExpiry() { actions?.expireDeletion(); updateToast() }
    @discardableResult private func undoDeletion() -> Bool {
        guard let actions, actions.canUndoDeletion else { return false }
        do { let restored = try actions.undoDeletion(); refresh(); return restored }
        catch { report(error); return true }
    }
    private func routeDeletionUndo() -> Bool {
        guard actions?.prefersDeletionUndo == true else { return false }
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
    private func report(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "无法保存便签"
        alert.informativeText = String(describing: error)
        alert.runModal()
    }
    @objc private func showHistory(_ sender: Any?) { auxiliary.show(.history) }
    @objc private func showSettings(_ sender: Any?) { auxiliary.show(.settings) }
    @objc private func quit(_ sender: Any?) { NSApp.terminate(sender) }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        expiryTimer?.invalidate()
        try? actions?.store.close()
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
    }
}
