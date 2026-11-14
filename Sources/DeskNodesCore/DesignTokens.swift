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

    /// Selection outline: a deeper tone of the same hue, so it never clashes with the card.
    public var selectionLightHex: String {
        switch self {
        case .paper: return "B59E74"
        case .lemon: return "C9A93A"
        case .apricot: return "D9905F"
        case .cherry: return "CF7F90"
        case .lavender: return "9A82C9"
        case .mist: return "6F97C4"
        case .mint: return "6FA585"
        }
    }

    public var selectionDarkHex: String {
        switch self {
        case .paper: return "C4B08A"
        case .lemon: return "D6BE5C"
        case .apricot: return "E0A47E"
        case .cherry: return "DB98A6"
        case .lavender: return "B5A2DE"
        case .mist: return "92B4DA"
        case .mint: return "8FC4A3"
        }
    }
}

public enum NoteMetrics {
    public static let width = 288.0
    /// Size offered for new notes in Settings. Height 0 means "follow the content".
    public static let newWidthChoices = [240.0, 288.0, 340.0, 400.0]
    public static let newHeightChoices = [0.0, 200.0, 240.0, 300.0, 400.0]
    /// Default new-note height: room for about four items, so an empty note does not look cramped.
    public static let newHeight = 240.0
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
    public static let rowTrailing = 64.0
    public static let collapsedHeight = 32.0
    public static let collapsedCornerRadius = 10.0
    public static let minimumWidth = 200.0
    public static let minimumHeight = 120.0
    public static let maximumWidth = 400.0
    public static let maximumHeight = 600.0
    public static let scrollHeight = 480.0
}

/// "文字大小": one choice for every note. Width and padding stay; type, rows, the
/// checkbox and the header/footer bands scale by the item size's ratio to 14pt.
public enum NoteTextSize: String, CaseIterable, Sendable {
    case small, standard, large, extraLarge
    public var name: String {
        switch self {
        case .small: return "小"
        case .standard: return "标准"
        case .large: return "大"
        case .extraLarge: return "特大"
        }
    }
    public var itemSize: Double {
        switch self {
        case .small: return 13
        case .standard: return 14
        case .large: return 16
        case .extraLarge: return 18
        }
    }
    public var titleSize: Double {
        switch self {
        case .small: return 15
        case .standard: return 16
        case .large: return 18
        case .extraLarge: return 20
        }
    }
    public var secondarySize: Double {
        switch self {
        case .small: return 11
        case .standard: return 12
        case .large: return 14
        case .extraLarge: return 15
        }
    }
    public var scale: Double { itemSize / NoteMetrics.itemSize }
    /// A standard-size length at this size, in whole points.
    public func scaled(_ value: Double) -> Double { (value * scale).rounded() }
    /// The next step up (+1) or down (-1), stopping at either end.
    public func stepped(_ offset: Int) -> NoteTextSize {
        let all = Self.allCases, index = all.firstIndex(of: self)! + offset
        return all[min(max(0, index), all.count - 1)]
    }
}

/// "字体" for every note. Each choice pairs a Latin face with a Chinese one, so mixed text
/// reads as one style; size, rows and the checkbox follow "文字大小" either way.
public enum NoteFont: String, CaseIterable, Sendable {
    case system, rounded, serif, wenkai
    public var name: String {
        switch self {
        case .system: return "默认"
        case .rounded: return "圆体"
        case .serif: return "宋体"
        case .wenkai: return "文楷"
        }
    }
}

/// The resident toolbar: a capsule laid out vertically or horizontally, which shrinks to a
/// rounded-square entry at its home on a display edge. All values are points.
public enum ToolbarMetrics {
    /// The capsule's short side, in either orientation.
    public static let width = 64.0
    /// Half the short side: the ends are full semicircles.
    public static let cornerRadius = 32.0
    /// The shrunk entry: a rounded square, its hit area reaching out to the edge.
    public static let entrySize = 56.0
    public static let entryCornerRadius = 14.0
    /// The home keeps the entry this far from either end of its edge, so its hit area never
    /// reaches a screen corner (and a hot corner there).
    public static let homeCornerClearance = 40.0
    /// Extra room at each end so the grip, count and pager stay clear of the end caps.
    public static let endCap = 10.0
    public static let gripHeight = 24.0
    /// A button's extent along the long axis: taller rows vertically, wider cells horizontally.
    public static let buttonHeight = 52.0
    public static let buttonWidth = 60.0
    public static let buttonCount = 4.0
    public static let footerHeight = 32.0
    public static let footerWidth = 68.0
    /// Page switcher, present only while an arrangement overflows.
    public static let pagerHeight = 28.0
    public static let pagerWidth = 64.0
    public static let inset = 6.0
    /// Distance kept from the screen edge on first launch.
    public static let screenMargin = 20.0
    /// Release within this distance of an outer display edge snaps to it. Generous on
    /// purpose: a drag "to the edge" often stops well short, and a preview shows the result.
    public static let snapDistance = 81.0
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
    /// Toolbar snap, and the entry's full expand or shrink.
    public static let toolbarSnap = 0.20
    public static let toolbarMorph = 0.26
    /// Going home from elsewhere: shrink in place (controls fade first), then glide.
    public static let toolbarHomeShrink = 0.20
    public static func toolbarHomeGlide(distance: Double) -> Double {
        min(max(0.30 + distance / 3000, 0.30), 0.50)
    }
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
