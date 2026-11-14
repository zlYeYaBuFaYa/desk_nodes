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

    private(set) var history: HistoryPresentation?
    private var historyKeys: Any?
    var settings: SettingsPresentation?
    /// Wires app-level actions (restore from 最近删除) into a newly allocated History model.
    var configureHistory: ((HistoryPresentation) -> Void)?

    func isVisible(_ destination: Destination) -> Bool { controllers[destination]?.window?.isVisible == true }

    func reloadHistoryIfVisible() {
        if controllers[.history]?.window?.isVisible == true { history?.reload() }
    }

    /// `day` opens the calendar on that day.
    func show(_ destination: Destination, store: Store? = nil, historyMode: HistoryMode? = nil, day: HistoryDay? = nil) {
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
        if destination == .history, let day { history?.select(day) }
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
                historyKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
                    guard let window, event.window === window, let history = self?.history else { return event }
                    return Self.calendarKey(event, in: window, history) ? nil : event
                }
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
    /// ←/→ a day, ↑/↓ a week, ⌥←/⌥→ a month, ⌘T today, on the calendar only. Plain arrows
    /// stay with whatever already uses them: detail text being read or selected, and with
    /// Full Keyboard Access the focused control (the 日历|最近删除 switch, a day).
    private static func calendarKey(_ event: NSEvent, in window: NSWindow, _ history: HistoryPresentation) -> Bool {
        guard history.mode == .calendar else { return false }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags == .command, event.charactersIgnoringModifiers == "t" { history.showToday(); return true }
        guard flags.isEmpty || flags == .option else { return false }
        if window.firstResponder is NSTextView { return false }
        if flags.isEmpty && NSApp.isFullKeyboardAccessEnabled { return false }
        let month = flags == .option
        switch event.keyCode {
        case 123: month ? history.navigate(-1) : history.step(days: -1)
        case 124: month ? history.navigate(1) : history.step(days: 1)
        case 126 where !month: history.step(days: -7)
        case 125 where !month: history.step(days: 7)
        default: return false
        }
        return true
    }
}
