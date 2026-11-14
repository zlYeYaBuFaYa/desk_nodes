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
    /// "" unbinds 浮起.
    let peekHotkey: (String, () throws -> Void) throws -> Void
    let export: () throws -> Data
    let importBackup: (ValidatedBackup) throws -> Void
    let canImport: () -> Bool
    /// Toolbar layout and idle shrink; Mac display preferences, not part of the backup.
    let toolbar: (ToolbarOrientation, Int) -> Void
    let toolbarCurrent: () -> (ToolbarOrientation, Int)
    /// Where an idle toolbar goes; only dragging its entry or "恢复默认" moves it.
    let toolbarHomeCurrent: () -> ToolbarHome
    let resetToolbarHome: () -> Void
    /// New-note size and 文字大小 are Mac display preferences too.
    let presentation: PresentationDefaults
    let textSize: (NoteTextSize) -> Void
    let noteFont: (NoteFont) -> Void
    @Published var noteTextSize = NoteTextSize.standard
    @Published var noteFace = NoteFont.system
    /// 圆体 while macOS downloads it; the notes keep their current font meanwhile.
    @Published var downloading: NoteFont?
    /// Faces this Mac cannot show yet, checked on reload rather than on every render.
    @Published private(set) var unavailable: Set<NoteFont> = []
    @Published var noteWidth = NoteMetrics.width
    /// 0 follows the content.
    @Published var noteHeight = 0.0
    @Published var toolbarOrientation = ToolbarOrientation.vertical
    @Published var toolbarShrink = ToolbarMetrics.defaultAutoShrink
    @Published var toolbarHome = ToolbarHome.standard
    @Published var settings = Settings()
    @Published var preferences = NativePreferences()
    @Published var shortcut = "Control+Option+N"
    @Published var peekShortcut = NativePreferences.defaultPeekHotkey
    @Published var message: String?
    @Published var loginEnabled = false
    @Published var loginExplanation = ""
    enum ShortcutTarget { case create, peek }
    @Published private(set) var recording: ShortcutTarget?
    private var recorder: Any?
    init(actions: NoteActions, login: LoginService, changed: @escaping () -> Void,
         hotkey: @escaping (Hotkey, () throws -> Void) throws -> Void,
         peekHotkey: @escaping (String, () throws -> Void) throws -> Void = { _, persist in try persist() },
         export: @escaping () throws -> Data, importBackup: @escaping (ValidatedBackup) throws -> Void,
         canImport: @escaping () -> Bool = { true },
         toolbar: @escaping (ToolbarOrientation, Int) -> Void = { _, _ in },
         toolbarCurrent: @escaping () -> (ToolbarOrientation, Int) = { (.vertical, ToolbarMetrics.defaultAutoShrink) },
         toolbarHome: @escaping () -> ToolbarHome = { .standard },
         resetToolbarHome: @escaping () -> Void = {},
         textSize: @escaping (NoteTextSize) -> Void = { _ in },
         noteFont: @escaping (NoteFont) -> Void = { _ in },
         presentation: PresentationDefaults? = nil) {
        self.actions = actions; self.login = login; self.changed = changed
        self.hotkey = hotkey; self.peekHotkey = peekHotkey; self.export = export; self.importBackup = importBackup; self.canImport = canImport
        self.toolbar = toolbar; self.toolbarCurrent = toolbarCurrent; self.textSize = textSize; self.noteFont = noteFont
        self.toolbarHomeCurrent = toolbarHome; self.resetToolbarHome = resetToolbarHome
        self.presentation = presentation ?? .standard()
        reload()
    }
    func reload() {
        (toolbarOrientation, toolbarShrink) = toolbarCurrent()
        toolbarHome = toolbarHomeCurrent()
        let size = presentation.newNoteSize
        noteWidth = size.width; noteHeight = size.height ?? 0
        noteTextSize = presentation.noteTextSize
        noteFace = presentation.noteFont
        unavailable = Set(NoteFont.allCases.filter { !NoteFonts.isAvailable($0) })
        do {
            settings = try actions.store.settings(); preferences = try actions.store.preferences()
            shortcut = preferences.hotkey; peekShortcut = preferences.peekHotkey
            loginEnabled = login.enabled; loginExplanation = login.explanation
        } catch { message = String(describing: error) }
    }
    func saveSettings() {
        perform { try actions.store.update(settings); changed() }
        reload()
    }
    func saveToolbar() { toolbar(toolbarOrientation, toolbarShrink) }
    /// A face this Mac lacks is downloaded first (圆体); a failed download, or a build
    /// without the bundled 文楷, keeps the old one and says why.
    func chooseFont(_ face: NoteFont) {
        guard downloading == nil else { return }
        message = nil
        if NoteFonts.isAvailable(face) { noteFont(face); reload(); return }
        guard face == .rounded else { message = "这个版本没有包含\(face.name)字体，便签保持当前字体。"; return }
        downloading = face
        NoteFonts.download(face) { [weak self] failure in
            guard let self else { return }
            self.downloading = nil
            if let failure { self.message = failure } else { self.noteFont(face) }
            self.reload()
        }
    }
    /// The bundled OFL text, else the project's published copy.
    func openFontLicense() {
        let bundled = Bundle.main.url(forResource: "OFL", withExtension: "txt", subdirectory: "Fonts")
        if let url = bundled ?? URL(string: "https://github.com/lxgw/LxgwWenKai/blob/main/OFL.txt") { NSWorkspace.shared.open(url) }
    }
    func saveNoteSize() { presentation.newNoteSize = (noteWidth, noteHeight > 0 ? noteHeight : nil) }
    func quit() { NSApp.terminate(nil) }
    func saveHotkey() {
        perform {
            let parsed = try Hotkey(shortcut)
            var updated = try actions.store.preferences(); updated.hotkey = parsed.canonical
            try updated.validate()
            try hotkey(parsed) { try self.actions.store.update(updated) }
            preferences = updated; shortcut = updated.hotkey
        }
    }
    /// Binds 浮起 to `peekShortcut`; an empty value removes the shortcut.
    func savePeekHotkey() {
        perform {
            var updated = try actions.store.preferences()
            updated.peekHotkey = peekShortcut.isEmpty ? "" : try Hotkey(peekShortcut).canonical
            try updated.validate()
            try peekHotkey(updated.peekHotkey) { try self.actions.store.update(updated) }
            preferences = updated; peekShortcut = updated.peekHotkey
        }
    }
    /// Captures the next key press as the shortcut. Esc cancels; unsupported keys explain why.
    func startRecording(_ target: ShortcutTarget) {
        guard recording == nil else { return }
        recording = target; message = nil
        recorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.stopRecording(); return nil } // Esc
            guard let text = HotkeyKeyCodes.shortcut(keyCode: event.keyCode, modifiers: event.modifierFlags) else {
                self.message = "只支持字母、数字或 Space，并需包含 Control 或 Command。"; return nil
            }
            self.stopRecording()
            // Rejected: show the kept binding.
            if target == .create {
                self.shortcut = text; self.saveHotkey()
                if self.message != nil { self.shortcut = self.preferences.hotkey }
            } else {
                self.peekShortcut = text; self.savePeekHotkey()
                if self.message != nil { self.peekShortcut = self.preferences.peekHotkey }
            }
            return nil
        }
    }
    func stopRecording() {
        if let recorder { NSEvent.removeMonitor(recorder) }
        recorder = nil; recording = nil
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
    private func shortcutRow(_ title: String, value: String, target: SettingsPresentation.ShortcutTarget,
                             @ViewBuilder extra: () -> some View = { EmptyView() }) -> some View {
        row(title) {
            let active = model.recording == target
            Text(active ? "请按下新快捷键（Esc 取消）" : value.isEmpty ? "未设置" : ShortcutText.symbols(value))
                .font(.system(size: 13, weight: .medium)).monospaced()
                .foregroundStyle(active || value.isEmpty ? .secondary : .primary)
                .frame(minWidth: 200, alignment: .trailing)
                .accessibilityLabel("\(title)快捷键：\(value.isEmpty ? "未设置" : value)")
            Button(active ? "取消" : "录制…") {
                active ? model.stopRecording() : model.startRecording(target)
            }.disabled(model.recording != nil && !active)
            extra()
        }
    }
    /// Each choice named in its own face; 圆体 notes when it still has to be downloaded.
    private func fontChoice(_ face: NoteFont) -> some View {
        let selected = model.noteFace == face
        let status: String? = model.downloading == face ? "下载中…"
            : !model.unavailable.contains(face) ? nil : face == .rounded ? "需下载" : "未包含"
        return Button { model.chooseFont(face) } label: {
            VStack(spacing: 2) {
                Text("文 Aa").font(Font(NoteFonts.font(face, size: 17, weight: .semibold)))
                Text(face.name).font(Font(NoteFonts.font(face, size: 11, weight: .regular))).foregroundStyle(.secondary)
                Text(status ?? " ").font(.system(size: 9)).foregroundStyle(.tertiary)
            }.frame(width: 72, height: 62)
                .background(Color(nsColor: NoteTheme.dynamic("F7F6F3", "3A3835")), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : Color.primary.opacity(0.1),
                                                                   lineWidth: selected ? 2 : 1))
        }.buttonStyle(.plain).disabled(model.downloading != nil)
            .accessibilityLabel("字体：\(face.name)\(status.map { "，\($0)" } ?? "")")
            .accessibilityAddTraits(selected ? .isSelected : [])
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
                group("外观") {
                    row("文字大小") {
                        Picker("文字大小", selection: Binding(get: { model.noteTextSize }, set: {
                            // Refused during IME composition: show the size actually in use.
                            model.textSize($0); model.noteTextSize = model.presentation.noteTextSize
                        })) {
                            ForEach(NoteTextSize.allCases, id: \.self) { Text($0.name).tag($0) }
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 260)
                    }
                    Divider()
                    row("字体") {
                        HStack(spacing: 8) {
                            ForEach(NoteFont.allCases, id: \.self) { face in fontChoice(face) }
                        }
                    }.padding(.vertical, 6)
                    Divider()
                    HStack(spacing: CGFloat(model.noteTextSize.scaled(NoteMetrics.checkboxGap))) {
                        Circle().stroke(Color.primary.opacity(0.42), lineWidth: 1.4)
                            .frame(width: CGFloat(model.noteTextSize.scaled(NoteMetrics.checkboxSize)),
                                   height: CGFloat(model.noteTextSize.scaled(NoteMetrics.checkboxSize)))
                        Text("示例事项：周五前交季度复盘 Review")
                            .font(Font(NoteFonts.font(model.noteFace, size: CGFloat(model.noteTextSize.itemSize), weight: .regular)))
                        Spacer()
                    }.frame(minHeight: 44).padding(.horizontal, 14).accessibilityHidden(true)
                }
                HStack(spacing: 4) {
                    Text("对所有便签生效，宽度不变。也可以在便签里按 ⌘+、⌘−、⌘0 调整大小。文楷为霞鹜文楷，SIL Open Font License 1.1，")
                    Button("字体授权") { model.openFontLicense() }.buttonStyle(.link)
                }.font(.system(size: 12)).foregroundStyle(.secondary).padding(.leading, 4)
                group("工具条") {
                    row("排列方向") {
                        Picker("排列方向", selection: Binding(get: { model.toolbarOrientation }, set: {
                            model.toolbarOrientation = $0; model.saveToolbar()
                        })) {
                            Text("竖向").tag(ToolbarOrientation.vertical); Text("横向").tag(ToolbarOrientation.horizontal)
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 160)
                    }
                    Divider()
                    row("闲置自动收缩") {
                        Picker("闲置自动收缩", selection: Binding(get: { model.toolbarShrink }, set: {
                            model.toolbarShrink = $0; model.saveToolbar()
                        })) {
                            Text("关闭").tag(0); Text("10 秒").tag(10); Text("15 秒").tag(15); Text("30 秒").tag(30)
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 260)
                    }
                    Divider()
                    row("收缩位置") {
                        ToolbarHomeDiagram(home: model.toolbarHome)
                        Text(ToolbarHomeText.describe(model.toolbarHome)).foregroundStyle(.secondary)
                        Button("恢复默认") { model.resetToolbarHome() } // the settings reload with the change
                            .disabled(model.toolbarHome == .standard)
                    }
                }
                Text("工具条闲置到时会收缩到固定位置，默认在屏幕右侧偏下；鼠标移过去停一下即可展开。拖动收缩后的入口可以换位置。")
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
                    shortcutRow("新建便签", value: model.shortcut, target: .create)
                    Divider()
                    shortcutRow("浮起便签", value: model.peekShortcut, target: .peek) {
                        Button("清除") { model.peekShortcut = ""; model.savePeekHotkey() }
                            .disabled(model.peekShortcut.isEmpty || model.recording != nil)
                    }
                }
                Text("浮起：把全部便签临时浮到最前，包括全屏应用；按 Esc、再按一次或切换到其他应用即放回。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.leading, 4)
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

/// A small screen with a dot where the entry rests.
struct ToolbarHomeDiagram: View {
    let home: ToolbarHome
    var body: some View {
        let width = 48.0, height = 30.0, inset = 3.0, dot = 6.0
        // The ratio runs bottom-to-top and left-to-right; SwiftUI's y runs down.
        let along = inset + dot / 2 + (home.edge == .left || home.edge == .right
            ? (1 - home.ratio) * (height - inset * 2 - dot) : home.ratio * (width - inset * 2 - dot))
        let point: CGPoint = switch home.edge {
        case .left: CGPoint(x: inset + dot / 2, y: along)
        case .right: CGPoint(x: width - inset - dot / 2, y: along)
        case .top: CGPoint(x: along, y: inset + dot / 2)
        case .bottom: CGPoint(x: along, y: height - inset - dot / 2)
        }
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.35), lineWidth: 1)
            Circle().fill(Color(nsColor: NoteTheme.accent)).frame(width: dot, height: dot)
                .position(point)
        }.frame(width: width, height: height).accessibilityHidden(true)
    }
}

enum ToolbarHomeText {
    /// "右侧 · 偏下": the edge, and roughly where along it.
    static func describe(_ home: ToolbarHome) -> String {
        let side = home.edge == .left || home.edge == .right
        let edge = switch home.edge { case .left: "左侧"; case .right: "右侧"; case .top: "顶部"; case .bottom: "底部" }
        let place: String
        switch home.ratio {
        case ..<0.2: place = side ? "靠下" : "靠左"
        case ..<0.45: place = side ? "偏下" : "偏左"
        case ...0.55: place = "居中"
        case ...0.8: place = side ? "偏上" : "偏右"
        default: place = side ? "靠上" : "靠右"
        }
        return "\(edge) · \(place)"
    }
}

/// "Control+Option+N" -> "⌃⌥N" for display; storage keeps the readable canonical form.
enum ShortcutText {
    static func symbols(_ value: String) -> String {
        let map = ["Control": "⌃", "Option": "⌥", "Shift": "⇧", "Command": "⌘"]
        return value.split(separator: "+").map { map[String($0)] ?? String($0) }.joined()
    }
}
