import Foundation
import DeskNodesCore
import DeskNodesActions
import DeskNodesPersistence

/// Display preferences that belong to this Mac, not to the notes: the toolbar position,
/// global collapse and the current arrangement pages. They live in UserDefaults on
/// purpose, so a JSON backup never exports them and an import never moves windows.
@MainActor
final class PresentationDefaults {
    struct ToolbarPlace: Equatable {
        var x: Double
        var y: Double
        /// Persistent display identity; nil for a session-only display.
        var display: String?
    }
    private let defaults: UserDefaults
    init(_ defaults: UserDefaults) { self.defaults = defaults }
    /// Verification runs keep their own domain next to their scratch database.
    static func standard() -> PresentationDefaults {
        let suite = NativeStorage.verificationDirectory == nil ? nil : "local.desknodes.native.verification"
        return PresentationDefaults(suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard)
    }

    var collapsed: Bool {
        get { defaults.bool(forKey: "desk.collapsed") }
        set { defaults.set(newValue, forKey: "desk.collapsed") }
    }
    /// The retired global 置顶. Returns whether it was on and forgets it, so the
    /// one-time notice about per-note 置顶 shows at most once.
    func retireGlobalTopmost() -> Bool {
        defer { defaults.removeObject(forKey: "desk.topmost") }
        return defaults.bool(forKey: "desk.topmost")
    }
    var toolbar: ToolbarPlace? {
        get {
            guard let value = defaults.dictionary(forKey: "toolbar.place"),
                  let x = value["x"] as? Double, let y = value["y"] as? Double, x.isFinite, y.isFinite else { return nil }
            return ToolbarPlace(x: x, y: y, display: value["display"] as? String)
        }
        set {
            guard let newValue else { defaults.removeObject(forKey: "toolbar.place"); return }
            var value: [String: Any] = ["x": newValue.x, "y": newValue.y]
            if let display = newValue.display { value["display"] = display }
            defaults.set(value, forKey: "toolbar.place")
        }
    }
    /// Free or snapped rest place. Before it exists, the legacy `toolbar` record is read as
    /// a free position; it is never promoted to snapped by distance alone.
    var toolbarAnchor: ToolbarAnchor? {
        get {
            guard let value = defaults.dictionary(forKey: "toolbar.anchor"), let mode = value["mode"] as? String else { return nil }
            let display = value["display"] as? String
            if mode == "free" {
                guard let x = value["x"] as? Double, let y = value["y"] as? Double, x.isFinite, y.isFinite else { return nil }
                return .free(centerX: x, centerY: y, display: display)
            }
            guard let edge = ToolbarEdge(rawValue: mode), let ratio = value["ratio"] as? Double, ratio.isFinite else { return nil }
            return .snapped(edge, ratio: min(max(ratio, 0), 1), display: display)
        }
        set {
            var value: [String: Any]
            switch newValue {
            case nil: defaults.removeObject(forKey: "toolbar.anchor"); return
            case .free(let x, let y, _): value = ["mode": "free", "x": x, "y": y]
            case .snapped(let edge, let ratio, _): value = ["mode": edge.rawValue, "ratio": ratio]
            }
            if let display = newValue?.display { value["display"] = display }
            defaults.set(value, forKey: "toolbar.anchor")
        }
    }
    var toolbarOrientation: ToolbarOrientation {
        get { defaults.string(forKey: "toolbar.orientation").flatMap(ToolbarOrientation.init(rawValue:)) ?? .vertical }
        set { defaults.set(newValue.rawValue, forKey: "toolbar.orientation") }
    }
    /// Seconds before a snapped, idle toolbar shrinks to its entry; 0 turns it off.
    var toolbarAutoShrink: Int {
        get {
            guard let value = defaults.object(forKey: "toolbar.autoShrink") as? Int,
                  ToolbarMetrics.autoShrinkChoices.contains(value) else { return ToolbarMetrics.defaultAutoShrink }
            return value
        }
        set { defaults.set(newValue, forKey: "toolbar.autoShrink") }
    }
    /// Size of a newly created note; a nil height follows the content.
    var newNoteSize: (width: Double, height: Double?) {
        get {
            let width = defaults.double(forKey: "note.newWidth"), height = defaults.double(forKey: "note.newHeight")
            return (NoteMetrics.newWidthChoices.contains(width) ? width : NoteMetrics.width,
                    height > 0 && NoteMetrics.newHeightChoices.contains(height) ? height : nil)
        }
        set {
            defaults.set(newValue.width, forKey: "note.newWidth")
            defaults.set(newValue.height ?? 0, forKey: "note.newHeight")
        }
    }
    /// Page of each note from the last overflowing arrangement, and its display's page
    /// count. Notes created later are not listed and are always visible.
    var pages: [NoteID: (page: Int, pages: Int)] {
        get {
            let raw = defaults.dictionary(forKey: "arrange.pages") as? [String: [Int]] ?? [:]
            return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
                guard let uuid = UUID(uuidString: key), value.count == 2, value[0] >= 0, value[1] > value[0] else { return nil }
                return (NoteID(uuid), (value[0], value[1]))
            })
        }
        set {
            if newValue.isEmpty { defaults.removeObject(forKey: "arrange.pages"); return }
            defaults.set(Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.rawValue.uuidString, [$0.value.page, $0.value.pages]) }),
                         forKey: "arrange.pages")
        }
    }
    var currentPage: Int {
        get { max(0, defaults.integer(forKey: "arrange.page")) }
        set { defaults.set(max(0, newValue), forKey: "arrange.page") }
    }
}
