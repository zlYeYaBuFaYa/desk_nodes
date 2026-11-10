import AppKit
import XCTest
import DeskNodesActions
import DeskNodesPersistence
@testable import DeskNodesApp

final class EditingImprovementTests: XCTestCase {
    func testPastedListLinesDropMarkersAndBlankLines() {
        XCTAssertEqual(NoteTextView.listLines("- 买牛奶\n\n* 取快递\r\n• 交电费\n- [ ] 写周报\n1. 第一\n3.14 不是序号\n  "),
                       ["买牛奶", "取快递", "交电费", "写周报", "第一", "3.14 不是序号"])
        XCTAssertEqual(NoteTextView.listLines("单行"), ["单行"])
    }

    func testRecorderShortcutTextMatchesTheParser() throws {
        let text = try XCTUnwrap(HotkeyKeyCodes.shortcut(keyCode: 45, modifiers: [.control, .option]))
        XCTAssertEqual(text, "Control+Option+N")
        XCTAssertEqual(try Hotkey(text).canonical, text)
        XCTAssertNil(HotkeyKeyCodes.shortcut(keyCode: 122, modifiers: [.command])) // F1
        XCTAssertEqual(ShortcutText.symbols("Control+Option+Shift+Command+Space"), "⌃⌥⇧⌘Space")
    }

    @MainActor
    func testTypingIsSavedAfterAPauseOrAtTheNextFlush() throws {
        _ = NSApplication.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let store = try Store(url: url); defer { try? store.close() }
        let actions = NoteActions(store: store), note = try actions.createNote()
        let item = try XCTUnwrap(store.items(in: note.id).first)
        var refreshes = 0
        let card = NoteCardView(note: note, actions: actions, changed: { refreshes += 1 }, undoDelete: { false }, failure: { XCTFail("\($0)") })
        let editor = try XCTUnwrap(card.firstEditor)
        for text in ["a", "ab", "abc"] { editor.string = text; card.save(item.id, text: text) }
        XCTAssertEqual(try store.items(in: note.id).first?.text, "", "no write per keystroke")
        XCTAssertEqual(refreshes, 0)
        try card.flushRolloverEdits()
        XCTAssertEqual(try store.items(in: note.id).first?.text, "abc")

        editor.string = "abcd"; card.save(item.id, text: editor.string)
        let saved = expectation(description: "debounced save")
        DispatchQueue.main.asyncAfter(deadline: .now() + NoteCardView.saveDelay + 0.2) { saved.fulfill() }
        wait(for: [saved], timeout: 2)
        XCTAssertEqual(try store.items(in: note.id).first?.text, "abcd")
        XCTAssertEqual(refreshes, 1, "one refresh per pause, not per keystroke")
    }
}
