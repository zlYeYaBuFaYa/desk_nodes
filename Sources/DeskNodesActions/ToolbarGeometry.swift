import Foundation
import DeskNodesCore
import DeskNodesPersistence

public enum ToolbarOrientation: String, CaseIterable, Sendable { case vertical, horizontal }
public enum ToolbarEdge: String, CaseIterable, Sendable { case left, right, top, bottom }

/// Where the toolbar rests. A free toolbar keeps its expanded centre; a snapped one keeps
/// its round entry's position along the edge, as a fraction of the entry's legal span so it
/// survives resolution changes.
public enum ToolbarAnchor: Equatable, Sendable {
    case free(centerX: Double, centerY: Double, display: String?)
    case snapped(ToolbarEdge, ratio: Double, display: String?)
    public var display: String? {
        switch self { case .free(_, _, let d), .snapped(_, _, let d): return d }
    }
    public var edge: ToolbarEdge? {
        if case .snapped(let edge, _, _) = self { return edge }
        return nil
    }
}

/// The resolved frames for one anchor: the full expanded target (what notes avoid) and,
/// when snapped, the round entry. Both are AppKit screen points.
public struct ToolbarFrames: Equatable, Sendable {
    public var screen: DockScreen
    public var target: NoteFrame
    public var circle: NoteFrame?
    public var edge: ToolbarEdge?
    public init(screen: DockScreen, target: NoteFrame, circle: NoteFrame?, edge: ToolbarEdge?) {
        self.screen = screen; self.target = target; self.circle = circle; self.edge = edge
    }
}

/// Pure geometry for the capsule toolbar. The round entry stands for the grip end: it
/// stays where it is dropped and the capsule unfolds from it, so nothing jumps on release.
public enum ToolbarGeometry {
    static let gap = ToolbarMetrics.edgeGap
    static let radius = ToolbarMetrics.circleDiameter / 2

    /// Expanded size. On a display too small for the whole capsule the long side shrinks
    /// and the content scrolls, with the grip fixed.
    public static func size(_ orientation: ToolbarOrientation, paged: Bool, on screen: DockScreen) -> (width: Double, height: Double) {
        let v = screen.visible, short = ToolbarMetrics.width
        switch orientation {
        case .vertical:
            return (short, max(short, min(ToolbarMetrics.length(horizontal: false, paged: paged), v.height - gap * 2)))
        case .horizontal:
            return (max(short, min(ToolbarMetrics.length(horizontal: true, paged: paged), v.width - gap * 2)), short)
        }
    }

    /// The capsule's long side runs along the edge (grip end follows the entry) or across
    /// it (centred on the entry, unfolding into the display).
    static func alongEdge(_ orientation: ToolbarOrientation, _ edge: ToolbarEdge) -> Bool {
        (orientation == .vertical) == (edge == .left || edge == .right)
    }
    private static func span(_ edge: ToolbarEdge, _ v: NoteFrame) -> (lo: Double, hi: Double) {
        edge == .left || edge == .right ? (v.y, v.y + v.height) : (v.x, v.x + v.width)
    }
    /// Legal positions of the entry's centre along an edge.
    private static func circleSpan(_ edge: ToolbarEdge, _ v: NoteFrame) -> (lo: Double, hi: Double) {
        let s = span(edge, v), lo = s.lo + gap + radius, hi = s.hi - gap - radius
        return hi >= lo ? (lo, hi) : ((s.lo + s.hi) / 2, (s.lo + s.hi) / 2)
    }
    public static func ratio(along position: Double, edge: ToolbarEdge, screen: DockScreen) -> Double {
        let s = circleSpan(edge, screen.visible)
        return s.hi > s.lo ? min(max((position - s.lo) / (s.hi - s.lo), 0), 1) : 0.5
    }
    static func position(ratio: Double, edge: ToolbarEdge, screen: DockScreen) -> Double {
        let s = circleSpan(edge, screen.visible)
        return s.lo + (s.hi - s.lo) * min(max(ratio, 0), 1)
    }

    public static func circle(edge: ToolbarEdge, along c: Double, screen: DockScreen) -> NoteFrame {
        let v = screen.visible, d = ToolbarMetrics.circleDiameter
        switch edge {
        case .left: return NoteFrame(x: v.x + gap, y: c - radius, width: d, height: d)
        case .right: return NoteFrame(x: v.x + v.width - gap - d, y: c - radius, width: d, height: d)
        case .top: return NoteFrame(x: c - radius, y: v.y + v.height - gap - d, width: d, height: d)
        case .bottom: return NoteFrame(x: c - radius, y: v.y + gap, width: d, height: d)
        }
    }

    /// The expanded capsule unfolding from an entry at `c`. It slides along the edge when
    /// it would not fit, but always still covers the entry.
    public static func target(edge: ToolbarEdge, along c: Double, orientation: ToolbarOrientation,
                              paged: Bool, screen: DockScreen) -> NoteFrame {
        let v = screen.visible, (w, h) = size(orientation, paged: paged, on: screen)
        func clamp(_ value: Double, _ lo: Double, _ hi: Double) -> Double { hi < lo ? lo : min(max(value, lo), hi) }
        var x: Double, y: Double
        switch edge {
        case .left: x = v.x + gap
        case .right: x = v.x + v.width - gap - w
        case .top, .bottom: x = 0
        }
        switch edge {
        case .top: y = v.y + v.height - gap - h
        case .bottom: y = v.y + gap
        case .left, .right: y = 0
        }
        let along = alongEdge(orientation, edge)
        if edge == .left || edge == .right {
            // Vertical along a side edge: the grip (top) sits level with the entry's top.
            let preferred = along ? c + radius - h : c - h / 2
            y = clamp(preferred, v.y + gap, v.y + v.height - gap - h)
        } else {
            // Horizontal along the top or bottom: the grip (left end) starts at the entry.
            let preferred = along ? c - radius : c - w / 2
            x = clamp(preferred, v.x + gap, v.x + v.width - gap - w)
        }
        return NoteFrame(x: x, y: y, width: w, height: h)
    }

    /// The entry position matching a capsule released at `frame`, so snapping an expanded
    /// toolbar does not move it along the edge.
    static func anchor(ofCapsule frame: NoteFrame, edge: ToolbarEdge, orientation: ToolbarOrientation) -> Double {
        let along = alongEdge(orientation, edge)
        if edge == .left || edge == .right { return along ? frame.y + frame.height - radius : frame.y + frame.height / 2 }
        return along ? frame.x + radius : frame.x + frame.width / 2
    }

    /// Edges that face outward: an edge another display continues past is a seam, not an edge.
    public static func outerEdges(of screen: DockScreen, among screens: [DockScreen]) -> Set<ToolbarEdge> {
        // Visible frames lose the menu bar or Dock, so neighbours touch within a band.
        let band = 48.0, v = screen.visible
        var edges = Set(ToolbarEdge.allCases)
        for other in screens where other.id != screen.id {
            let o = other.visible
            let overlapsY = o.y < v.y + v.height && o.y + o.height > v.y
            let overlapsX = o.x < v.x + v.width && o.x + o.width > v.x
            if overlapsY && abs(o.x + o.width - v.x) <= band { edges.remove(.left) }
            if overlapsY && abs(o.x - (v.x + v.width)) <= band { edges.remove(.right) }
            if overlapsX && abs(o.y - (v.y + v.height)) <= band { edges.remove(.top) }
            if overlapsX && abs(o.y + o.height - v.y) <= band { edges.remove(.bottom) }
        }
        return edges
    }

    /// The edge a released frame snaps to: the nearest outer edge within the snap distance
    /// whose display can hold the full capsule across it. Ties keep the previous edge, then
    /// go left, right, top, bottom.
    public static func snapEdge(_ visible: NoteFrame, screen: DockScreen, screens: [DockScreen],
                                orientation: ToolbarOrientation, paged: Bool, previous: ToolbarEdge?) -> ToolbarEdge? {
        let v = screen.visible, outer = outerEdges(of: screen, among: screens)
        let (w, h) = size(orientation, paged: paged, on: screen)
        let distances: [(ToolbarEdge, Double)] = [
            (.left, visible.x - v.x), (.right, v.x + v.width - visible.x - visible.width),
            (.top, v.y + v.height - visible.y - visible.height), (.bottom, visible.y - v.y)]
        let fits = distances.filter { edge, distance in
            guard outer.contains(edge), distance <= ToolbarMetrics.snapDistance else { return false }
            return edge == .left || edge == .right ? w + gap * 2 <= v.width : h + gap * 2 <= v.height
        }
        guard let nearest = fits.map(\.1).min() else { return nil }
        let tied = fits.filter { $0.1 - nearest < 0.5 }.map(\.0)
        if let previous, tied.contains(previous) { return previous }
        return tied.first
    }

    /// Frames for a stored anchor on the current displays. A missing display falls back to
    /// the primary one, keeping the ratio or centre.
    public static func resolve(_ anchor: ToolbarAnchor?, orientation: ToolbarOrientation, paged: Bool,
                               screens: [DockScreen]) -> ToolbarFrames? {
        guard let primary = screens.first else { return nil }
        let screen = anchor?.display.flatMap { id in screens.first { $0.id == id } } ?? primary
        let (w, h) = size(orientation, paged: paged, on: screen)
        switch anchor {
        case .snapped(let edge, let ratio, _):
            let c = position(ratio: ratio, edge: edge, screen: screen)
            return ToolbarFrames(screen: screen, target: target(edge: edge, along: c, orientation: orientation, paged: paged, screen: screen),
                                 circle: circle(edge: edge, along: c, screen: screen), edge: edge)
        case .free(let cx, let cy, _):
            let frame = Arrangement.clampToolbar(NoteFrame(x: cx - w / 2, y: cy - h / 2, width: w, height: h), to: screen)
            return ToolbarFrames(screen: screen, target: frame, circle: nil, edge: nil)
        case nil:
            let v = screen.visible, m = ToolbarMetrics.screenMargin
            let frame = Arrangement.clampToolbar(NoteFrame(x: v.x + m, y: v.y + v.height - m - h, width: w, height: h), to: screen)
            return ToolbarFrames(screen: screen, target: frame, circle: nil, edge: nil)
        }
    }

    /// Where a drag ends. `visible` is the shape on screen (the round entry or the capsule);
    /// the display is the one under the pointer, else the last valid one.
    public static func release(_ visible: NoteFrame, round: Bool, pointer: (x: Double, y: Double), last: String?,
                               previous: ToolbarEdge?, orientation: ToolbarOrientation, paged: Bool,
                               screens: [DockScreen]) -> (ToolbarAnchor, ToolbarFrames)? {
        guard let screen = screens.first(where: { DockGeometry.contains($0.visible, x: pointer.x, y: pointer.y) })
                ?? screens.first(where: { $0.id == last }) ?? screens.first else { return nil }
        let display = screen.persistentID
        if let edge = snapEdge(visible, screen: screen, screens: screens, orientation: orientation, paged: paged, previous: previous) {
            let raw = round ? (edge == .left || edge == .right ? visible.y + visible.height / 2 : visible.x + visible.width / 2)
                            : anchor(ofCapsule: visible, edge: edge, orientation: orientation)
            let anchor = ToolbarAnchor.snapped(edge, ratio: ratio(along: raw, edge: edge, screen: screen), display: display)
            return resolve(anchor, orientation: orientation, paged: paged, screens: [screen]).map { (anchor, $0) }
        }
        let (w, h) = size(orientation, paged: paged, on: screen)
        // A dropped entry is the grip end: the capsule unfolds from it rather than around it.
        let proposed = round
            ? (orientation == .vertical
                ? NoteFrame(x: visible.x + visible.width / 2 - w / 2, y: visible.y + visible.height - h, width: w, height: h)
                : NoteFrame(x: visible.x, y: visible.y + visible.height / 2 - h / 2, width: w, height: h))
            : NoteFrame(x: visible.x, y: visible.y + visible.height - h, width: w, height: h)
        let frame = Arrangement.clampToolbar(proposed, to: screen)
        let anchor = ToolbarAnchor.free(centerX: frame.x + w / 2, centerY: frame.y + h / 2, display: display)
        return (anchor, ToolbarFrames(screen: screen, target: frame, circle: nil, edge: nil))
    }
}

extension Arrangement {
    /// The largest part of `bounds` that keeps `gap` clear of `obstacle`: right of it, left
    /// of it, below or above, in that order on ties. Bounds the obstacle misses are returned whole.
    public static func largestFree(_ bounds: NoteFrame, avoiding obstacle: NoteFrame, gap: Double) -> NoteFrame {
        let o = obstacle, b = bounds
        guard o.x < b.x + b.width, o.x + o.width > b.x, o.y < b.y + b.height, o.y + o.height > b.y else { return b }
        let right = max(b.x, o.x + o.width + gap), above = max(b.y, o.y + o.height + gap)
        let candidates = [
            NoteFrame(x: right, y: b.y, width: b.x + b.width - right, height: b.height),
            NoteFrame(x: b.x, y: b.y, width: min(b.x + b.width, o.x - gap) - b.x, height: b.height),
            NoteFrame(x: b.x, y: b.y, width: b.width, height: min(b.y + b.height, o.y - gap) - b.y),
            NoteFrame(x: b.x, y: above, width: b.width, height: b.y + b.height - above)
        ].filter { $0.width > 0 && $0.height > 0 }
        var best: NoteFrame?
        for candidate in candidates where candidate.width * candidate.height > (best.map { $0.width * $0.height } ?? 0) { best = candidate }
        return best ?? NoteFrame(x: b.x, y: b.y, width: 1, height: 1)
    }
}

extension DockGeometry {
    /// Strips leave the toolbar's full expanded frame alone: when the toolbar reaches into
    /// the band a strip would use, the strip takes the largest region clear of it.
    public static func region(_ region: DockScreen, edge: DockEdge, avoiding toolbar: NoteFrame?) -> DockScreen {
        guard let toolbar else { return region }
        let a = region.available, v = region.visible
        let depth = edge == .top ? (v.height < 700 ? 200.0 : 260.0) : sideWidth
        let band: NoteFrame
        switch edge {
        case .top: band = NoteFrame(x: a.x, y: a.y + a.height - depth, width: a.width, height: depth)
        case .left: band = NoteFrame(x: a.x, y: a.y, width: depth, height: a.height)
        case .right: band = NoteFrame(x: a.x + a.width - depth, y: a.y, width: depth, height: a.height)
        }
        let t = toolbar
        guard t.x < band.x + band.width, t.x + t.width > band.x, t.y < band.y + band.height, t.y + t.height > band.y else { return region }
        return DockScreen(id: region.id, visible: Arrangement.largestFree(v, avoiding: toolbar, gap: gap))
    }
}
