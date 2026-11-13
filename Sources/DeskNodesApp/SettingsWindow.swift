import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ServiceManagement
import DeskNodesCore
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
    /// Toolbar layout and idle shrink; Mac display preferences, not part of the backup.
    let toolbar: (ToolbarOrientation, Int) -> Void
    let toolbarCurrent: () -> (ToolbarOrientation, Int)
    /// New-note size is a Mac display preference too.
    let presentation: PresentationDefaults
    @Published var noteWidth = NoteMetrics.width
    /// 0 follows the content.
    @Published var noteHeight = 0.0
    @Published var toolbarOrientation = ToolbarOrientation.vertical
    @Published var toolbarShrink = ToolbarMetrics.defaultAutoShrink
    @Published var settings = Settings()
    @Published var preferences = NativePreferences()
    @Published var shortcut = "Control+Option+N"
    @Published var message: String?
    @Published var loginEnabled = false
    @Published var loginExplanation = ""
    @Published var dockExplanation = ""
    @Published var displays: [(String, String)] = []
    @Published private(set) var recording = false
    private var recorder: Any?
    init(actions: NoteActions, login: LoginService, changed: @escaping () -> Void,
         hotkey: @escaping (Hotkey, () throws -> Void) throws -> Void,
         export: @escaping () throws -> Data, importBackup: @escaping (ValidatedBackup) throws -> Void,
         canImport: @escaping () -> Bool = { true },
         toolbar: @escaping (ToolbarOrientation, Int) -> Void = { _, _ in },
         toolbarCurrent: @escaping () -> (ToolbarOrientation, Int) = { (.vertical, ToolbarMetrics.defaultAutoShrink) },
         presentation: PresentationDefaults? = nil) {
        self.actions = actions; self.login = login; self.changed = changed
        self.hotkey = hotkey; self.export = export; self.importBackup = importBackup; self.canImport = canImport
        self.toolbar = toolbar; self.toolbarCurrent = toolbarCurrent; self.presentation = presentation ?? .standard()
        reload()
    }
    func reload() {
        (toolbarOrientation, toolbarShrink) = toolbarCurrent()
        let size = presentation.newNoteSize
        noteWidth = size.width; noteHeight = size.height ?? 0
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
    func saveToolbar() { toolbar(toolbarOrientation, toolbarShrink) }
    func saveNoteSize() { presentation.newNoteSize = (noteWidth, noteHeight > 0 ? noteHeight : nil) }
    func quit() { NSApp.terminate(nil) }
    func saveHotkey() {
        perform {
            let parsed = try Hotkey(shortcut)
            var updated = try actions.store.preferences(); updated.hotkey = parsed.canonical
            try hotkey(parsed) { try self.actions.store.update(updated) }
            preferences = updated; shortcut = updated.hotkey
        }
    }
    /// Captures the next key press as the shortcut. Esc cancels; unsupported keys explain why.
    func startRecording() {
        guard !recording else { return }
        recording = true; message = nil
        recorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.stopRecording(); return nil } // Esc
            guard let text = HotkeyKeyCodes.shortcut(keyCode: event.keyCode, modifiers: event.modifierFlags) else {
                self.message = "只支持字母、数字或 Space，并需包含 Control 或 Command。"; return nil
            }
            self.stopRecording()
            self.shortcut = text; self.saveHotkey()
            if self.message != nil { self.shortcut = self.preferences.hotkey } // rejected: show the kept binding
            return nil
        }
    }
    func stopRecording() {
        if let recorder { NSEvent.removeMonitor(recorder) }
        recorder = nil; recording = false
    }
    var rolloverTime: Date {
        get { Calendar.current.date(from: DateComponents(hour: settings.rolloverHour, minute: settings.rolloverMinute)) ?? Date() }
        set {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            guard let hour = parts.hour, let minute = parts.minute,
                  hour != settings.rolloverHour || minute != settings.rolloverMinute else { return }
            settings.rolloverHour = hour; settings.rolloverMinute = minute; saveSettings()
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
                        DatePicker("每天跨天时间", selection: Binding(get: { model.rolloverTime }, set: { model.rolloverTime = $0 }),
                                   displayedComponents: .hourAndMinute)
                            .labelsHidden().datePickerStyle(.field)
                            .environment(\.locale, Locale(identifier: "en_GB")) // 24-hour field
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
                group("工具条") {
                    row("排列方向") {
                        Picker("排列方向", selection: Binding(get: { model.toolbarOrientation }, set: {
                            model.toolbarOrientation = $0; model.saveToolbar()
                        })) {
                            Text("竖向").tag(ToolbarOrientation.vertical); Text("横向").tag(ToolbarOrientation.horizontal)
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 160)
                    }
                    Divider()
                    row("吸边后自动收缩") {
                        Picker("吸边后自动收缩", selection: Binding(get: { model.toolbarShrink }, set: {
                            model.toolbarShrink = $0; model.saveToolbar()
                        })) {
                            Text("关闭").tag(0); Text("10 秒").tag(10); Text("15 秒").tag(15); Text("30 秒").tag(30)
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 260)
                    }
                }
                Text("把工具条拖到屏幕边缘即可吸附；吸附后闲置到时，会缩成圆形入口，鼠标停在入口上即可展开。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.leading, 4)
                group("新建便签") {
                    row("宽度") {
                        Picker("宽度", selection: Binding(get: { model.noteWidth }, set: {
                            model.noteWidth = $0; model.saveNoteSize()
                        })) {
                            ForEach(NoteMetrics.newWidthChoices, id: \.self) { Text("\(Int($0))").tag($0) }
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 260)
                    }
                    Divider()
                    row("高度") {
                        Picker("高度", selection: Binding(get: { model.noteHeight }, set: {
                            model.noteHeight = $0; model.saveNoteSize()
                        })) {
                            ForEach(NoteMetrics.newHeightChoices, id: \.self) { Text($0 == 0 ? "随内容" : "\(Int($0))").tag($0) }
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 260)
                    }
                }
                Text("只影响之后新建的便签，单位为点。「随内容」会随事项增多自动变高；固定高度可在便签菜单里改回「随内容调整高度」。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.leading, 4)
                group("快捷键") {
                    row("新建便签") {
                        Text(model.recording ? "请按下新快捷键（Esc 取消）" : ShortcutText.symbols(model.shortcut))
                            .font(.system(size: 13, weight: .medium)).monospaced()
                            .foregroundStyle(model.recording ? .secondary : .primary)
                            .frame(minWidth: 200, alignment: .trailing)
                            .accessibilityLabel("新建便签快捷键：\(model.shortcut)")
                        Button(model.recording ? "取消" : "录制…") {
                            model.recording ? model.stopRecording() : model.startRecording()
                        }
                    }
                }
                group("数据") {
                    row("备份（JSON）") {
                        Button("导入…") { model.importFile() }; Button("导出…") { model.exportFile() }
                    }
                }
                if let message = model.message { Text(message).foregroundStyle(.red).textSelection(.enabled) }
                HStack {
                    Spacer()
                    Button("退出 DeskNodes") { model.quit() }.keyboardShortcut("q", modifiers: .command)
                }
            }.padding(.horizontal, 40).padding(.vertical, 20)
        }.font(.system(size: 13)).frame(minWidth: 760, minHeight: 576)
            .background(Color(nsColor: NoteTheme.dynamic("F4F3F0", "242321")))
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.reload() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in model.reload() }
            .onDisappear { model.stopRecording() }
    }
}

/// "Control+Option+N" -> "⌃⌥N" for display; storage keeps the readable canonical form.
enum ShortcutText {
    static func symbols(_ value: String) -> String {
        let map = ["Control": "⌃", "Option": "⌥", "Shift": "⇧", "Command": "⌘"]
        return value.split(separator: "+").map { map[String($0)] ?? String($0) }.joined()
    }
}
