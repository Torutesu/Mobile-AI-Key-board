import XCTest
@testable import MobileAIKeyboardCore

final class OrdinaryKeyboardLayoutTests: XCTestCase {
    func testLayoutContainsOrdinaryInputControls() {
        XCTAssertEqual(OrdinaryKeyboardLayout.letterRows, ["qwertyuiop", "asdfghjkl", "zxcvbnm"])
        XCTAssertEqual(OrdinaryKeyboardLayout.letterRows.joined().count, 26)
        XCTAssertEqual(OrdinaryKeyboardLayout.numberRows, ["1234567890", "-/:;()$&@\"", ".,?!'"])
        XCTAssertEqual(OrdinaryKeyboardLayout.numberRows.joined().count, 25)
        XCTAssertEqual(OrdinaryKeyboardLayout.bottomKeys, ["globe", "layer", "space", "return"])
        XCTAssertEqual(OrdinaryKeyboardLayout.utilityKeys, ["shift", "delete"])
    }

    func testLayerAndShiftTransitionsAreExplicit() {
        var state = KeyboardInputState()
        XCTAssertEqual(state.layer, .letters)
        XCTAssertEqual(state.shift, .lower)

        state.pressShift()
        XCTAssertEqual(state.shift, .shifted)
        XCTAssertEqual(state.displayLetter("a"), "A")
        state.commitLetter()
        XCTAssertEqual(state.shift, .lower)

        state.pressShift()
        state.pressShift()
        XCTAssertEqual(state.shift, .capsLock)
        state.toggleLayer()
        XCTAssertEqual(state.layer, .numbersAndSymbols)
        XCTAssertEqual(state.shift, .lower)
        state.toggleLayer()
        XCTAssertEqual(state.layer, .letters)
        XCTAssertEqual(state.displayLetter("a"), "a")
    }

    func testReturnLabelsRemainPureAndLocalized() {
        XCTAssertEqual(KeyboardReturnAction.newline.displayLabel, "改行")
        XCTAssertEqual(KeyboardReturnAction.search.displayLabel, "検索")
        XCTAssertEqual(KeyboardReturnAction.send.displayLabel, "送信")
    }
}
