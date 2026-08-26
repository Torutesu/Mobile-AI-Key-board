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
        case (.planning, .showActionReview): screen = .actionReview
        case (.resultReview(let result), .applyResult(let currentFingerprint)):
            screen = currentFingerprint == result.fieldFingerprint ? .typing : .error(.staleField)
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
