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

enum NoteTheme {
    static func dynamic(_ light: String, _ dark: String) -> NSColor {
        NSColor(name: nil) { appearance in
            NSColor(sRGBHex: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        }
    }
    static let primary = dynamic(NoteInk.primaryLight, NoteInk.primaryDark)
    static let secondary = dynamic(NoteInk.secondaryLight, NoteInk.secondaryDark)
    static let completed = dynamic(NoteInk.completedLight, NoteInk.completedDark)
    static let checkboxFill = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(sRGBHex: dark ? NoteInk.primaryDark : NoteInk.primaryLight).withAlphaComponent(dark ? 0.8 : 0.72)
    }
    static let checkboxBorder = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(sRGBHex: dark ? NoteInk.primaryDark : NoteInk.primaryLight).withAlphaComponent(dark ? 0.5 : 0.42)
    }
    static let checkmark = dynamic("FFFFFF", "2B2822")
    static let border = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.06)
    }
    static func background(_ palette: NotePalette) -> NSColor {
        dynamic(palette.lightHex, palette.darkHex)
    }
}
