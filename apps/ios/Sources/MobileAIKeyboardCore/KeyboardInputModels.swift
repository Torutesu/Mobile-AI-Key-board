import Foundation

/// The ordinary keyboard's two visible layers. Skill Keys are intentionally
/// letter-only and therefore never participate in the number/symbol layer.
public enum KeyboardInputLayer: String, CaseIterable, Equatable, Sendable {
    case letters
    case numbersAndSymbols

    public var toggleTitle: String {
        switch self {
        case .letters: return "123"
        case .numbersAndSymbols: return "ABC"
        }
    }
}

public enum KeyboardShiftState: String, CaseIterable, Equatable, Sendable {
    case lower
    case shifted
    case capsLock

    public var accessibilityValue: String {
        switch self {
        case .lower: return "オフ"
        case .shifted: return "オン。次の1文字だけ大文字"
        case .capsLock: return "オン。大文字を固定"
        }
    }
}

/// Pure state machine for the ordinary input surface. Keeping this separate
/// from UIKit prevents layer/shift regressions from affecting Skill Key routing.
public struct KeyboardInputState: Equatable, Sendable {
    public private(set) var layer: KeyboardInputLayer
    public private(set) var shift: KeyboardShiftState

    public init(layer: KeyboardInputLayer = .letters, shift: KeyboardShiftState = .lower) {
        self.layer = layer
        self.shift = shift
    }

    public mutating func toggleLayer() {
        layer = layer == .letters ? .numbersAndSymbols : .letters
        // Shift has no meaning on the number/symbol layer and must not leak
        // into the next return to letters.
        if layer == .numbersAndSymbols { shift = .lower }
    }

    public mutating func pressShift() {
        guard layer == .letters else { return }
        switch shift {
        case .lower: shift = .shifted
        case .shifted: shift = .capsLock
        case .capsLock: shift = .lower
        }
    }

    public mutating func commitLetter() {
        if shift == .shifted { shift = .lower }
    }

    public func displayLetter(_ letter: Character) -> Character {
        guard layer == .letters else { return letter }
        switch shift {
        case .lower: return Character(String(letter).lowercased())
        case .shifted, .capsLock: return Character(String(letter).uppercased())
        }
    }
}

public enum KeyboardReturnAction: String, Equatable, Sendable {
    case newline
    case go
    case join
    case next
    case search
    case send
    case done
    case `continue`

    public var displayLabel: String {
        switch self {
        case .newline: return "改行"
        case .go: return "移動"
        case .join: return "参加"
        case .next: return "次へ"
        case .search: return "検索"
        case .send: return "送信"
        case .done: return "完了"
        case .continue: return "続ける"
        }
    }
}
