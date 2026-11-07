import AppKit

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
    private var panel: NotePanel?
    private let auxiliary = AuxiliaryWindows()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let symbol = NSImage(systemSymbolName: "note.text", accessibilityDescription: "DeskNodes")
        symbol?.isTemplate = true
        item.button?.image = symbol
        item.button?.toolTip = "DeskNodes · 临时预览（不保存）"
        item.menu = makeStatusMenu()
        statusItem = item
        showPreview(nil)
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let label = NSMenuItem(title: "N1 · 临时预览，不保存", action: nil, keyEquivalent: "")
        label.isEnabled = false
        menu.addItem(label)
        menu.addItem(.separator())
        add("查看便签预览", to: menu, action: #selector(showPreview(_:)))
        for title in ["新建便签（尚未实现）", "全部置顶 / 全部恢复（尚未实现）"] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
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
            ("撤销", Selector("undo:"), "z"),
            ("剪切", #selector(NSText.cut(_:)), "x"),
            ("复制", #selector(NSText.copy(_:)), "c"),
            ("粘贴", #selector(NSText.paste(_:)), "v"),
            ("全选", #selector(NSText.selectAll(_:)), "a")
        ] {
            edit.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        let redo = NSMenuItem(title: "重做", action: Selector("redo:"), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @objc private func showPreview(_ sender: Any?) {
        if panel == nil {
            let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
            panel = NotePanel(origin: NSPoint(x: visible.midX - 120, y: visible.maxY - 190))
        }
        panel?.showPreview()
    }
    @objc private func showHistory(_ sender: Any?) { auxiliary.show(.history) }
    @objc private func showSettings(_ sender: Any?) { auxiliary.show(.settings) }
    @objc private func quit(_ sender: Any?) { NSApp.terminate(sender) }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
    }
}
