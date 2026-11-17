import XCTest
@testable import DeskNodesCore

final class DesignTokensTests: XCTestCase {
    func testSevenPalettePairsInOrderWithoutGraphite() {
        let expected = [
            ["宣纸", "FAFBF8", "252C28"], ["柠黄", "F6F2DE", "302E23"],
            ["杏", "F5ECE2", "322B25"], ["樱", "F4E9EC", "31282C"],
            ["薰衣草", "EFECF5", "2C2933"], ["雾蓝", "EBF1F7", "252D35"],
            ["薄荷", "EDF2EB", "273129"]
        ]
        XCTAssertEqual(NotePalette.allCases.map { [$0.name, $0.lightHex, $0.darkHex] }, expected)
        // Outlines are a deeper tone of each colour: darker than the light card, lighter than the dark one.
        for palette in NotePalette.allCases {
            func luma(_ hex: String) -> Int {
                let v = Int(hex, radix: 16)!
                return (v >> 16 & 255) * 3 + (v >> 8 & 255) * 6 + (v & 255)
            }
            XCTAssertLessThan(luma(palette.selectionLightHex), luma(palette.lightHex))
            XCTAssertGreaterThan(luma(palette.selectionDarkHex), luma(palette.darkHex))
        }
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
        XCTAssertEqual(NoteMetrics.cornerRadius, 14)
        XCTAssertEqual(NoteMetrics.titleSize, 17)
        XCTAssertEqual(NoteMetrics.itemSize, 14)
        XCTAssertEqual(NoteMetrics.rowHeight, 36)
        XCTAssertEqual(NoteMetrics.collapsedHeight, 32)
        XCTAssertEqual(NoteMetrics.minimumWidth, 200)
        XCTAssertEqual(NoteMetrics.maximumHeight, 600)
    }

    func testTextSizesScaleFromTheStandardMetrics() {
        XCTAssertEqual(NoteTextSize.allCases.map(\.name), ["小", "标准", "大", "特大"])
        XCTAssertEqual(NoteTextSize.allCases.map(\.itemSize), [13, 14, 16, 18])
        XCTAssertEqual(NoteTextSize.allCases.map(\.titleSize), [16, 17, 19, 21])
        // Standard is exactly today's note.
        XCTAssertEqual(NoteTextSize.standard.titleSize, NoteMetrics.titleSize)
        XCTAssertEqual(NoteTextSize.standard.secondarySize, NoteMetrics.secondarySize)
        XCTAssertEqual(NoteTextSize.standard.scaled(NoteMetrics.rowHeight), NoteMetrics.rowHeight)
        XCTAssertEqual(NoteTextSize.extraLarge.scaled(NoteMetrics.rowHeight), 46)
        XCTAssertEqual(NoteTextSize.standard.stepped(1), .large)
        XCTAssertEqual(NoteTextSize.extraLarge.stepped(1), .extraLarge)
        XCTAssertEqual(NoteTextSize.small.stepped(-1), .small)
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
        XCTAssertEqual(ToolbarMetrics.buttonCount, 4) // 新建 浮起 整理 收起; 设置 lives in the menus
        XCTAssertEqual(ToolbarMetrics.height(paged: false), 296)
        XCTAssertEqual(ToolbarMetrics.length(horizontal: true, paged: false), 364)
    }

    func testEntryIsACircleAndLongTripsHomeTakeLonger() {
        XCTAssertEqual(ToolbarMetrics.entrySize, 56)
        XCTAssertEqual(ToolbarMetrics.entryCornerRadius, ToolbarMetrics.entrySize / 2, "a circle, not a rounded square")
        XCTAssertLessThan(MotionPolicy.toolbarReveal, MotionPolicy.toolbarExpandSpring, "controls are in before the spring settles")
        XCTAssertLessThanOrEqual(ToolbarMetrics.entrySize + ToolbarMetrics.edgeGap, ToolbarMetrics.width, "its hit zone fits the capsule's width")
        XCTAssertEqual(MotionPolicy.toolbarHomeGlide(distance: 0), 0.30)
        XCTAssertEqual(MotionPolicy.toolbarHomeGlide(distance: 300), 0.40, accuracy: 0.0001)
        XCTAssertEqual(MotionPolicy.toolbarHomeGlide(distance: 5000), 0.50)
    }

    func testCompositionBlocksFutureStructuralCommands() {
        XCTAssertFalse(CompositionPolicy.allowsStructuralCommand(hasMarkedText: true))
        XCTAssertTrue(CompositionPolicy.allowsStructuralCommand(hasMarkedText: false))
    }
}
