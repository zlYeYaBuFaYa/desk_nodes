import AppKit
import XCTest
import DeskNodesCore
import DeskNodesActions
import DeskNodesPersistence
@testable import DeskNodesApp

final class DesktopRedesignTests: XCTestCase {
    private var url: URL!
    private var store: Store!
    private var actions: NoteActions!

    @MainActor override func setUpWithError() throws {
        _ = NSApplication.shared
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        store = try Store(url: url); actions = NoteActions(store: store)
    }
    override func tearDownWithError() throws {
        try store.close()
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
    }

    /// Vertical centre of the inked glyphs on an editor's first line, in row coordinates.
    @MainActor private func firstLineInkCenter(_ row: ItemRow) throws -> CGFloat {
        let editor = row.editor
        let manager = try XCTUnwrap(editor.layoutManager), storage = try XCTUnwrap(editor.textStorage)
        manager.ensureLayout(for: try XCTUnwrap(editor.textContainer))
        var range = NSRange()
        let line = manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: &range)
        var top = CGFloat.infinity, bottom = -CGFloat.infinity
        for glyph in range.location..<NSMaxRange(range) {
            let character = manager.characterIndexForGlyph(at: glyph)
            guard let scalar = (storage.string as NSString).substring(with: NSRange(location: character, length: 1)).unicodeScalars.first,
                  !CharacterSet.whitespacesAndNewlines.contains(scalar),
                  let font = storage.attribute(.font, at: character, effectiveRange: nil) as? NSFont else { continue }
            // Line fragments are in text-container coordinates; add the container's inset.
            let baseline = editor.textContainerOrigin.y + line.minY + manager.location(forGlyphAt: glyph).y
            let ink = font.boundingRect(forCGGlyph: manager.cgGlyph(at: glyph))
            top = min(top, baseline - ink.maxY); bottom = max(bottom, baseline - ink.minY)
        }
        XCTAssertTrue(top.isFinite, "first line has visible glyphs")
        return row.convert(NSPoint(x: 0, y: (top + bottom) / 2), from: editor).y
    }

    @MainActor func testCompletionCircleAlignsWithTheFirstLineForEveryScript() throws {
        let note = try actions.createNote(frame: NoteFrame(x: 0, y: 0, width: NoteMetrics.width, height: 400))
        let texts = ["整理项目需求", "Review the layout", "2026 12 31", "读书 20 分钟 · Swift",
                     "这是一条很长很长的中文事项，用来确认换行以后圆圈仍然对齐第一行而不是整段文字的中间位置"]
        let first = try XCTUnwrap(store.items(in: note.id).first)
        try actions.text(first.id, in: note.id, texts[0])
        var anchor = first.id
        for text in texts.dropFirst() { anchor = try actions.add(in: note.id, after: anchor, text: text).id }
        let card = NoteCardView(note: try XCTUnwrap(store.notes().first), actions: actions, changed: {}, undoDelete: { false }, failure: { XCTFail("\($0)") })
        card.frame = NSRect(x: 0, y: 0, width: NoteMetrics.width, height: 400)
        card.layoutSubtreeIfNeeded()
        card.itemRows.forEach { $0.layoutSubtreeIfNeeded() }
        XCTAssertEqual(card.itemRows.count, texts.count)
        for row in card.itemRows {
            XCTAssertEqual(try firstLineInkCenter(row), row.circleCenter.y, accuracy: 1.5, row.editor.string)
        }
        let wrapped = try XCTUnwrap(card.itemRows.last)
        XCTAssertGreaterThan(wrapped.frame.height, CGFloat(NoteMetrics.rowHeight), "long text wraps")
        XCTAssertLessThan(wrapped.circleCenter.y, wrapped.bounds.midY - 8, "aligned to the first line, not the paragraph")

        // An input method's marked text keeps the same geometry.
        let editor = card.itemRows[0].editor
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        editor.setMarkedText("zheng li", selectedRange: NSRange(location: 8, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertEqual(try firstLineInkCenter(card.itemRows[0]), card.itemRows[0].circleCenter.y, accuracy: 1.5)
        editor.unmarkText()
    }

    @MainActor func testHoverNeverChangesTheTitleWidth() throws {
        let note = try actions.createNote(frame: NoteFrame(x: 0, y: 0, width: NoteMetrics.width, height: 200))
        try actions.title(note.id, "今天要做")
        let card = NoteCardView(note: try XCTUnwrap(store.notes().first), actions: actions, changed: {}, undoDelete: { false }, failure: { XCTFail("\($0)") })
        card.frame = NSRect(x: 0, y: 0, width: NoteMetrics.width, height: 200)
        card.layoutSubtreeIfNeeded()
        let idle = card.titleFrame
        let enter = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
                                                         windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        card.mouseEntered(with: enter); card.layoutSubtreeIfNeeded()
        XCTAssertEqual(card.titleFrame, idle)
        XCTAssertLessThan(idle.width, CGFloat(NoteMetrics.width) / 2, "an idle title leaves the header free for dragging")
    }

    @MainActor func testSuppressedPanelsStayHiddenThroughRefreshAndSelectionFollowsRemoval() throws {
        let surfaces = NoteSurfaces(actions: actions, changed: {}, undo: { false }, canMutate: { true }, failure: { XCTFail("\($0)") })
        defer { surfaces.discardAll() }
        var hidden = true, selectionEvents = 0
        surfaces.hidden = { _ in hidden }
        surfaces.selectionChanged = { selectionEvents += 1 }
        let note = try actions.createNote()
        try surfaces.refresh(.all)
        let panel = try XCTUnwrap(surfaces.panels[note.id])
        XCTAssertFalse(panel.isVisible, "created while collapsed: never shown")
        panel.orderFrontRegardless(); panel.makeKeyAndOrderFront(nil)
        try surfaces.refresh(.all)
        XCTAssertFalse(panel.isVisible, "no refresh or restore path can reveal a suppressed note")
        hidden = false
        panel.suppressed = false; panel.orderFrontRegardless()
        XCTAssertTrue(panel.isVisible)

        surfaces.select(note.id)
        XCTAssertEqual(surfaces.selection, note.id)
        XCTAssertEqual(selectionEvents, 1)
        try actions.deleteNote(note.id)
        try surfaces.refresh()
        XCTAssertNil(surfaces.selection, "deleting the target clears it")
        XCTAssertEqual(selectionEvents, 2)
    }

    @MainActor func testPresentationDefaultsRoundTripOutsideTheBackup() throws {
        let suite = "local.desknodes.native.tests." + UUID().uuidString
        let raw = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { raw.removePersistentDomain(forName: suite) }
        let defaults = PresentationDefaults(raw)
        XCTAssertFalse(defaults.collapsed); XCTAssertNil(defaults.toolbar); XCTAssertTrue(defaults.pages.isEmpty)
        XCTAssertFalse(defaults.topmost)
        let id = NoteID()
        defaults.collapsed = true; defaults.topmost = true
        defaults.toolbar = .init(x: 20, y: 860, display: "37D8832A-2D66-02CA-B9F7-8F30A301B230")
        defaults.pages = [id: (page: 1, pages: 3)]; defaults.currentPage = 2
        let reopened = PresentationDefaults(raw)
        XCTAssertTrue(reopened.collapsed); XCTAssertTrue(reopened.topmost)
        XCTAssertEqual(reopened.toolbar, .init(x: 20, y: 860, display: "37D8832A-2D66-02CA-B9F7-8F30A301B230"))
        XCTAssertEqual(reopened.pages[id]?.page, 1); XCTAssertEqual(reopened.pages[id]?.pages, 3)
        XCTAssertEqual(reopened.currentPage, 2)
        XCTAssertNil(reopened.toolbarAnchor)
        XCTAssertEqual(reopened.toolbarOrientation, .vertical)
        XCTAssertEqual(reopened.toolbarAutoShrink, ToolbarMetrics.defaultAutoShrink)
        defaults.toolbarAnchor = .snapped(.right, ratio: 0.25, display: "37D8832A-2D66-02CA-B9F7-8F30A301B230")
        defaults.toolbarOrientation = .horizontal; defaults.toolbarAutoShrink = 0
        XCTAssertEqual(PresentationDefaults(raw).toolbarAnchor, .snapped(.right, ratio: 0.25, display: "37D8832A-2D66-02CA-B9F7-8F30A301B230"))
        XCTAssertEqual(PresentationDefaults(raw).toolbarOrientation, .horizontal)
        XCTAssertEqual(PresentationDefaults(raw).toolbarAutoShrink, 0)
        defaults.toolbarAnchor = .free(centerX: 52, centerY: 660, display: nil)
        XCTAssertEqual(PresentationDefaults(raw).toolbarAnchor, .free(centerX: 52, centerY: 660, display: nil))
        raw.set(7, forKey: "toolbar.autoShrink") // not an offered choice
        XCTAssertEqual(PresentationDefaults(raw).toolbarAutoShrink, ToolbarMetrics.defaultAutoShrink)
        // The JSON backup has no field for any of this.
        let backup = String(decoding: try store.exportBackup(), as: UTF8.self)
        for key in ["collapsed", "toolbar", "arrange", "desk."] { XCTAssertFalse(backup.contains(key), key) }
    }

    @MainActor func testTopmostToggleKeepsEachNotesOwnLevel() throws {
        let suite = "local.desknodes.native.tests." + UUID().uuidString
        let raw = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { raw.removePersistentDomain(forName: suite) }
        let surfaces = NoteSurfaces(actions: actions, changed: {}, undo: { false }, canMutate: { true }, failure: { XCTFail("\($0)") })
        let desk = DesktopController(actions: actions, defaults: PresentationDefaults(raw))
        desk.surfaces = { surfaces }
        var mirrored: [Bool] = []
        desk.topmostChanged = { mirrored.append($0) }
        let plain = try actions.createNote(), pinned = try actions.createNote()
        try actions.appearance(pinned.id, level: .topmost)
        try surfaces.refresh(.all)
        defer { surfaces.discardAll() }
        let button = desk.toolbar.buttons[Toolbar.Action.topmost.rawValue]
        defer { desk.toolbar.invalidate() }
        desk.sync(try store.notes())
        XCTAssertEqual(button.label, "置顶"); XCTAssertFalse(button.isOn)
        XCTAssertEqual(surfaces.panels[plain.id]?.collectionBehavior.contains(.fullScreenNone), true)

        desk.toggleTopmost()
        XCTAssertEqual(button.label, "取消置顶"); XCTAssertTrue(button.isOn)
        XCTAssertEqual(surfaces.panels[plain.id]?.level, .floating)
        XCTAssertEqual(surfaces.panels[plain.id]?.collectionBehavior.contains(.fullScreenAuxiliary), true)
        XCTAssertTrue(PresentationDefaults(raw).topmost)
        // A note created while everything floats floats too, but keeps its own desktop level.
        let late = try actions.createNote()
        try surfaces.refresh(.all)
        XCTAssertEqual(surfaces.panels[late.id]?.level, .floating)
        XCTAssertEqual(try store.notes().first { $0.id == late.id }?.level, .desktop)

        desk.toggleTopmost()
        XCTAssertEqual(button.label, "置顶"); XCTAssertFalse(button.isOn)
        XCTAssertEqual(surfaces.panels[plain.id]?.level.rawValue, Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        XCTAssertEqual(surfaces.panels[pinned.id]?.level, .floating)
        XCTAssertEqual(try store.notes().map(\.level), [.desktop, .topmost, .desktop])
        XCTAssertEqual(mirrored, [true, false])
        XCTAssertTrue(desk.toolbar.panel.collectionBehavior.contains(.fullScreenAuxiliary))
    }
}
