import AppKit
import SwiftUI
import DeskNodesPersistence

/// Created only on demand. History reads the shared store; Settings remains reserved for N9.
@MainActor
final class AuxiliaryWindows {
    enum Destination: String, CaseIterable {
        case history = "历史记录"
        case settings = "设置"

        var detail: String {
            switch self {
            case .history: return "只读日历与每日快照"
            case .settings: return "尚未实现。后续将提供通用、停靠、边缘唤出、快捷键和备份设置。"
            }
        }
    }
    private var controllers: [Destination: NSWindowController] = [:]

    private var history: HistoryPresentation?

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
        let controller: NSWindowController
        if let existing = controllers[destination] {
            controller = existing
        } else {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: destination == .history ? 1040 : 480, height: destination == .history ? 656 : 280),
                                  styleMask: destination == .history ? [.titled, .closable, .resizable, .miniaturizable] : [.titled, .closable], backing: .buffered, defer: false)
            window.title = destination.rawValue
            window.isReleasedWhenClosed = false
            if destination == .history, let history {
                window.collectionBehavior = [.fullScreenNone]
                window.contentMinSize = NSSize(width: 900, height: 656)
                window.contentViewController = NSHostingController(rootView: HistoryView(model: history))
            } else {
                window.contentViewController = NSHostingController(rootView: UnfinishedView(destination: destination))
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

private struct UnfinishedView: View {
    let destination: AuxiliaryWindows.Destination
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(destination.rawValue).font(.system(size: 20, weight: .semibold))
            Text("N1 · 界面基础").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text(destination.detail).font(.system(size: 13)).foregroundStyle(.secondary)
            Divider()
            Text("当前便签仅为临时预览，编辑内容不会保存。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
