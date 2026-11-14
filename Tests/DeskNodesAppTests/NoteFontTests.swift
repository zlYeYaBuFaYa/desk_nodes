import XCTest
import AppKit
import CoreText
import DeskNodesCore
@testable import DeskNodesApp

final class NoteFontTests: XCTestCase {
    func testChoicesAreNamedAndTheDefaultIsTheSystemFace() {
        XCTAssertEqual(NoteFont.allCases.map(\.name), ["默认", "圆体", "宋体", "文楷"])
        XCTAssertEqual(NoteFonts.font(.system, size: 14, weight: .regular), NSFont.systemFont(ofSize: 14))
        XCTAssertEqual(NoteFonts.font(.system, size: 16, weight: .semibold), NSFont.systemFont(ofSize: 16, weight: .semibold))
    }

    func testRoundedAndSerifCascadeToTheirChineseFamily() {
        for (face, family) in [(NoteFont.rounded, NoteFonts.yuanti), (.serif, NoteFonts.songti)] {
            let font = NoteFonts.font(face, size: 14, weight: .semibold)
            XCTAssertEqual(font.pointSize, 14)
            let cascade = font.fontDescriptor.object(forKey: .cascadeList) as? [NSFontDescriptor]
            XCTAssertEqual(cascade?.first?.object(forKey: .family) as? String, family, "\(face)")
        }
    }

    /// With the bundled files present (scripts/fetch-fonts.sh), titles take Medium and items
    /// Regular; without them the system font stands in rather than nothing.
    func testWenKaiTitlesUseMediumAndAMissingFaceFallsBack() throws {
        let fonts = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Fonts")
        let files = ["LXGWWenKai-Regular.ttf", "LXGWWenKai-Medium.ttf"].map { fonts.appendingPathComponent($0) }
        guard files.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
            XCTAssertEqual(NoteFonts.font(.wenkai, size: 14, weight: .regular).pointSize, 14)
            throw XCTSkip("Resources/Fonts not fetched")
        }
        for file in files where NSFont(name: file.deletingPathExtension().lastPathComponent, size: 12) == nil {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
        XCTAssertEqual(NoteFonts.font(.wenkai, size: 14, weight: .regular).fontName, NoteFonts.wenkaiRegular)
        XCTAssertEqual(NoteFonts.font(.wenkai, size: 16, weight: .semibold).fontName, NoteFonts.wenkaiMedium)
        XCTAssertTrue(NoteFonts.isAvailable(.wenkai))
    }
}
