import AppKit
import DeskNodesCore

extension NSColor {
    convenience init(sRGBHex hex: String) {
        let value = UInt32(hex, radix: 16)!
        self.init(srgbRed: CGFloat((value >> 16) & 255) / 255,
                  green: CGFloat((value >> 8) & 255) / 255,
                  blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}

/// Note type and row metrics at the current 文字大小. Read live: a change applies on each
/// card's `applyTextSize()` and next layout. Standard equals the `NoteMetrics` values.
enum NoteType {
    static var size = NoteTextSize.standard
    static var titleSize: CGFloat { CGFloat(size.titleSize) }
    static var itemSize: CGFloat { CGFloat(size.itemSize) }
    static var secondarySize: CGFloat { CGFloat(size.secondarySize) }
    static var rowHeight: CGFloat { CGFloat(size.scaled(NoteMetrics.rowHeight)) }
    static var lineHeight: CGFloat { CGFloat(size.scaled(NoteMetrics.lineHeight)) }
    static var rowPadding: CGFloat { (rowHeight - lineHeight) / 2 }
    static var checkboxSize: CGFloat { CGFloat(size.scaled(NoteMetrics.checkboxSize)) }
    static var checkboxGap: CGFloat { CGFloat(size.scaled(NoteMetrics.checkboxGap)) }
    static var headerHeight: CGFloat { CGFloat(size.scaled(NoteMetrics.headerHeight)) }
    static var footerHeight: CGFloat { CGFloat(size.scaled(NoteMetrics.footerHeight)) }
}

enum NoteTheme {
    static func dynamic(_ light: String, _ dark: String) -> NSColor {
        NSColor(name: nil) { appearance in
            NSColor(sRGBHex: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        }
    }
    static let primary = dynamic(NoteInk.primaryLight, NoteInk.primaryDark)
    static let secondary = dynamic(NoteInk.secondaryLight, NoteInk.secondaryDark)
    static let completed = dynamic(NoteInk.completedLight, NoteInk.completedDark)
    /// Low-saturation sage: completion fill and the undo action.
    static let accent = dynamic("6E9A68", "8DB887")
    static let checkboxFill = accent
    static let checkboxBorder = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(sRGBHex: dark ? NoteInk.primaryDark : NoteInk.primaryLight).withAlphaComponent(dark ? 0.5 : 0.42)
    }
    static let checkmark = dynamic("FFFFFF", "2B2822")
    static let border = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.06)
    }
    static let tertiary = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(sRGBHex: NoteInk.secondaryDark).withAlphaComponent(0.55)
            : NSColor(sRGBHex: NoteInk.secondaryLight).withAlphaComponent(0.5)
    }
    /// Selection outline in the note's own hue; faded while another app is active.
    static func selection(_ palette: NotePalette, active: Bool) -> NSColor {
        dynamic(palette.selectionLightHex, palette.selectionDarkHex).withAlphaComponent(active ? 1 : 0.45)
    }
    static let hairline = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.10) : NSColor.black.withAlphaComponent(0.08)
    }
    // Stable, opaque toolbar colours keep its small labels legible on any wallpaper.
    static let toolbarBackground = dynamic("F6F5F1", "272A2E")
    static let toolbarInk = dynamic("24282D", "F2F4F6")
    static let toolbarSecondary = dynamic("5C636B", "BDC4CC")
    static let toolbarDisabled = dynamic("878D94", "858D97")
    static let toolbarBorder = dynamic("D1D2CE", "50555C")
    static func background(_ palette: NotePalette) -> NSColor {
        dynamic(palette.lightHex, palette.darkHex)
    }
}
