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

    func reloadHistoryIfVisible() {
        if controllers[.history]?.window?.isVisible == true { history?.reload() }
    }

    func show(_ destination: Destination, store: Store? = nil) {
        if destination == .history, history == nil {
            guard let store else { return }
            do {
                let today = try BusinessCalendar(timeZone: .current).day(at: Date(), settings: store.settings())
                history = HistoryPresentation(store: store, today: today)
            } catch {
                let alert = NSAlert()
                alert.messageText = "无法读取历史记录"
                alert.informativeText = String(describing: error)
                alert.runModal()
                return
            }
        }
        if destination == .history { history?.reload() }
        if destination == .settings { settings?.reload() }
        let controller: NSWindowController
        if let existing = controllers[destination] {
            controller = existing
        } else {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: destination == .history ? 1040 : 760, height: destination == .history ? 656 : 680),
                                  styleMask: destination == .history ? [.titled, .closable, .resizable, .miniaturizable] : [.titled, .closable], backing: .buffered, defer: false)
            window.title = destination.rawValue
            window.isReleasedWhenClosed = false
            if destination == .history, let history {
                window.collectionBehavior = [.fullScreenNone]
                window.contentMinSize = NSSize(width: 900, height: 656)
                window.contentViewController = NSHostingController(rootView: HistoryView(model: history))
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
