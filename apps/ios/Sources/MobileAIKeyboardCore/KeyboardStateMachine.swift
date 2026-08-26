import Foundation

/// Pure reducer for keyboard UI. It deliberately has no networking or document access.
public struct KeyboardStateMachine: Sendable {
    public private(set) var screen: KeyboardScreen = .typing

    public init() {}

    @discardableResult
    public mutating func send(_ action: KeyboardAction) -> KeyboardScreen {
        switch (screen, action) {
        case (.typing, .invokeCommand): screen = .command
        case (.typing, .lock(let reason)): screen = .locked(reason)
        case (.command, .beginCapture(let draft)) where !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            screen = .captureReview(draft)
        case (.captureReview(let draft), .acknowledgeCapture): screen = .captureReview(draft.acknowledging())
        case (.captureReview(let draft), .beginPlanning) where draft.acknowledged: screen = .planning
        case (.captureReview, .beginPlanning): screen = .error(.missingDisclosure)
        case (.planning, .showRewrite(let result)): screen = .resultReview(result)
        case (.resultReview, .updateRewrite(let result)): screen = .resultReview(result)
        case (.planning, .showActionReview): screen = .actionReview
        case (.resultReview(let result), .applyResult(let currentFingerprint)):
            if currentFingerprint == result.fieldFingerprint {
                let locking = EntityLocking()
                screen = .applied(UndoToken(original: result.original, rewritten: result.rewritten, originalFingerprint: result.fieldFingerprint, appliedFingerprint: locking.fingerprint(result.rewritten), documentIdentifier: result.documentIdentifier))
            } else {
                screen = .error(.staleField)
            }
        case (.resultReview(let result), .applyResultWithSnapshot(let snapshot)):
            let identityMatches = result.documentIdentifier == nil || result.documentIdentifier == snapshot.documentIdentifier
            if snapshot.fieldFingerprint == result.fieldFingerprint && identityMatches {
                let locking = EntityLocking()
                let appliedFingerprint = snapshot.expectedAppliedFingerprint ?? locking.fingerprint(result.rewritten)
                screen = .applied(UndoToken(original: result.original, rewritten: result.rewritten, originalFingerprint: result.fieldFingerprint, appliedFingerprint: appliedFingerprint, documentIdentifier: snapshot.documentIdentifier))
            } else {
                screen = .error(.staleField)
            }
        case (.applied(let token), .undo(let currentFingerprint)):
            screen = currentFingerprint == token.appliedFingerprint ? .typing : .error(.staleField)
        case (.applied(let token), .undoWithSnapshot(let snapshot)):
            let identityMatches = token.documentIdentifier == nil || token.documentIdentifier == snapshot.documentIdentifier
            screen = snapshot.fieldFingerprint == token.appliedFingerprint && identityMatches ? .typing : .error(.staleField)
        case (.resultReview, .editResult): break
        case (.resultReview, .regenerateResult): break
        case (.resultReview, .copyResult): break
        case (.resultReview, .showActionReview): screen = .actionReview
        case (.actionReview, .confirmExecution): screen = .executing
        case (.executing, .settle(let receipt)): screen = .receipt(receipt)
        case (.receipt, .applyResult): screen = .typing
        case (_, .cancel): screen = .typing
        case (_, .fail(let error)): screen = .error(error)
        case (.locked, .unlock): screen = .typing
        default: break
        }
        return screen
    }
}
