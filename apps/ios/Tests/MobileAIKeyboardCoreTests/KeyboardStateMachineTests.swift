import XCTest
@testable import MobileAIKeyboardCore

final class KeyboardStateMachineTests: XCTestCase {
    func testCommandRequiresDisclosureBeforePlanning() {
        var machine = KeyboardStateMachine()
        XCTAssertEqual(machine.send(.invokeCommand), .command)
        let draft = CaptureDraft(text: "明日の予定を確認してください", fieldFingerprint: "abc")
        XCTAssertEqual(machine.send(.beginCapture(draft)), .captureReview(draft))
        XCTAssertEqual(machine.send(.beginPlanning), .error(.missingDisclosure))
    }

    func testApplyStopsWhenFieldChanged() {
        var machine = KeyboardStateMachine()
        _ = machine.send(.invokeCommand)
        _ = machine.send(.beginCapture(CaptureDraft(text: "よろしく", fieldFingerprint: "snapshot")))
        _ = machine.send(.acknowledgeCapture)
        _ = machine.send(.beginPlanning)
        let result = RewriteResult(original: "よろしく", rewritten: "よろしくお願いいたします。", preservedEntities: [], fieldFingerprint: "snapshot")
        _ = machine.send(.showRewrite(result))
        XCTAssertEqual(machine.send(.applyResult(currentFieldFingerprint: "changed")), .error(.staleField))
    }

    func testSecureFieldCanOnlyReturnToTypingAfterUnlock() {
        var machine = KeyboardStateMachine()
        _ = machine.send(.lock(.secureField))
        XCTAssertEqual(machine.screen, .locked(.secureField))
        XCTAssertEqual(machine.send(.invokeCommand), .locked(.secureField))
        XCTAssertEqual(machine.send(.unlock), .typing)
    }

    func testActionRequiresExplicitConfirmation() {
        var machine = KeyboardStateMachine()
        _ = machine.send(.invokeCommand)
        _ = machine.send(.beginCapture(CaptureDraft(text: "日程調整", fieldFingerprint: "a")))
        _ = machine.send(.acknowledgeCapture)
        _ = machine.send(.beginPlanning)
        _ = machine.send(.showActionReview)
        XCTAssertEqual(machine.screen, .actionReview)
        XCTAssertEqual(machine.send(.confirmExecution), .executing)
    }
}
