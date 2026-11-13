import AppKit
import Carbon
import ServiceManagement
import DeskNodesPersistence

/// Physical ANSI virtual key codes shared by the Carbon adapter and the shortcut recorder.
enum HotkeyKeyCodes {
    static let codes: [String: UInt32] = ["A":0,"S":1,"D":2,"F":3,"H":4,"G":5,"Z":6,"X":7,"C":8,"V":9,"B":11,"Q":12,"W":13,"E":14,"R":15,"Y":16,"T":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"9":25,"7":26,"8":28,"0":29,"O":31,"U":32,"I":34,"P":35,"L":37,"J":38,"K":40,"N":45,"M":46,"Space":49]
    static let names = Dictionary(uniqueKeysWithValues: codes.map { ($0.value, $0.key) })
    /// "Control+Option+N" style text for a key press, or nil for unsupported keys.
    static func shortcut(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String? {
        guard let key = names[UInt32(keyCode)] else { return nil }
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        let parts = [(NSEvent.ModifierFlags.control, "Control"), (.option, "Option"), (.shift, "Shift"), (.command, "Command")]
            .filter { flags.contains($0.0) }.map(\.1)
        return (parts + [key]).joined(separator: "+")
    }
}

@MainActor
final class GlobalHotkey {
    private let binding = HotkeyBinding<EventHotKeyRef>()
    private var handler: EventHandlerRef?
    /// Shared by every instance: each handler sees every DeskNodes hotkey and must only
    /// claim its own, so two instances may never hand out the same id.
    private static var serial: UInt32 = 0
    private var activeID: UInt32 = 0
    private let action: () -> Void
    init(action: @escaping () -> Void) throws {
        self.action = action
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var identity = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                numericCast(MemoryLayout<EventHotKeyID>.size), nil, &identity)
            guard status == noErr else { return status }
            return MainActor.assumeIsolated {
                let owner = Unmanaged<GlobalHotkey>.fromOpaque(context).takeUnretainedValue()
                guard identity.signature == 0x44534B4E, identity.id == owner.activeID else { return OSStatus(eventNotHandledErr) }
                owner.action(); return noErr
            }
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { throw StoreError.invalid("无法安装快捷键处理器：\(status)") }
    }
    func apply(_ shortcut: Hotkey, persist: () throws -> Void) throws {
        var candidateID = activeID
        try binding.replace(shortcut, register: { key in
            Self.serial &+= 1; candidateID = Self.serial
            guard let code = HotkeyKeyCodes.codes[key.key] else { throw StoreError.invalid("不支持的按键") }
            var modifiers: UInt32 = 0
            for (name, value) in [("Control", controlKey), ("Option", optionKey), ("Shift", shiftKey), ("Command", cmdKey)] where key.modifiers.contains(name) { modifiers |= UInt32(value) }
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(code, modifiers, EventHotKeyID(signature: 0x44534B4E, id: candidateID), GetApplicationEventTarget(), 0, &reference)
            guard status == noErr, let reference else { throw StoreError.invalid("快捷键被占用或无法注册（\(status)）；保留原快捷键。") }
            return reference
        }, persist: persist, unregister: { _ = UnregisterEventHotKey($0) })
        activeID = candidateID
    }
    /// Releases the shortcut but keeps the handler, so a later `apply` can bind again.
    func unbind(persist: () throws -> Void) throws {
        try persist()
        binding.stop { _ = UnregisterEventHotKey($0) }
        activeID = 0
    }
    func stop() {
        binding.stop { _ = UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }
}

/// OS status is authoritative. Persisted consent never causes registration on launch
/// or import; only the first-launch affirmative button or explicit Settings toggle can.
@MainActor
final class LoginService {
    var enabled: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }
    var explanation: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "已启用：下次登录时启动。"
        case .requiresApproval: return "等待系统批准；请检查系统设置中的登录项。"
        case .notRegistered: return "未注册。只会在您同意后启用。"
        case .notFound: return "系统找不到此应用服务；请从稳定位置的已签名 .app 运行。"
        @unknown default: return "系统状态未知；请检查登录项。"
        }
    }
    func setEnabled(_ enabled: Bool, store: Store) throws {
        // Persist choice first. Failed OS requests remain visible and are never retried silently.
        var preferences = try store.preferences()
        preferences.loginDecision = enabled ? .requested : .declined
        try store.update(preferences)
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }
    func askOnFirstLaunch(store: Store) throws {
        guard try store.preferences().shouldAskForLogin else { return }
        NSApp.activate(ignoringOtherApps: true) // accessory app: otherwise the alert may open behind other windows
        let alert = NSAlert()
        alert.messageText = "登录时自动启动 DeskNodes？"
        alert.informativeText = "同意后才会向系统注册。您可以稍后在设置中修改；系统可能仍需批准。"
        alert.addButton(withTitle: "暂不启用")
        alert.addButton(withTitle: "启用")
        let accepted = alert.runModal() == .alertSecondButtonReturn
        if accepted { try setEnabled(true, store: store) }
        else {
            var preferences = try store.preferences(); preferences.loginDecision = .declined
            try store.update(preferences)
        }
    }
}
