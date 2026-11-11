import XCTest
@testable import DeskNodesPersistence

final class HotkeyTests: XCTestCase {
    func testDefaultCanonicalParserAndSupportedKeys() throws {
        XCTAssertEqual(try Hotkey(NativePreferences().hotkey).canonical, "Control+Option+N")
        XCTAssertEqual(try Hotkey(" command + shift + n ").canonical, "Shift+Command+N")
        for key in Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789").map(String.init) + ["Space"] {
            XCTAssertEqual(try Hotkey("Command+" + key).key, key)
        }
    }
    func testInvalidDuplicateReservedAndUnmodifiedShortcuts() {
        for value in ["", "N", "Option+N", "Shift+N", "Control++N", "Control+Control+N", "Fn+Command+N", "Command+Enter", "Command+中", "Command+NN", "Option+Command+H", "Option+Command+D", "Control+Option+Space"] {
            XCTAssertThrowsError(try Hotkey(value), value)
        }
    }
    func testConflictPreservesOldBindingAndDoesNotPersist() throws {
        enum Conflict: Error { case occupied }
        let binding = HotkeyBinding<Int>(), old = try Hotkey("Control+Option+N")
        var retired: [Int] = [], stored = old
        try binding.replace(old, register: { _ in 1 }, persist: {}, unregister: { retired.append($0) })
        let next = try Hotkey("Command+7")
        XCTAssertThrowsError(try binding.replace(next, register: { _ in throw Conflict.occupied }, persist: { stored = next }, unregister: { retired.append($0) }))
        XCTAssertEqual(stored, old); XCTAssertEqual(binding.binding, old); XCTAssertTrue(retired.isEmpty)
    }
    func testPersistenceFailureRetiresCandidateAndSuccessfulReplaceRetiresOld() throws {
        enum Failure: Error { case disk }
        let binding = HotkeyBinding<Int>(), old = try Hotkey("Control+Option+N"), next = try Hotkey("Command+7")
        var retired: [Int] = []
        try binding.replace(old, register: { _ in 1 }, persist: {}, unregister: { retired.append($0) })
        XCTAssertThrowsError(try binding.replace(next, register: { _ in 2 }, persist: { throw Failure.disk }, unregister: { retired.append($0) }))
        XCTAssertEqual(retired, [2]); XCTAssertEqual(binding.binding, old)
        try binding.replace(next, register: { _ in 3 }, persist: {}, unregister: { retired.append($0) })
        XCTAssertEqual(retired, [2,1]); XCTAssertEqual(binding.binding, next)
        var registered = false
        try binding.replace(next, register: { _ in registered = true; return 4 }, persist: {}, unregister: { retired.append($0) })
        XCTAssertFalse(registered)
        binding.stop { retired.append($0) }; binding.stop { retired.append($0) }
        XCTAssertEqual(retired, [2,1,3]); XCTAssertNil(binding.binding)
    }
}
