import AppKit
import XCTest
import DeskNodesCore
import DeskNodesActions
import DeskNodesPersistence
@testable import DeskNodesApp

final class PaperWhiteDesignTests: XCTestCase {
    /// Measure the resolved colours, including auxiliary windows' dark paper mapping.
    @MainActor func testEveryPaperKeepsTextControlsAndSelectionReadable() throws {
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            appearance.performAsCurrentDrawingAppearance {
                for palette in NotePalette.allCases {
                    let surface = NoteTheme.background(palette)
                    for ink in [NoteTheme.primary, NoteTheme.secondary, NoteTheme.completed, NoteTheme.tertiary] {
                        XCTAssertGreaterThanOrEqual(contrast(ink, surface), 4.5, "\(palette), \(appearanceName)")
                    }
                    XCTAssertGreaterThanOrEqual(contrast(NoteTheme.checkboxBorder, surface), 3)
                    let outline = NSColor(sRGBHex: appearanceName == .aqua ? palette.selectionLightHex : palette.selectionDarkHex)
                    XCTAssertGreaterThanOrEqual(contrast(outline, surface), 3)
                }
                XCTAssertGreaterThanOrEqual(contrast(NoteTheme.checkmark, NoteTheme.checkboxFill), 3)
            }
        }
    }

    private func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        func luminance(_ color: NSColor) -> Double {
            guard let rgb = color.usingColorSpace(.sRGB) else { XCTFail("Colour must resolve to sRGB"); return 0 }
            let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { value -> Double in
                let v = Double(value)
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return zip(channels, [0.2126, 0.7152, 0.0722]).reduce(0) { $0 + $1.0 * $1.1 }
        }
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// Optional visual evidence uses the actual production AppKit views, with an isolated store.
    @MainActor func testRenderNativeSevenColourPresentation() throws {
        guard let output = ProcessInfo.processInfo.environment["DESKNODES_VISUAL_OUTPUT_DIR"] else {
            throw XCTSkip("Set DESKNODES_VISUAL_OUTPUT_DIR to render native view evidence")
        }
        _ = NSApplication.shared
        let oldSize = NoteType.size, oldFace = NoteType.face
        NoteType.size = .standard; NoteType.face = .system
        defer { NoteType.size = oldSize; NoteType.face = oldFace }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try Store(url: directory.appendingPathComponent("paper.sqlite"))
        defer { try? store.close() }
        let actions = NoteActions(store: store)
        let titles = ["今日待办", "读书清单", "生活小事", "值得记录", "灵感收集", "DeskNodes", "周末计划"]
        for (index, palette) in NotePalette.allCases.enumerated() {
            let note = try actions.createNote()
            try actions.title(note.id, titles[index] + " · " + palette.name)
            let first = try XCTUnwrap(store.items(in: note.id).first)
            try actions.text(first.id, in: note.id, "整理本周的工作计划")
            try actions.toggle(first.id, in: note.id)
            let next = try actions.add(in: note.id, after: first.id, text: "打磨界面细节 · Review")
            let struck = try actions.add(in: note.id, after: next.id, text: "暂时不做的另一件事")
            try actions.strike(struck.id, in: note.id)
            _ = try actions.add(in: note.id, after: struck.id, text: "读书 20 分钟，记下新的想法")
        }
        try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
        for (name, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1272, height: 700),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let canvas = try XCTUnwrap(window.contentView)
            canvas.wantsLayer = true
            canvas.appearance = NSAppearance(named: appearanceName)
            canvas.layer?.backgroundColor = NSColor(sRGBHex: name == "light" ? "E9EDE9" : "222A26").cgColor
            let heading = NSTextField(labelWithString: "纸白轻笺  ·  七色原生视图")
            heading.font = .systemFont(ofSize: 20, weight: .semibold)
            heading.textColor = NoteTheme.primary
            heading.frame = NSRect(x: 24, y: 654, width: 500, height: 28)
            canvas.addSubview(heading)
            for (index, note) in try store.notes().enumerated() {
                let card = NoteCardView(note: note, actions: actions, changed: {}, undoDelete: { false }, failure: { XCTFail("\($0)") })
                // Desktop paper stays light, including on a dark desktop.
                card.appearance = NSAppearance(named: .aqua)
                card.frame = NSRect(x: 24 + index % 4 * 312, y: 348 - index / 4 * 304, width: 288, height: 280)
                canvas.addSubview(card)
                card.layoutSubtreeIfNeeded()
            }
            let toolbar = ToolbarRoot()
            toolbar.frame = NSRect(x: 1000, y: 36, width: 64, height: 296)
            canvas.addSubview(toolbar)
            toolbar.content.count.stringValue = "7"
            toolbar.arrange(shell: toolbar.bounds, controls: toolbar.bounds, controlsAlpha: 1,
                            staggered: false, badge: nil, iconAlpha: 0)
            canvas.layoutSubtreeIfNeeded()
            canvas.displayIfNeeded()
            let bitmap = try XCTUnwrap(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
            canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: output).appendingPathComponent("paper-white-\(name).png"))
        }
    }
}
