import Foundation
import DeskNodesPersistence

public enum RevealSide: String, Sendable { case left, right }
extension EdgePreference {
    public func resolved(dock: String?) -> RevealSide {
        switch self { case .left: return .left; case .right: return .right
        case .automatic: return dock == "right" ? .left : .right }
    }
}
public struct RevealTarget: Equatable, Sendable {
    public let screen: String
    public let side: RevealSide
    public init(screen: String, side: RevealSide) { self.screen = screen; self.side = side }
}
public enum RevealGeometry {
    /// Full display frames, never visibleFrame. Reject any occupied point immediately
    /// beyond the edge, including partial seams, overlapping and mirrored displays.
    public static func target(x: Double, y: Double, screens: [DockScreen], side: RevealSide) -> RevealTarget? {
        guard x.isFinite, y.isFinite else { return nil }
        for (index, screen) in screens.enumerated() {
            let f = screen.visible, edge = side == .left ? f.x : f.x + f.width
            guard f.width > 0, f.height > 0, y > f.y + f.height * 0.2,
                  y < f.y + f.height * 0.8,
                  (side == .left ? x >= edge && x <= edge + 2 : x <= edge && x >= edge - 2) else { continue }
            let blocked = screens.enumerated().contains { otherIndex, other in
                guard otherIndex != index else { return false }
                let o = other.visible
                let occupiesOutside = side == .left ? o.x < edge && o.x + o.width >= edge : o.x <= edge && o.x + o.width > edge
                return (occupiesOutside || o == f) && y >= o.y && y <= o.y + o.height
            }
            if !blocked { return RevealTarget(screen: screen.id, side: side) }
        }
        return nil
    }
}
/// Caller supplies monotonic seconds. Backwards/nonfinite samples reset pending timers.
/// Visible target stays fixed until close; vertical direction is deliberately irrelevant.
public struct RevealTiming {
    public private(set) var visible: RevealTarget?
    private var candidate: RevealTarget?
    private var entered: Double?
    private var exited: Double?
    private var last: Double?
    public init() {}
    /// Nothing pending or shown: the caller may stop sampling until the pointer moves.
    public var isIdle: Bool { visible == nil && candidate == nil }
    public mutating func sample(time: Double, target: RevealTarget?, inside: Bool, editing: Bool) -> RevealTarget? {
        guard time.isFinite else { candidate = nil; entered = nil; exited = nil; last = nil; return visible }
        if let last, time < last { candidate = nil; entered = nil; exited = nil }
        last = time
        if let visible {
            if inside || target == visible || editing { exited = nil }
            else if let exited { if time >= exited + 0.4 { self.visible = nil; self.exited = nil; candidate = nil; entered = nil } }
            else { exited = time }
        } else if let target {
            if candidate != target { candidate = target; entered = time }
            else if let entered, time >= entered + 0.25 { visible = target; exited = nil }
        } else { candidate = nil; entered = nil }
        return visible
    }
    public mutating func reset() { self = Self() }
}
