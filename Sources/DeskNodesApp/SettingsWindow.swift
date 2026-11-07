import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ServiceManagement
import DeskNodesPersistence
import DeskNodesActions

@MainActor
final class SettingsPresentation: ObservableObject {
    let actions: NoteActions
    let login: LoginService
    let changed: () -> Void
    let hotkey: (Hotkey, () throws -> Void) throws -> Void
    let export: () throws -> Data
    let importBackup: (ValidatedBackup) throws -> Void
    let canImport: () -> Bool
    @Published var settings = Settings()
    @Published var preferences = NativePreferences()
    @Published var shortcut = "Control+Option+N"
    @Published var message: String?
    @Published var loginEnabled = false
    @Published var loginExplanation = ""
    @Published var dockExplanation = ""
    @Published var displays: [(String, String)] = []
    init(actions: NoteActions, login: LoginService, changed: @escaping () -> Void,
         hotkey: @escaping (Hotkey, () throws -> Void) throws -> Void,
         export: @escaping () throws -> Data, importBackup: @escaping (ValidatedBackup) throws -> Void,
         canImport: @escaping () -> Bool = { true }) {
        self.actions = actions; self.login = login; self.changed = changed
        self.hotkey = hotkey; self.export = export; self.importBackup = importBackup; self.canImport = canImport
        reload()
    }
    func reload() {
        do {
            settings = try actions.store.settings(); preferences = try actions.store.preferences()
            shortcut = preferences.hotkey
            displays = zip(DockController.screens(), NSScreen.screens).compactMap { screen, native in
                screen.persistentID.map { ($0, native.localizedName) }
            }
            let orientation = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation")
            let side = settings.edgePreference.resolved(dock: orientation) == .left ? "左侧" : "右侧"
            let dock = ["bottom":"底部", "left":"左侧", "right":"右侧"][orientation ?? ""]
            dockExplanation = dock.map { "Dock 在屏幕\($0)，当前使用\(side)。" } ?? "无法读取 Dock 位置；自动模式回退到右侧。当前使用\(side)。"
            if let id = settings.displayID, !displays.contains(where: { $0.0 == id }) {
                displays.append((id, "不可用显示器（暂用主显示器）"))
            }
            loginEnabled = login.enabled; loginExplanation = login.explanation
        } catch { message = String(describing: error) }
    }
    func saveSettings(docking: Bool = false) {
        perform {
            if docking && !canImport() { throw StoreError.invalid("请先完成输入法组词，再调整停靠条") }
            if docking { try actions.dockPreference(edge: settings.dockEdge, displayID: settings.displayID) }
            else { try actions.store.update(settings) }
            changed()
        }
        reload()
    }
    func saveHotkey() {
        perform {
            let parsed = try Hotkey(shortcut)
            var updated = try actions.store.preferences(); updated.hotkey = parsed.canonical
            try hotkey(parsed) { try self.actions.store.update(updated) }
            preferences = updated; shortcut = updated.hotkey
        }
    }
    func toggleLogin(_ value: Bool) {
        perform { try login.setEnabled(value, store: actions.store) }
        reload()
    }
    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
    func exportFile() {
        perform {
            let data = try export() // Composition gate and owning-editor flush precede file output.
            let panel = NSSavePanel(); panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "DeskNodes-backup.json"; panel.title = "导出完整备份"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
        }
    }
    func importFile() {
        perform {
            guard canImport() else { throw StoreError.invalid("请先完成输入法组词，再导入备份") }
            let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
            panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
            panel.title = "导入原生完整备份"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            let backup = try Store.validateBackup(Data(contentsOf: url))
            let alert = NSAlert(); alert.alertStyle = .warning
            alert.messageText = "替换全部本机数据？"
            alert.informativeText = "将替换所有便签、事项、历史记录、设置和布局。此操作无法撤销，请先导出备份。导入的自动启动意愿不会注册系统登录项。"
            alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "替换全部数据")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
            try importBackup(backup); reload()
        }
    }
    private func perform(_ operation: () throws -> Void) {
        message = nil
        do { try operation() } catch { message = String(describing: error) }
    }
}

@MainActor
struct SettingsView: View {
    @ObservedObject var model: SettingsPresentation
    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack { Text(title); Spacer(); content() }.frame(minHeight: 40).padding(.horizontal, 14)
    }
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4)
            VStack(spacing: 0, content: content).background(Color(nsColor: NoteTheme.dynamic("FFFFFF", "302E2B")))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                group("通用") {
                    row("开机时自动启动") {
                        Toggle("开机时自动启动", isOn: Binding(get: { model.loginEnabled }, set: { model.toggleLogin($0) }))
                            .labelsHidden().toggleStyle(.switch)
                    }
                    Divider()
                    row("每天跨天时间") {
                        Picker("每天跨天时间", selection: Binding(get: { model.settings.rolloverHour }, set: {
                            model.settings.rolloverHour = $0; model.saveSettings()
                        })) {
                            ForEach(0..<24, id: \.self) { Text(String(format: "%02d 时", $0)).tag($0) }
                        }.labelsHidden().frame(width: 100)
                        Picker("分钟", selection: Binding(get: { model.settings.rolloverMinute }, set: {
                            model.settings.rolloverMinute = $0; model.saveSettings()
                        })) { ForEach(0..<60, id: \.self) { Text(String(format: "%02d 分", $0)).tag($0) } }
                            .labelsHidden().frame(width: 90)
                    }
                }
                Text(model.loginExplanation + " 跨天范围 00:00–23:59，默认 04:00。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Button("在系统设置中查看登录项…") { model.openLoginSettings() }
                group("停靠条") {
                    row("停靠位置") {
                        Picker("停靠位置", selection: Binding(get: { model.settings.dockEdge }, set: {
                            model.settings.dockEdge = $0; model.saveSettings(docking: true)
                        })) {
                            Text("顶部").tag(DockEdge.top); Text("左侧").tag(DockEdge.left); Text("右侧").tag(DockEdge.right)
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 220)
                    }
                    Divider()
                    row("显示在") {
                        Picker("显示在", selection: Binding(get: { model.settings.displayID ?? "" }, set: {
                            model.settings.displayID = $0.isEmpty ? nil : $0; model.saveSettings(docking: true)
                        })) {
                            Text("主显示器").tag("")
                            ForEach(model.displays, id: \.0) { display in Text(display.1).tag(display.0) }
                        }.labelsHidden().frame(width: 240)
                    }
                }
                group("边缘唤出") {
                    row("唤出边") {
                        Picker("唤出边", selection: Binding(get: { model.settings.edgePreference }, set: {
                            model.settings.edgePreference = $0; model.saveSettings()
                        })) {
                            Text("自动").tag(EdgePreference.automatic); Text("左侧").tag(EdgePreference.left); Text("右侧").tag(EdgePreference.right)
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 220)
                    }
                }
                Text(model.dockExplanation).font(.system(size: 12)).foregroundStyle(.secondary).padding(.leading, 4)
                group("快捷键") {
                    row("新建便签") {
                        TextField("Control+Option+N", text: $model.shortcut).frame(width: 210)
                            .accessibilityLabel("新建便签快捷键，修饰键用加号连接")
                            .onSubmit { model.saveHotkey() }
                        Button("应用") { model.saveHotkey() }
                    }
                }
                group("数据") {
                    row("备份（JSON）") {
                        Button("导入…") { model.importFile() }; Button("导出…") { model.exportFile() }
                    }
                }
                if let message = model.message { Text(message).foregroundStyle(.red).textSelection(.enabled) }
            }.padding(.horizontal, 40).padding(.vertical, 20)
        }.font(.system(size: 13)).frame(minWidth: 760, minHeight: 576)
            .background(Color(nsColor: NoteTheme.dynamic("F4F3F0", "242321")))
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.reload() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in model.reload() }
    }
}
