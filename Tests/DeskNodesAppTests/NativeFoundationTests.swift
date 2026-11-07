import AppKit
import XCTest
@testable import DeskNodesApp

final class NativeFoundationTests: XCTestCase {
    @MainActor
    func testMarkedTextSurvivesAppearanceChange() {
        _ = NSApplication.shared
        let editor = NoteTextView(text: "确认")
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        editor.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasUncommittedComposition)
        let marked = editor.markedRange()
        let selected = editor.selectedRange()
        let string = editor.string
        editor.appearance = NSAppearance(named: .darkAqua)
        editor.viewDidChangeEffectiveAppearance()
        XCTAssertEqual(editor.markedRange(), marked)
        XCTAssertEqual(editor.selectedRange(), selected)
        XCTAssertEqual(editor.string, string)
        editor.unmarkText()
        XCTAssertFalse(editor.hasUncommittedComposition)
    }

    @MainActor
    func testPreviewPanelCanEditWithoutBecomingMainWindow() {
        _ = NSApplication.shared
        let panel = NotePanel(origin: .zero)
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.contentRect(forFrameRect: panel.frame).size, NSSize(width: 240, height: 130))
        XCTAssertFalse(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        panel.close()
    }
}
