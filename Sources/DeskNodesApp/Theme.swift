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
    /// Low-saturation sage: completion fill, selection outline and the undo action.
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
    static let selection = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(sRGBHex: "8DB887").withAlphaComponent(0.85) : NSColor(sRGBHex: "8FB487")
    }
    static let hairline = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.10) : NSColor.black.withAlphaComponent(0.08)
    }
    static func background(_ palette: NotePalette) -> NSColor {
        dynamic(palette.lightHex, palette.darkHex)
    }
}
