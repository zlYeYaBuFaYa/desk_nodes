import Foundation

/// These are consent decisions, not claims about the OS registration status.
public enum LoginDecision: String, Codable, Sendable { case unasked, declined, requested }
public struct NativePreferences: Codable, Equatable, Sendable {
    public var hotkey = "Control+Option+N"
    public var loginDecision: LoginDecision = .unasked
    public init() {}
    public var shouldAskForLogin: Bool { loginDecision == .unasked }
}

/// Portable parser shared by persistence, Settings and the Carbon adapter.
/// Keys are physical ANSI letters/digits/space; modifiers require Control or Command.
public struct Hotkey: Equatable, Sendable {
    public let key: String
    public let modifiers: Set<String>
    public var canonical: String {
        ["Control", "Option", "Shift", "Command"].filter { modifiers.contains($0) }.joined(separator: "+") + "+" + key
    }
    public init(_ value: String) throws {
        let parts = value.split(separator: "+", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2, let last = parts.last else { throw StoreError.invalid("快捷键格式，例如 Control+Option+N") }
        let aliases = ["control":"Control", "option":"Option", "shift":"Shift", "command":"Command"]
        var flags: Set<String> = []
        for part in parts.dropLast() {
            guard let flag = aliases[part.lowercased()], flags.insert(flag).inserted else { throw StoreError.invalid("重复或未知修饰键") }
        }
        let key = last.uppercased() == "SPACE" ? "Space" : last.uppercased()
        guard (key.count == 1 && key.utf8.allSatisfy { (65...90).contains($0) || (48...57).contains($0) }) || key == "Space",
              flags.contains("Control") || flags.contains("Command") else { throw StoreError.invalid("快捷键需要 Control 或 Command，及字母、数字或 Space") }
        guard !(key == "H" && flags == ["Option", "Command"]),
              !(key == "D" && flags == ["Option", "Command"]),
              !(key == "Space" && flags == ["Control", "Option"]) else { throw StoreError.invalid("此组合由系统保留") }
        self.key = key; modifiers = flags
    }
}

/// Register candidate BEFORE retiring the previous handle. A conflict or persistence
/// failure releases only the candidate; the old binding and stored preference survive.
public final class HotkeyBinding<Handle> {
    private var current: (Hotkey, Handle)?
    public init() {}
    public var binding: Hotkey? { current?.0 }
    public func replace(_ candidate: Hotkey, register: (Hotkey) throws -> Handle,
                        persist: () throws -> Void, unregister: (Handle) -> Void) throws {
        if current?.0 == candidate { try persist(); return }
        let handle = try register(candidate)
        do { try persist() } catch { unregister(handle); throw error }
        let previous = current
        current = (candidate, handle)
        if let previous { unregister(previous.1) }
    }
    public func stop(unregister: (Handle) -> Void) {
        if let current { unregister(current.1) }; current = nil
    }
}

extension Store {
    public func preferences() throws -> NativePreferences {
        try locked {
            guard let value = try db.query("SELECT payload FROM native_preferences WHERE id=1").first?[0] else { throw StoreError.corrupt("native preferences") }
            let result = try JSONDecoder().decode(NativePreferences.self, from: Data(value.utf8))
            _ = try Hotkey(result.hotkey)
            return result
        }
    }
    public func update(_ preferences: NativePreferences) throws {
        _ = try Hotkey(preferences.hotkey)
        try transaction { _ in
            try db.run("UPDATE native_preferences SET payload=? WHERE id=1", [.text(String(decoding: try JSONEncoder().encode(preferences), as: UTF8.self))])
        }
    }
}
