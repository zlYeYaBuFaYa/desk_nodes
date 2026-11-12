/// Platform independent design values. Hex strings are sRGB, without alpha.
/// 石墨 (graphite) was retired; stored or imported graphite notes read as 宣纸.
public enum NotePalette: String, CaseIterable, Codable, Sendable {
    case paper, lemon, apricot, cherry, lavender, mist, mint

    /// A stored or imported value, where retired graphite reads as paper.
    public init?(stored raw: String) {
        guard let palette = raw == "graphite" ? .paper : NotePalette(rawValue: raw) else { return nil }
        self = palette
    }
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let palette = NotePalette(stored: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown palette \(raw)"))
        }
        self = palette
    }

    /// Colour for a new note: the one used least by live notes; ties go to the first
    /// in palette order after the most recently created note's colour.
    public static func next(inUse: [NotePalette], latest: NotePalette?) -> NotePalette {
        let counts = Dictionary(inUse.map { ($0, 1) }, uniquingKeysWith: +)
        let start = latest.flatMap { allCases.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        let order = (0..<allCases.count).map { allCases[(start + $0) % allCases.count] }
        return order.min { counts[$0, default: 0] < counts[$1, default: 0] }!
    }

    public var name: String {
        switch self {
        case .paper: return "宣纸"
        case .lemon: return "柠黄"
        case .apricot: return "杏"
        case .cherry: return "樱"
        case .lavender: return "薰衣草"
        case .mist: return "雾蓝"
        case .mint: return "薄荷"
        }
    }

    public var lightHex: String {
        switch self {
        case .paper: return "F6F1E7"
        case .lemon: return "FAF0C8"
        case .apricot: return "FBE7D6"
        case .cherry: return "F7E1E4"
        case .lavender: return "ECE6F5"
        case .mist: return "E3ECF5"
        case .mint: return "E2F0E8"
        }
    }

    public var darkHex: String {
        switch self {
        case .paper: return "2B2822"
        case .lemon: return "35301A"
        case .apricot: return "3A2A20"
        case .cherry: return "3A2328"
        case .lavender: return "2A2536"
        case .mist: return "1F2A36"
        case .mint: return "1E2E26"
        }
    }
}

public enum NoteMetrics {
    public static let width = 288.0
    public static let padding = 18.0
    public static let cornerRadius = 13.0
    public static let titleSize = 16.0
    public static let itemSize = 14.0
    public static let secondarySize = 12.0
    /// A single-line item row; wrapped lines inside it use the tighter `lineHeight`.
    public static let rowHeight = 32.0
    public static let lineHeight = 22.0
    public static var rowPadding: Double { (rowHeight - lineHeight) / 2 }
    public static let checkboxSize = 16.0
    public static let checkboxGap = 11.0
    /// Grip row plus title row; the item list starts below it.
    public static let headerHeight = 50.0
    /// Hairline plus the "添加事项" row.
    public static let footerHeight = 44.0
    /// Hover-only delete/reorder controls at the end of an item row.
    public static let rowTrailing = 30.0
    public static let collapsedHeight = 32.0
    public static let collapsedCornerRadius = 10.0
    public static let minimumWidth = 200.0
    public static let minimumHeight = 120.0
    public static let maximumWidth = 400.0
    public static let maximumHeight = 600.0
    public static let scrollHeight = 480.0
}

/// The resident toolbar: a capsule laid out vertically or horizontally, which can shrink
/// to a round entry while it is snapped to a display edge. All values are points.
public enum ToolbarMetrics {
    /// The capsule's short side, in either orientation.
    public static let width = 64.0
    /// Half the short side: the ends are full semicircles.
    public static let cornerRadius = 32.0
    public static let circleDiameter = 48.0
    /// Extra room at each end so the grip, count and pager stay clear of the end caps.
    public static let endCap = 10.0
    public static let gripHeight = 24.0
    /// A button's extent along the long axis: taller rows vertically, wider cells horizontally.
    public static let buttonHeight = 52.0
    public static let buttonWidth = 60.0
    public static let buttonCount = 6.0
    public static let footerHeight = 32.0
    public static let footerWidth = 68.0
    /// Page switcher, present only while an arrangement overflows.
    public static let pagerHeight = 28.0
    public static let pagerWidth = 64.0
    public static let inset = 6.0
    /// Distance kept from the screen edge on first launch.
    public static let screenMargin = 20.0
    /// Release within this distance of an outer display edge snaps to it.
    public static let snapDistance = 24.0
    /// Gap kept between a snapped toolbar (either shape) and its edge.
    public static let edgeGap = 8.0
    /// Pointer travel that turns a press on the round entry into a drag.
    public static let dragThreshold = 4.0
    /// Dwell on the round entry before it expands, so passing pointers do not open it.
    public static let hoverIntent = 0.14
    /// A hover-opened toolbar that is left without a click shrinks after this, not the full delay.
    public static let hoverGrace = 1.5
    public static let autoShrinkChoices = [0, 10, 15, 30]
    public static let defaultAutoShrink = 15
    /// Long side of the vertical layout.
    public static func height(paged: Bool) -> Double { length(horizontal: false, paged: paged) }
    public static func length(horizontal: Bool, paged: Bool) -> Double {
        let ends = (inset + endCap) * 2 + gripHeight
        return horizontal
            ? ends + buttonWidth * buttonCount + footerWidth + (paged ? pagerWidth : 0)
            : ends + buttonHeight * buttonCount + footerHeight + (paged ? pagerHeight : 0)
    }
}

/// "整理" spacing, in points.
public enum ArrangeMetrics {
    public static let gap = 18.0
    public static let margin = 22.0
}

public enum NoteInk {
    public static let primaryLight = "1F1F1F"
    public static let primaryDark = "EDEBE6"
    public static let secondaryLight = "5F5A52"
    public static let secondaryDark = "B3ADA2"
    public static let completedLight = "6F6A61"
    public static let completedDark = "A39D92"
}

public enum MotionPolicy {
    public static let insertion = 0.20
    public static let deletion = 0.18
    public static let arrangement = 0.26
    public static let gathering = 0.28
    /// Toolbar snap, and the round entry's full expand or shrink.
    public static let toolbarSnap = 0.20
    public static let toolbarMorph = 0.26
    /// Reduce Motion keeps only a very short cross-fade for spatial transitions.
    public static let reducedFade = 0.12
    public static func insertionDuration(reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : insertion
    }
}

/// A boundary for future structural commands, not an item-editing implementation.
public enum CompositionPolicy {
    public static func allowsStructuralCommand(hasMarkedText: Bool) -> Bool {
        !hasMarkedText
    }
}
