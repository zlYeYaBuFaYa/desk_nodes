import XCTest
@testable import DeskNodesCore

final class DesignTokensTests: XCTestCase {
    func testAllEightSpecificationPairsInOrder() {
        let expected = [
            ["宣纸", "F6F1E7", "2B2822"], ["柠黄", "FAF0C8", "35301A"],
            ["杏", "FBE7D6", "3A2A20"], ["樱", "F7E1E4", "3A2328"],
            ["薰衣草", "ECE6F5", "2A2536"], ["雾蓝", "E3ECF5", "1F2A36"],
            ["薄荷", "E2F0E8", "1E2E26"], ["石墨", "E8E8EA", "2A2A2D"]
        ]
        XCTAssertEqual(NotePalette.allCases.map { [$0.name, $0.lightHex, $0.darkHex] }, expected)
    }

    func testRedesignSizingAndCollapsedHeight() {
        XCTAssertEqual(NoteMetrics.width, 288)
        XCTAssertEqual(NoteMetrics.padding, 18)
        XCTAssertEqual(NoteMetrics.cornerRadius, 13)
        XCTAssertEqual(NoteMetrics.titleSize, 16)
        XCTAssertEqual(NoteMetrics.itemSize, 14)
        XCTAssertEqual(NoteMetrics.rowHeight, 32)
        XCTAssertEqual(NoteMetrics.collapsedHeight, 32)
        XCTAssertEqual(NoteMetrics.minimumWidth, 200)
        XCTAssertEqual(NoteMetrics.maximumHeight, 600)
    }

    func testReduceMotionRemovesInsertionMovement() {
        XCTAssertEqual(MotionPolicy.insertionDuration(reduceMotion: true), 0)
        XCTAssertTrue((0.16...0.22).contains(MotionPolicy.insertionDuration(reduceMotion: false)))
    }

    func testToolbarHeightOnlyGrowsForThePager() {
        XCTAssertEqual(ToolbarMetrics.height(paged: true) - ToolbarMetrics.height(paged: false), ToolbarMetrics.pagerHeight)
        XCTAssertGreaterThanOrEqual(ToolbarMetrics.buttonHeight, 44)
    }

    func testCompositionBlocksFutureStructuralCommands() {
        XCTAssertFalse(CompositionPolicy.allowsStructuralCommand(hasMarkedText: true))
        XCTAssertTrue(CompositionPolicy.allowsStructuralCommand(hasMarkedText: false))
    }
}
