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

/// Note type and row metrics at the current 文字大小 and 字体. Read live: a change applies on
/// each card's `applyTextSize()` and next layout. Standard equals the `NoteMetrics` values.
enum NoteType {
    static var size = NoteTextSize.standard
    static var face = NoteFont.system
    /// Note text in the current 字体: titles ask for `.semibold`, items for `.regular`.
    static func font(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NoteFonts.font(face, size: size, weight: weight)
    }
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
    /// Paper White: deep pine on light paper, soft pine on dark auxiliary surfaces.
    static let accent = dynamic("426B58", "9AC7AB")
    static let checkboxFill = accent
    // Unchecked controls and struck text remain readable on every paper colour.
    static let checkboxBorder = secondary
    static let checkmark = dynamic("FFFFFF", "243029")
    static let border = dynamic("D5DCD5", "4A574E")
    static let tertiary = secondary
    /// Selection outline in the note's own hue; faded while another app is active.
    static func selection(_ palette: NotePalette, active: Bool) -> NSColor {
        dynamic(palette.selectionLightHex, palette.selectionDarkHex).withAlphaComponent(active ? 1 : 0.45)
    }
    static let hairline = dynamic("D5DCD5", "4A574E")
    // The toolbar sits on system material; stable ink and a fine rim keep it legible on any wallpaper.
    static let toolbarInk = dynamic("354239", "E4EBE6")
    static let toolbarSecondary = dynamic("626E65", "BFCBC2")
    static let toolbarDisabled = dynamic("858F87", "8D9C92")
    static let toolbarBorder = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.10)
    }
    static func background(_ palette: NotePalette) -> NSColor {
        dynamic(palette.lightHex, palette.darkHex)
    }
}

/// The faces behind each 字体. 圆体 and 宋体 take the system's Latin design and cascade to a
/// macOS Chinese family; 文楷 is bundled with the app (Latin included) in Regular and Medium.
/// A face that is not on this Mac falls back to the system font, never to a blank.
enum NoteFonts {
    static let wenkaiRegular = "LXGWWenKai-Regular"
    static let wenkaiMedium = "LXGWWenKai-Medium"
    /// Downloadable from Apple: not every Mac has it until asked for.
    static let yuanti = "Yuanti SC"
    static let songti = "Songti SC"

    static func font(_ face: NoteFont, size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: weight)
        // Chinese families here step Regular → Bold; a title's semibold takes Bold.
        let bold = weight.rawValue >= NSFont.Weight.semibold.rawValue
        switch face {
        case .system: return system
        case .rounded: return paired(system, design: .rounded, chinese: yuanti, bold: bold, size: size)
        case .serif: return paired(system, design: .serif, chinese: songti, bold: bold, size: size)
        case .wenkai:
            let name = weight.rawValue >= NSFont.Weight.medium.rawValue ? wenkaiMedium : wenkaiRegular
            return NSFont(name: name, size: size) ?? NSFont(name: wenkaiRegular, size: size) ?? system
        }
    }
    private static func paired(_ base: NSFont, design: NSFontDescriptor.SystemDesign, chinese family: String,
                               bold: Bool, size: CGFloat) -> NSFont {
        let chinese = NSFontDescriptor(fontAttributes: [
            .family: family, .traits: [NSFontDescriptor.TraitKey.weight: (bold ? NSFont.Weight.bold : .regular).rawValue]])
        let latin = base.fontDescriptor.withDesign(design) ?? base.fontDescriptor
        return NSFont(descriptor: latin.addingAttributes([.cascadeList: [chinese]]), size: size) ?? base
    }
    /// Whether this Mac can show the face as designed right now.
    static func isAvailable(_ face: NoteFont) -> Bool {
        switch face {
        case .system, .serif: return true
        case .rounded: return NSFontManager.shared.availableMembers(ofFontFamily: yuanti) != nil
        case .wenkai: return NSFont(name: wenkaiRegular, size: 13) != nil
        }
    }
    /// Asks macOS to download 圆体-简. `completion` runs on the main thread once, with nil
    /// on success or the reason it failed.
    @MainActor static func download(_ face: NoteFont, completion: @escaping @MainActor (String?) -> Void) {
        guard face == .rounded, !isAvailable(face) else { completion(nil); return }
        var reported = false
        let finish: @MainActor (String?) -> Void = { failure in
            guard !reported else { return }
            reported = true; completion(failure)
        }
        let descriptors = [NSFontDescriptor(fontAttributes: [.family: yuanti])] as CFArray
        // Progress arrives on a background queue; outcomes hop to the main thread.
        let started = CTFontDescriptorMatchFontDescriptorsWithProgressHandler(descriptors, nil) { state, progress in
            let error = (progress as NSDictionary)[kCTFontDescriptorMatchingError] as? NSError
            switch state {
            case .didFinish:
                DispatchQueue.main.async { MainActor.assumeIsolated {
                    finish(isAvailable(.rounded) ? nil : "下载已结束，但系统没有提供“圆体-简”。")
                } }
            case .didFailWithError:
                let reason = error?.localizedDescription ?? "未知错误"
                DispatchQueue.main.async { MainActor.assumeIsolated { finish("无法下载“圆体-简”：\(reason)") } }
            default: break
            }
            return true
        }
        if !started { finish("无法开始下载“圆体-简”。") }
    }
}
