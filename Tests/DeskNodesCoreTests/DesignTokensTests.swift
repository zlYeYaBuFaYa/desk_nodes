import XCTest
@testable import DeskNodesCore

final class DesignTokensTests: XCTestCase {
    func testSevenPalettePairsInOrderWithoutGraphite() {
        let expected = [
            ["宣纸", "F6F1E7", "2B2822"], ["柠黄", "FAF0C8", "35301A"],
            ["杏", "FBE7D6", "3A2A20"], ["樱", "F7E1E4", "3A2328"],
            ["薰衣草", "ECE6F5", "2A2536"], ["雾蓝", "E3ECF5", "1F2A36"],
            ["薄荷", "E2F0E8", "1E2E26"]
        ]
        XCTAssertEqual(NotePalette.allCases.map { [$0.name, $0.lightHex, $0.darkHex] }, expected)
        XCTAssertNil(NotePalette(rawValue: "graphite"))
        XCTAssertEqual(NotePalette(stored: "graphite"), .paper)
        XCTAssertEqual(NotePalette(stored: "mint"), .mint)
        XCTAssertNil(NotePalette(stored: "slate"))
        let decoded = try? JSONDecoder().decode([NotePalette].self, from: Data(#"["graphite","lemon"]"#.utf8))
        XCTAssertEqual(decoded, [.paper, .lemon])
        XCTAssertThrowsError(try JSONDecoder().decode([NotePalette].self, from: Data(#"["slate"]"#.utf8)))
    }

    func testNextColorPrefersTheLeastUsedThenFollowsTheLatest() {
        XCTAssertEqual(NotePalette.next(inUse: [], latest: nil), .paper)
        // Seven creations in a row use every colour once.
        var used: [NotePalette] = []
        for _ in NotePalette.allCases { used.append(NotePalette.next(inUse: used, latest: used.last)) }
        XCTAssertEqual(used, NotePalette.allCases)
        // A gap left by a deletion is filled first, whatever came last.
        let remaining = used.filter { $0 != .cherry }
        XCTAssertEqual(NotePalette.next(inUse: remaining, latest: .mint), .cherry)
        // Equal counts: the colour after the latest, wrapping around.
        XCTAssertEqual(NotePalette.next(inUse: used, latest: .mint), .paper)
        XCTAssertEqual(NotePalette.next(inUse: [.lemon], latest: .lemon), .apricot)
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
        XCTAssertEqual(ToolbarMetrics.length(horizontal: true, paged: true) - ToolbarMetrics.length(horizontal: true, paged: false), ToolbarMetrics.pagerWidth)
        XCTAssertEqual(ToolbarMetrics.cornerRadius, ToolbarMetrics.width / 2, "a true capsule")
        XCTAssertEqual(ToolbarMetrics.snapDistance, 81)
        XCTAssertGreaterThanOrEqual(ToolbarMetrics.buttonWidth, 44)
        XCTAssertGreaterThanOrEqual(ToolbarMetrics.buttonHeight, 44)
        XCTAssertEqual(ToolbarMetrics.buttonCount, 5) // 新建 浮起 整理 收起 设置
    }

    func testCompositionBlocksFutureStructuralCommands() {
        XCTAssertFalse(CompositionPolicy.allowsStructuralCommand(hasMarkedText: true))
        XCTAssertTrue(CompositionPolicy.allowsStructuralCommand(hasMarkedText: false))
    }
}
