import Foundation
import DeskNodesCore
import DeskNodesPersistence

/// The four presentation states of "全局收起". Only the target (collapsed or not) is
/// persisted; the transitional states exist so rapid clicks can reverse an animation.
public enum DeskPresentation: Equatable, Sendable {
    case expanded, collapsing, collapsed, expanding
    public init(collapsed: Bool) { self = collapsed ? .collapsed : .expanded }
    /// What the last request asked for, whether or not its animation has finished.
    public var targetsCollapsed: Bool { self == .collapsing || self == .collapsed }
    /// A new toggle always reverses the current target, even mid-animation.
    public func toggled() -> Self { targetsCollapsed ? .expanding : .collapsing }
    public func finished() -> Self {
        switch self {
        case .collapsing: return .collapsed
        case .expanding: return .expanded
        default: return self
        }
    }
}

/// One-shot "整理" geometry, plus the toolbar's own placement rules.
/// Coordinates are AppKit points with a bottom-left origin, like `DockScreen`.
public enum Arrangement {
    public struct Card: Equatable, Sendable {
        public let id: NoteID
        public let screen: String
        /// Height occupied on screen (32 for an individually folded note).
        public let presentedHeight: Double
        /// Durable expanded height; kept so unfolding later does not change size.
        public let expandedHeight: Double
        public init(id: NoteID, screen: String, presentedHeight: Double, expandedHeight: Double) {
            self.id = id; self.screen = screen
            self.presentedHeight = presentedHeight; self.expandedHeight = expandedHeight
        }
    }
    public struct Slot: Equatable, Sendable {
        public let id: NoteID
        public let screen: String
        /// Expanded frame whose top edge is the slot's top edge.
        public let frame: NoteFrame
        public let page: Int
        /// Pages used on this slot's screen; 1 means no overflow there.
        public let pages: Int
    }

    /// The display area minus the screen margin and, on the toolbar's display, the largest
    /// part clear of the toolbar's full expanded frame (beside a column, below or above a
    /// row), so no card can ever sit underneath it, even while it is shrunk to its entry.
    public static func area(_ screen: DockScreen, avoiding toolbar: NoteFrame?) -> NoteFrame {
        let margin = ArrangeMetrics.margin
        let v = screen.visible
        let left = v.x + min(margin, v.width / 2), right = v.x + v.width - min(margin, v.width / 2)
        let bottom = v.y + min(margin, v.height / 2), top = v.y + v.height - min(margin, v.height / 2)
        let inner = NoteFrame(x: left, y: bottom, width: max(1, right - left), height: max(1, top - bottom))
        guard let toolbar else { return inner }
        return largestFree(inner, avoiding: toolbar, gap: ArrangeMetrics.gap)
    }

    /// Masonry: each card goes under the shortest column (the leftmost on a tie), so a tall
    /// card leaves no gap beside it. When even the shortest column cannot take the card, a
    /// new page starts instead of overlapping.
    public static func layout(_ cards: [Card], in area: NoteFrame, width: Double = NoteMetrics.width,
                              gap: Double = ArrangeMetrics.gap) -> [Slot] {
        let width = min(width, area.width)
        let columns = max(1, Int((area.width + gap) / (width + gap)))
        let pageTop = area.y + area.height
        var placed: [(Card, NoteFrame, Int)] = []
        var page = 0, tops = Array(repeating: pageTop, count: columns)
        for card in cards {
            let height = min(max(1, card.presentedHeight), area.height)
            var column = tops.indices.max { tops[$0] < tops[$1] || (tops[$0] == tops[$1] && $0 > $1) }!
            if tops[column] - height < area.y && tops[column] < pageTop {
                page += 1; tops = Array(repeating: pageTop, count: columns); column = 0
            }
            let x = area.x + Double(column) * (width + gap), top = tops[column]
            placed.append((card, NoteFrame(x: x, y: top - card.expandedHeight, width: width, height: card.expandedHeight), page))
            tops[column] = top - height - gap
        }
        let pages = page + 1
        return placed.map { Slot(id: $0.0.id, screen: $0.0.screen, frame: $0.1, page: $0.2, pages: pages) }
    }

    /// Each display arranges only its own cards; durable order is the caller's order.
    public static func plan(_ cards: [Card], screens: [DockScreen], toolbar: NoteFrame?, toolbarScreen: String?) -> [Slot] {
        screens.flatMap { screen -> [Slot] in
            let mine = cards.filter { $0.screen == screen.id }
            guard !mine.isEmpty else { return [] }
            return layout(mine, in: area(screen, avoiding: toolbarScreen == screen.id ? toolbar : nil))
        }
    }

    /// The display a free frame belongs to: its stored display, else the one under its centre.
    public static func screen(for frame: NoteFrame, displayID: String?, screens: [DockScreen]) -> DockScreen? {
        if let displayID, let stored = screens.first(where: { $0.id == displayID }) { return stored }
        return screens.first { DockGeometry.contains($0.visible, x: frame.x + frame.width / 2, y: frame.y + frame.height / 2) }
            ?? screens.first
    }

    /// A new note goes to the first free spot next to the toolbar, scanning rows from the
    /// top. When every spot overlaps something, it cascades instead of leaving the screen.
    public static func placement(width: Double, height: Double, screen: DockScreen, toolbar: NoteFrame?,
                                 occupied: [NoteFrame], gap: Double = ArrangeMetrics.gap) -> NoteFrame {
        let a = area(screen, avoiding: toolbar)
        let width = min(width, a.width), height = min(height, a.height)
        let fromRight = toolbar.map { $0.x + $0.width / 2 > a.x + a.width / 2 } ?? false
        let columns = max(1, Int((a.width + gap) / (width + gap)))
        let step = 40.0
        let rows = max(1, Int((a.height - height) / step) + 1)
        func overlaps(_ f: NoteFrame) -> Bool {
            occupied.contains { o in
                f.x < o.x + o.width + gap / 2 && f.x + f.width + gap / 2 > o.x &&
                f.y < o.y + o.height + gap / 2 && f.y + f.height + gap / 2 > o.y
            }
        }
        for row in 0..<rows {
            for column in 0..<columns {
                let x = fromRight ? a.x + a.width - width - Double(column) * (width + gap) : a.x + Double(column) * (width + gap)
                let frame = NoteFrame(x: x, y: a.y + a.height - height - Double(row) * step, width: width, height: height)
                if !overlaps(frame) { return frame }
            }
        }
        let offset = Double(occupied.count % 6) * 24
        let x = fromRight ? a.x + a.width - width - offset : a.x + offset
        return NoteFrame(x: x, y: a.y + a.height - height - offset, width: width, height: height)
    }

    /// The whole toolbar stays inside one display's visible area, so its grip and every
    /// action are reachable. Too-short displays keep the grip (the top) visible.
    public static func clampToolbar(_ frame: NoteFrame, to screen: DockScreen) -> NoteFrame {
        let v = screen.visible
        let x = min(max(frame.x, v.x), v.x + max(0, v.width - frame.width))
        let top = v.y + v.height - frame.height
        let y = frame.height > v.height ? top : min(max(frame.y, v.y), top)
        return NoteFrame(x: x, y: y, width: frame.width, height: frame.height)
    }

    /// The collapsed stack sits beside the toolbar: right when it fits, otherwise left.
    public static func stackHint(beside toolbar: NoteFrame, width: Double, height: Double, screen: DockScreen) -> NoteFrame {
        let v = screen.visible, gap = 12.0
        let right = toolbar.x + toolbar.width + gap
        let x = right + width <= v.x + v.width ? right : toolbar.x - gap - width
        let top = toolbar.y + toolbar.height - 24
        let y = min(max(top - height, v.y), v.y + v.height - height)
        return NoteFrame(x: x, y: y, width: width, height: height)
    }

    /// A paged note is shown only on its page; a display with fewer pages keeps its last one.
    public static func visible(page: Int, pages: Int, current: Int) -> Bool {
        page == min(max(0, current), max(1, pages) - 1)
    }
}

extension NoteActions {
    /// Writes one completed "整理" in a single transaction. Docked notes become free notes;
    /// titles, items, completion, colours, levels, folding and history are untouched.
    public func arrange(_ slots: [Arrangement.Slot], screens: [DockScreen]) throws {
        try store.transaction { store in
            let notes = Dictionary(uniqueKeysWithValues: try store.notes().map { ($0.id, $0) })
            for slot in slots {
                guard var note = notes[slot.id] else { continue }
                let display = screens.first { $0.id == slot.screen }?.persistentID
                let placement = Placement.free(try slot.frame.bounded(), displayID: display)
                guard placement != note.placement else { continue }
                note.placement = placement
                try store.update(note)
            }
        }
    }
}
