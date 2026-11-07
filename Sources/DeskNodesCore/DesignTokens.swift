/// Platform independent design values. Hex strings are sRGB, without alpha.
public enum NotePalette: String, CaseIterable, Sendable {
    case paper, lemon, apricot, cherry, lavender, mist, mint, graphite

    public var name: String {
        switch self {
        case .paper: return "宣纸"
        case .lemon: return "柠黄"
        case .apricot: return "杏"
        case .cherry: return "樱"
        case .lavender: return "薰衣草"
        case .mist: return "雾蓝"
        case .mint: return "薄荷"
        case .graphite: return "石墨"
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
        case .graphite: return "E8E8EA"
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
        case .graphite: return "2A2A2D"
        }
    }
}

public enum NoteMetrics {
    public static let width = 240.0
    public static let padding = 14.0
    public static let cornerRadius = 12.0
    public static let titleSize = 13.0
    public static let itemSize = 13.0
    public static let rowHeight = 26.0
    public static let checkboxSize = 16.0
    public static let checkboxGap = 9.0
    // Reserved for N4; no collapse or resizing behavior in N1.
    public static let collapsedHeight = 32.0
    public static let collapsedCornerRadius = 10.0
    public static let minimumWidth = 200.0
    public static let minimumHeight = 120.0
    public static let maximumWidth = 400.0
    public static let maximumHeight = 600.0
    public static let scrollHeight = 480.0
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
    public static func insertionDuration(reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : 0.30
    }
}

/// A boundary for future structural commands, not an item-editing implementation.
public enum CompositionPolicy {
    public static func allowsStructuralCommand(hasMarkedText: Bool) -> Bool {
        !hasMarkedText
    }
}
