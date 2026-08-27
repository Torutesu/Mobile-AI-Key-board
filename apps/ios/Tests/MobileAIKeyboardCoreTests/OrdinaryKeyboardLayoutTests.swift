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

    func testAutocapitalizationPolicyCoversUIKitModes() {
        XCTAssertFalse(KeyboardAutocapitalizationPolicy.shouldShift(mode: .none, contextBeforeInput: nil))
        XCTAssertTrue(KeyboardAutocapitalizationPolicy.shouldShift(mode: .allCharacters, contextBeforeInput: "hello"))
        XCTAssertTrue(KeyboardAutocapitalizationPolicy.shouldShift(mode: .words, contextBeforeInput: "hello "))
        XCTAssertFalse(KeyboardAutocapitalizationPolicy.shouldShift(mode: .words, contextBeforeInput: "hello"))
        XCTAssertTrue(KeyboardAutocapitalizationPolicy.shouldShift(mode: .sentences, contextBeforeInput: nil))
        XCTAssertTrue(KeyboardAutocapitalizationPolicy.shouldShift(mode: .sentences, contextBeforeInput: "完了。 "))
        XCTAssertTrue(KeyboardAutocapitalizationPolicy.shouldShift(mode: .sentences, contextBeforeInput: "line\n"))
        XCTAssertFalse(KeyboardAutocapitalizationPolicy.shouldShift(mode: .sentences, contextBeforeInput: "still writing "))
    }

    func testAutomaticShiftPreservesManualCapsLock() {
        var state = KeyboardInputState()
        state.synchronizeAutomaticShift(true)
        XCTAssertEqual(state.shift, .shifted)
        state.synchronizeAutomaticShift(false)
        XCTAssertEqual(state.shift, .lower)
        state.pressShift()
        state.pressShift()
        XCTAssertEqual(state.shift, .capsLock)
        state.synchronizeAutomaticShift(false)
        XCTAssertEqual(state.shift, .capsLock)
    }

    func testKeyboardSurfaceHeightRespondsToDeviceOrientationAndTextSize() {
        let phonePortrait = KeyboardSurfaceEnvironment(isPad: false, isLandscape: false, usesAccessibilityTextSize: false)
        let phoneLandscape = KeyboardSurfaceEnvironment(isPad: false, isLandscape: true, usesAccessibilityTextSize: false)
        let accessiblePhone = KeyboardSurfaceEnvironment(isPad: false, isLandscape: false, usesAccessibilityTextSize: true)
        let pad = KeyboardSurfaceEnvironment(isPad: true, isLandscape: false, usesAccessibilityTextSize: false)

        XCTAssertEqual(KeyboardSurfaceMetrics.height(keySize: .standard, environment: phonePortrait), 260)
        XCTAssertEqual(KeyboardSurfaceMetrics.height(keySize: .standard, environment: phoneLandscape), 260)
        XCTAssertEqual(KeyboardSurfaceMetrics.height(keySize: .standard, environment: accessiblePhone), 288)
        XCTAssertEqual(KeyboardSurfaceMetrics.height(keySize: .standard, environment: pad), 276)
    }
}
