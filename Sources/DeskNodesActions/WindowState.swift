import Foundation
import DeskNodesCore
import DeskNodesPersistence

/// Expanded geometry is authoritative even while the panel presents a 32pt header.
public struct NoteFrame: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double = 240, height: Double = 120) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public func bounded() throws -> Self {
        guard [x, y, width, height].allSatisfy(\.isFinite) else { throw StoreError.invalid("frame") }
        return Self(x: x, y: y, width: min(400, max(200, width)), height: min(600, max(120, height)))
    }
    public func presenting(collapsed: Bool) -> Self {
        collapsed ? Self(x: x, y: y + height - 32, width: width, height: 32) : self
    }
    public static func automaticHeight(content: Double) -> Double {
        min(480, max(120, content.isFinite ? content : 120))
    }
}

/// Presentation overrides never rewrite a note's durable individual level.
/// Clicking a desktop-level note lifts it to the ordinary layer only, so it can sit
/// above the desktop while editing without floating over other applications.
public struct WindowModes {
    public var allTopmost = false
    public init() {}
    public func effective(_ choice: WindowLevel, temporarilyRaised: Bool = false) -> WindowLevel {
        if allTopmost { return .topmost }
        return choice == .desktop && temporarilyRaised ? .ordinary : choice
    }
    public static func collapsedTitle(_ title: String?, firstItem: String?) -> String {
        if let title, !title.isEmpty { return title }
        return firstItem ?? ""
    }
}

extension NoteActions {
    public func appearance(_ id: NoteID, color: NotePalette? = nil, level: WindowLevel? = nil,
                           collapsed: Bool? = nil, automaticHeight: Bool? = nil) throws {
        try store.transaction { store in
            guard var note = try store.notes().first(where: { $0.id == id }) else { throw StoreError.notFound }
            if let color { note.color = color }
            if let level { note.level = level }
            if let collapsed { note.collapsed = collapsed }
            if let automaticHeight { note.automaticHeight = automaticHeight }
            try store.update(note)
        }
    }
    /// Called only at gesture completion / a completed model layout, never on animation ticks.
    public func finalGeometry(_ id: NoteID, frame: NoteFrame, manuallyResized: Bool = false) throws {
        let frame = try frame.bounded()
        try store.transaction { store in
            guard var note = try store.notes().first(where: { $0.id == id }) else { throw StoreError.notFound }
            let display: String?
            switch note.placement {
            case .free(let id, _, _, _, _): display = id
            case .dock: return // N5 owns existing dock placements; N4 does not detach them.
            }
            note.placement = .free(displayID: display, x: frame.x, y: frame.y, width: frame.width, height: frame.height)
            if manuallyResized { note.automaticHeight = false }
            try store.update(note)
        }
    }
}
