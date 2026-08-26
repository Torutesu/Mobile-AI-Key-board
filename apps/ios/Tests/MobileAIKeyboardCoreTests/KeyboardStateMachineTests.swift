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

    func testCaptureReviewCarriesLocalOnlyDisclosureAndCancelResetsBoundary() {
        var machine = KeyboardStateMachine()
        _ = machine.send(.invokeCommand)
        let draft = CaptureDraft(text: "丁寧に", source: .command, fieldFingerprint: "f", redactedText: "丁寧に", externalTransmissionAllowed: false, fallbackMessage: "選択範囲なし")
        _ = machine.send(.beginCapture(draft))
        if case .captureReview(let review) = machine.screen {
            XCTAssertEqual(review.characterCount, 3)
            XCTAssertFalse(review.externalTransmissionAllowed)
            XCTAssertEqual(review.fallbackMessage, "選択範囲なし")
        } else {
            XCTFail("expected capture review")
        }
        XCTAssertEqual(machine.send(.cancel), .typing)
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

    func testEditedResultBecomesUndoAuthority() {
        var machine = KeyboardStateMachine()
        _ = machine.send(.invokeCommand)
        _ = machine.send(.beginCapture(CaptureDraft(text: "よろしく", fieldFingerprint: "snapshot", documentIdentifier: "doc-1")))
        _ = machine.send(.acknowledgeCapture)
        _ = machine.send(.beginPlanning)
        _ = machine.send(.showRewrite(RewriteResult(original: "よろしく", rewritten: "旧結果", preservedEntities: [], fieldFingerprint: "snapshot", documentIdentifier: "doc-1")))
        _ = machine.send(.updateRewrite(RewriteResult(original: "よろしく", rewritten: "編集後の結果", preservedEntities: [], fieldFingerprint: "snapshot", documentIdentifier: "doc-1")))
        let applied = machine.send(.applyResultWithSnapshot(EditorSnapshot(documentIdentifier: "doc-1", fieldFingerprint: "snapshot")))
        guard case .applied(let token) = applied else { return XCTFail("expected applied state") }
        XCTAssertEqual(token.rewritten, "編集後の結果")
        XCTAssertEqual(token.appliedFingerprint, EntityLocking().fingerprint("編集後の結果"))
    }

    func testApplyCallbackAndUndoBindTheSameCursorContextFingerprint() {
        var machine = KeyboardStateMachine()
        _ = machine.send(.invokeCommand)
        _ = machine.send(.beginCapture(CaptureDraft(text: "old", fieldFingerprint: "selection", documentIdentifier: "doc-1")))
        _ = machine.send(.acknowledgeCapture)
        _ = machine.send(.beginPlanning)
        _ = machine.send(.showRewrite(RewriteResult(original: "old", rewritten: "new", preservedEntities: [], fieldFingerprint: "selection", documentIdentifier: "doc-1")))
        let expectedAfterInsertion = EntityLocking().selectionFingerprint(selectedText: "", before: "before new", after: " after")
        let applied = machine.send(.applyResultWithSnapshot(EditorSnapshot(documentIdentifier: "doc-1", fieldFingerprint: "selection", expectedAppliedFingerprint: expectedAfterInsertion)))
        guard case .applied(let token) = applied else { return XCTFail("expected applied state") }
        XCTAssertEqual(token.appliedFingerprint, expectedAfterInsertion)
        XCTAssertEqual(
            machine.send(.undoWithSnapshot(EditorSnapshot(documentIdentifier: "doc-1", fieldFingerprint: expectedAfterInsertion))),
            .typing
        )

        // The old whole-field hash format must not alias the cursor-context
        // lock used by Apply callback and Undo.
        var staleMachine = KeyboardStateMachine()
        _ = staleMachine.send(.invokeCommand)
        _ = staleMachine.send(.beginCapture(CaptureDraft(text: "old", fieldFingerprint: "selection", documentIdentifier: "doc-1")))
        _ = staleMachine.send(.acknowledgeCapture)
        _ = staleMachine.send(.beginPlanning)
        _ = staleMachine.send(.showRewrite(RewriteResult(original: "old", rewritten: "new", preservedEntities: [], fieldFingerprint: "selection", documentIdentifier: "doc-1")))
        _ = staleMachine.send(.applyResultWithSnapshot(EditorSnapshot(documentIdentifier: "doc-1", fieldFingerprint: "selection", expectedAppliedFingerprint: expectedAfterInsertion)))
        XCTAssertEqual(staleMachine.send(.undoWithSnapshot(EditorSnapshot(documentIdentifier: "doc-1", fieldFingerprint: EntityLocking().fingerprint("mutated")))), .error(.staleField))
    }

    func testLocalTextLimitsMatchW2Contract() {
        XCTAssertEqual(LocalTextLimits.commandCharacters, 500)
        XCTAssertEqual(LocalTextLimits.selectionCharacters, 4_000)
        XCTAssertEqual(LocalTextLimits.surroundingBeforeCharacters, 1_000)
        XCTAssertEqual(LocalTextLimits.surroundingAfterCharacters, 500)
        XCTAssertEqual(LocalTextLimits.resultCharacters, 10_000)
    }

    func testApplyUndoRequiresSameDocumentAndAppliedText() {
        var machine = KeyboardStateMachine()
        _ = machine.send(.invokeCommand)
        _ = machine.send(.beginCapture(CaptureDraft(text: "よろしく", fieldFingerprint: "original", documentIdentifier: "doc-1")))
        _ = machine.send(.acknowledgeCapture)
        _ = machine.send(.beginPlanning)
        _ = machine.send(.showRewrite(RewriteResult(original: "よろしく", rewritten: "よろしくお願いいたします。", preservedEntities: [], fieldFingerprint: "original", documentIdentifier: "doc-1")))
        _ = machine.send(.applyResultWithSnapshot(EditorSnapshot(documentIdentifier: "doc-1", fieldFingerprint: "original")))
        let applied = EntityLocking().fingerprint("よろしくお願いいたします。")
        XCTAssertEqual(machine.send(.undoWithSnapshot(EditorSnapshot(documentIdentifier: "doc-2", fieldFingerprint: applied))), .error(.staleField))
        var valid = KeyboardStateMachine()
        _ = valid.send(.invokeCommand)
        _ = valid.send(.beginCapture(CaptureDraft(text: "よろしく", fieldFingerprint: "original", documentIdentifier: "doc-1")))
        _ = valid.send(.acknowledgeCapture)
        _ = valid.send(.beginPlanning)
        _ = valid.send(.showRewrite(RewriteResult(original: "よろしく", rewritten: "よろしくお願いいたします。", preservedEntities: [], fieldFingerprint: "original", documentIdentifier: "doc-1")))
        _ = valid.send(.applyResultWithSnapshot(EditorSnapshot(documentIdentifier: "doc-1", fieldFingerprint: "original")))
        XCTAssertEqual(valid.send(.undoWithSnapshot(EditorSnapshot(documentIdentifier: "doc-1", fieldFingerprint: applied))), .typing)
    }

    func testSecureFieldCanOnlyReturnToTypingAfterUnlock() {
        var machine = KeyboardStateMachine()
        _ = machine.send(.lock(.secureField))
        XCTAssertEqual(machine.screen, .locked(.secureField))
        XCTAssertEqual(machine.send(.invokeCommand), .locked(.secureField))
        XCTAssertEqual(machine.send(.unlock), .typing)
    }

    func testSecureTransitionOverridesEveryContentBearingScreen() {
        var command = KeyboardStateMachine()
        _ = command.send(.invokeCommand)
        XCTAssertEqual(command.send(.lock(.secureField)), .locked(.secureField))

        var capture = KeyboardStateMachine()
        _ = capture.send(.invokeCommand)
        _ = capture.send(.beginCapture(CaptureDraft(text: "secret", fieldFingerprint: "f")))
        XCTAssertEqual(capture.send(.lock(.unsupportedField)), .locked(.unsupportedField))

        var result = KeyboardStateMachine()
        _ = result.send(.invokeCommand)
        _ = result.send(.beginCapture(CaptureDraft(text: "secret", fieldFingerprint: "f")))
        _ = result.send(.acknowledgeCapture)
        _ = result.send(.beginPlanning)
        _ = result.send(.showRewrite(RewriteResult(original: "secret", rewritten: "result", preservedEntities: [], fieldFingerprint: "f")))
        XCTAssertEqual(result.send(.lock(.secureField)), .locked(.secureField))

        var applied = KeyboardStateMachine()
        _ = applied.send(.invokeCommand)
        _ = applied.send(.beginCapture(CaptureDraft(text: "secret", fieldFingerprint: "f")))
        _ = applied.send(.acknowledgeCapture)
        _ = applied.send(.beginPlanning)
        _ = applied.send(.showRewrite(RewriteResult(original: "secret", rewritten: "result", preservedEntities: [], fieldFingerprint: "f")))
        _ = applied.send(.applyResult(currentFieldFingerprint: "f"))
        XCTAssertEqual(applied.send(.lock(.secureField)), .locked(.secureField))
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
