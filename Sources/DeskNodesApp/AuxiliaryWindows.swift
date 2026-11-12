import AppKit
import SwiftUI
import DeskNodesPersistence

/// SwiftUI content and windows are created only when requested; both use the shared store.
@MainActor
final class AuxiliaryWindows {
    enum Destination: String, CaseIterable {
        case history = "历史记录"
        case settings = "设置"

    }
    private var controllers: [Destination: NSWindowController] = [:]

    private var history: HistoryPresentation?
    var settings: SettingsPresentation?
    /// Wires app-level actions (restore from 最近删除) into a newly allocated History model.
    var configureHistory: ((HistoryPresentation) -> Void)?

    func isVisible(_ destination: Destination) -> Bool { controllers[destination]?.window?.isVisible == true }

    func reloadHistoryIfVisible() {
        if controllers[.history]?.window?.isVisible == true { history?.reload() }
    }

    func show(_ destination: Destination, store: Store? = nil, historyMode: HistoryMode? = nil) {
        if destination == .history, history == nil {
            guard let store else { return }
            do {
                let today = try BusinessCalendar(timeZone: .current).day(at: Date(), settings: store.settings())
                history = HistoryPresentation(store: store, today: today)
                if let history { configureHistory?(history) }
            } catch {
                let alert = NSAlert()
                alert.messageText = "无法读取历史记录"
                alert.informativeText = String(describing: error)
                alert.runModal()
                return
            }
        }
        if destination == .history, let historyMode { history?.mode = historyMode }
        if destination == .history { history?.reload() }
        if destination == .history, history?.mode == .deleted { history?.reloadDeleted() }
        if destination == .settings { settings?.reload() }
        let controller: NSWindowController
        if let existing = controllers[destination] {
            controller = existing
        } else {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: destination == .history ? 1040 : 760, height: destination == .history ? 656 : 576),
                                  styleMask: destination == .history ? [.titled, .closable, .resizable, .miniaturizable] : [.titled, .closable], backing: .buffered, defer: false)
            window.title = destination.rawValue
            window.isReleasedWhenClosed = false
            if destination == .history, let history {
                window.collectionBehavior = [.fullScreenNone]
                window.contentMinSize = NSSize(width: 900, height: 656)
                let hosting = NSHostingController(rootView: HistoryView(model: history))
                hosting.sceneBridgingOptions = [.toolbars] // 日历 | 最近删除 switch lives in the title bar
                window.toolbarStyle = .unified
                window.contentViewController = hosting
            } else if let settings {
                window.collectionBehavior = [.fullScreenNone]
                window.contentViewController = NSHostingController(rootView: SettingsView(model: settings))
            }
            window.center()
            controller = NSWindowController(window: window)
            controllers[destination] = controller
        }
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }
}
