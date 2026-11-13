import Foundation
import DeskNodesPersistence

/// Screen coordinates are AppKit points, with a bottom-left origin. No pixel conversion.
public struct DockScreen: Equatable, Sendable {
    public var id: String
    public var visible: NoteFrame
    public init(id: String, visible: NoteFrame) { self.id = id; self.visible = visible }
    public var persistentID: String? { id.hasPrefix("session-screen-") ? nil : id }
    public var available: NoteFrame {
        let dx = min(8, max(0, (visible.width - 1) / 2))
        let dy = min(8, max(0, (visible.height - 1) / 2))
        return NoteFrame(x: visible.x + dx, y: visible.y + dy,
                         width: max(1, visible.width - 2 * dx), height: max(1, visible.height - 2 * dy))
    }
}
public struct DockSlot: Equatable, Sendable {
    public let id: NoteID
    public let frame: NoteFrame
}
public struct DockLayout: Equatable, Sendable {
    public var slots: [DockSlot] = []
    public var overflow: [NoteID] = []
    public var tabs: NoteFrame? = nil
}
public struct DockTabs: Equatable, Sendable {
    public let slots: [DockSlot]
    public let control: NoteFrame
    public let pageCount: Int
}
public enum DockGeometry {
    public static let gap = 12.0
    /// Side strips match a free note's standard width; the top strip stays narrower so more fit.
    public static let sideWidth = 288.0
    public static let topWidth = 220.0
    public static func screen(_ id: String?, screens: [DockScreen], preferred: String? = nil) -> DockScreen? {
        screens.first { $0.id == (id ?? preferred) } ?? screens.first
    }
    public static func contains(_ frame: NoteFrame, x: Double, y: Double) -> Bool {
        x >= frame.x && x <= frame.x + frame.width && y >= frame.y && y <= frame.y + frame.height
    }
    public static func clamp(_ frame: NoteFrame, to screen: DockScreen) -> NoteFrame {
        let area = screen.available
        let width = min(area.width, frame.width), height = min(area.height, frame.height)
        return NoteFrame(x: min(max(frame.x, area.x), area.x + area.width - width),
                         y: min(max(frame.y, area.y), area.y + area.height - height), width: width, height: height)
    }
    /// A 96pt overflow rail is reserved only when needed. Its tabs scroll, never overlap.
    /// Selection promotes a note to a card without changing durable order.
    public static func layout(ids: [NoteID], edge: DockEdge, screen: DockScreen,
                              heights: [NoteID: Double] = [:], collapsed: Set<NoteID> = [],
                              selected: NoteID? = nil) -> DockLayout {
        let a = screen.available
        let horizontal = edge == .top
        let width = min(a.width, horizontal ? topWidth : sideWidth)
        let topHeight = min(a.height, screen.visible.height < 700 ? 200.0 : 260.0)
        func height(_ id: NoteID) -> Double {
            collapsed.contains(id) ? min(32, a.height) : (horizontal ? topHeight : min(a.height, NoteFrame.automaticHeight(content: heights[id] ?? 120)))
        }
        func extent(_ id: NoteID) -> Double { horizontal ? width : height(id) }
        let limit = horizontal ? a.width : a.height
        let total = ids.reduce(0.0) { $0 + extent($1) } + Double(max(0, ids.count - 1)) * gap
        let overflowing = total > limit
        let rail = min(96.0, limit)
        let budget = overflowing ? max(0, limit - rail - gap) : limit
        var ordered = ids
        if let selected, let i = ordered.firstIndex(of: selected) { ordered.remove(at: i); ordered.insert(selected, at: 0) }
        var result = DockLayout(), cursor = 0.0
        var filled = false
        for id in ordered {
            let size = extent(id)
            if !filled && cursor + size <= budget {
                let frame = NoteFrame(x: horizontal ? a.x + cursor : (edge == .left ? a.x : a.x + a.width - width),
                                      y: a.y + a.height - (horizontal ? height(id) : cursor + height(id)),
                                      width: width, height: height(id))
                result.slots.append(DockSlot(id: id, frame: frame)); cursor += size + gap
            } else { filled = true; result.overflow.append(id) }
        }
        // Overflow order always follows the durable strip order, even after promotion.
        result.overflow = ids.filter { result.overflow.contains($0) }
        if !result.overflow.isEmpty {
            result.tabs = NoteFrame(x: horizontal ? a.x + a.width - rail : (edge == .left ? a.x : a.x + a.width - width),
                                    y: horizontal ? a.y + a.height - topHeight : a.y,
                                    width: horizontal ? rail : width, height: horizontal ? topHeight : rail)
        }
        return result
    }
    /// Paged compact tabs reserve a 32pt all-notes menu. Wheel changes pages.
    public static func tabs(ids: [NoteID], frame: NoteFrame, page: Int) -> DockTabs {
        let count = frame.height < 76 ? 0 : max(1, Int((frame.height - 32) / 44))
        let pages = count == 0 ? 1 : max(1, (ids.count + count - 1) / count)
        let start = min(max(0, page), pages - 1) * count
        let slots = count == 0 ? [] : Array(ids.dropFirst(start).prefix(count)).enumerated().map { index, id in
            DockSlot(id: id, frame: NoteFrame(x: frame.x, y: frame.y + frame.height - Double(index) * 44 - 32,
                                            width: frame.width, height: 32))
        }
        return DockTabs(slots: slots, control: NoteFrame(x: frame.x, y: frame.y, width: frame.width, height: min(32, frame.height)), pageCount: pages)
    }
    /// Snap only on release, within 24pt of an available edge and inside its span.
    public static func snap(x: Double, y: Double, screen: DockScreen) -> DockEdge? {
        let a = screen.available
        guard contains(NoteFrame(x: a.x - 24, y: a.y - 24, width: a.width + 48, height: a.height + 48), x: x, y: y) else { return nil }
        let candidates: [(DockEdge, Double)] = [(.top, abs(y - a.y - a.height)), (.left, abs(x - a.x)), (.right, abs(x - a.x - a.width))]
        return candidates.filter { $0.1 <= 24 }.min { $0.1 < $1.1 }?.0
    }
    /// Existing strip retention uses a wider 48pt band to avoid accidental detach.
    public static func retains(edge: DockEdge, x: Double, y: Double, screen: DockScreen) -> Bool {
        let a = screen.available
        switch edge {
        case .top: return x >= a.x - 24 && x <= a.x + a.width + 24 && abs(y - a.y - a.height) <= 48
        case .left: return y >= a.y - 24 && y <= a.y + a.height + 24 && abs(x - a.x) <= 48
        case .right: return y >= a.y - 24 && y <= a.y + a.height + 24 && abs(x - a.x - a.width) <= 48
        }
    }
    /// Side strips start below a top strip. Opposing side strips split narrow displays.
    public static func region(edge: DockEdge, occupied: Set<DockEdge>, screen: DockScreen) -> DockScreen {
        guard edge != .top else { return screen }
        var visible = screen.visible
        if occupied.contains(.top) {
            let reserve = min(max(0, visible.height - 48), (visible.height < 700 ? 200.0 : 260.0) + gap)
            visible.height -= reserve
        }
        if occupied.contains(.left) && occupied.contains(.right) && visible.width < 508 {
            let half = max(1, (visible.width - gap) / 2)
            if edge == .right { visible.x += visible.width - half }
            visible.width = half
        }
        return DockScreen(id: screen.id, visible: visible)
    }
    /// Map a visible slot insertion back into the full durable order (including overflow).
    public static func insertion(x: Double, y: Double, edge: DockEdge, slots: [DockSlot],
                                 ordered: [NoteID], excluding: NoteID) -> Int {
        let ids = ordered.filter { $0 != excluding }
        let visible = slots.filter { $0.id != excluding }
        let index = insertion(x: x, y: y, edge: edge, slots: slots, excluding: excluding)
        if index < visible.count { return ids.firstIndex(of: visible[index].id) ?? ids.count }
        if let last = visible.last, let found = ids.firstIndex(of: last.id) { return found + 1 }
        return ids.count
    }
    public static func insertion(x: Double, y: Double, edge: DockEdge, slots: [DockSlot], excluding: NoteID) -> Int {
        slots.filter { $0.id != excluding }.filter {
            edge == .top ? x > $0.frame.x + $0.frame.width / 2 : y < $0.frame.y + $0.frame.height / 2
        }.count
    }
}

extension Placement {
    public var freeFrame: NoteFrame? {
        guard case let .free(_, x, y, w, h) = self else { return nil }
        return NoteFrame(x: x, y: y, width: w, height: h)
    }
    public var displayID: String? {
        switch self { case .dock(_, let id), .free(let id, _, _, _, _): return id }
    }
    public static func free(_ frame: NoteFrame, displayID: String?) -> Placement {
        .free(displayID: displayID, x: frame.x, y: frame.y, width: frame.width, height: frame.height)
    }
}
extension NoteActions {
    /// One final transaction for placement and the complete target-strip permutation.
    /// No item writes, level changes, collapse changes or sizing-mode changes.
    public func dock(_ id: NoteID, edge: DockEdge, displayID: String?, index: Int, screens: [DockScreen] = []) throws {
        try store.transaction { store in
            let notes = try store.notes()
            guard var note = notes.first(where: { $0.id == id }) else { throw StoreError.notFound }
            let target = Placement.dock(edge: edge, displayID: displayID)
            let preferred = try store.settings().displayID
            var strip = notes.filter {
                guard $0.id != id, case .dock(let e, let d) = $0.placement, e == edge else { return false }
                if screens.isEmpty { return $0.placement == target }
                return DockGeometry.screen(d, screens: screens, preferred: preferred)?.id == DockGeometry.screen(displayID, screens: screens, preferred: preferred)?.id
            }
            if case .free = note.placement { note.freeRestore = note.placement }
            note.placement = target
            strip.insert(note, at: min(max(0, index), strip.count))
            for (order, var member) in strip.enumerated() { member.order = order; try store.update(member) }
        }
    }
    public func detach(_ id: NoteID, frame: NoteFrame? = nil, displayID: String? = nil) throws {
        try store.transaction { store in
            guard var note = try store.notes().first(where: { $0.id == id }) else { throw StoreError.notFound }
            let saved = note.freeRestore
            let final = try (frame ?? saved?.freeFrame ?? NoteFrame(x: 100, y: 100)).bounded()
            note.placement = .free(final, displayID: frame == nil ? saved?.displayID : displayID)
            try store.update(note)
        }
    }
    /// Empty topology is transient (sleep/reconfiguration): never manufacture a screen.
    public func reconcileScreens(_ screens: [DockScreen]) throws {
        guard let primary = screens.first else { return }
        try store.transaction { store in
            for var note in try store.notes() {
                let before = note
                func recovered(_ placement: Placement) -> Placement {
                    let missing = placement.displayID.map { id in !screens.contains { $0.id == id } } ?? false
                    if case .dock(let edge, _) = placement {
                        return missing ? .dock(edge: edge, displayID: primary.persistentID) : placement
                    }
                    guard let frame = placement.freeFrame else { return placement }
                    let screen = missing ? primary : (screens.first { $0.id == placement.displayID }
                        ?? screens.first { DockGeometry.contains($0.visible, x: frame.x + frame.width / 2, y: frame.y + frame.height / 2) } ?? primary)
                    return .free(DockGeometry.clamp(frame, to: screen), displayID: screen.persistentID)
                }
                note.placement = recovered(note.placement)
                note.freeRestore = note.freeRestore.map(recovered)
                if note != before { try store.update(note) }
            }
        }
    }
}
