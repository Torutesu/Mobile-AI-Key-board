import XCTest
@testable import MobileAIKeyboardCore

final class OrdinaryKeyboardLayoutTests: XCTestCase {
    func testLayoutContainsOrdinaryInputControls() {
        XCTAssertEqual(OrdinaryKeyboardLayout.letterRows, ["qwertyuiop", "asdfghjkl", "zxcvbnm"])
        XCTAssertEqual(OrdinaryKeyboardLayout.letterRows.joined().count, 26)
        XCTAssertEqual(OrdinaryKeyboardLayout.bottomKeys, ["globe", "space", "return"])
        XCTAssertEqual(OrdinaryKeyboardLayout.utilityKeys, ["shift", "delete"])
    }
}
