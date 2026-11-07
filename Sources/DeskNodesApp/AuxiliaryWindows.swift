import AppKit
import SwiftUI

/// Created only on demand. N8/N9 will replace these views with real features.
@MainActor
final class AuxiliaryWindows {
    enum Destination: String, CaseIterable {
        case history = "历史记录"
        case settings = "设置"

        var detail: String {
            switch self {
            case .history: return "尚未实现。后续将提供只读日历与每日快照；当前没有历史数据或统计。"
            case .settings: return "尚未实现。后续将提供通用、停靠、边缘唤出、快捷键和备份设置。"
            }
        }
    }
    private var controllers: [Destination: NSWindowController] = [:]

    func show(_ destination: Destination) {
        let controller: NSWindowController
        if let existing = controllers[destination] {
            controller = existing
        } else {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 280),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = destination.rawValue
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: UnfinishedView(destination: destination))
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
