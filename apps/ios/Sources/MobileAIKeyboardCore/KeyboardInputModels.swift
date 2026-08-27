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

    /// Mirrors the host field's automatic-capitalization request without
    /// overriding a deliberate Caps Lock choice.
    public mutating func synchronizeAutomaticShift(_ shouldShift: Bool) {
        switch (shift, shouldShift) {
        case (.capsLock, _): break
        case (_, true): shift = .shifted
        case (.shifted, false): shift = .lower
        case (.lower, false): break
        }
    }

    public func displayLetter(_ letter: Character) -> Character {
        guard layer == .letters else { return letter }
        switch shift {
        case .lower: return Character(String(letter).lowercased())
        case .shifted, .capsLock: return Character(String(letter).uppercased())
        }
    }
}

public enum KeyboardAutocapitalizationMode: Equatable, Sendable {
    case none
    case words
    case sentences
    case allCharacters
}

public enum KeyboardAutocapitalizationPolicy {
    public static func shouldShift(mode: KeyboardAutocapitalizationMode, contextBeforeInput: String?) -> Bool {
        switch mode {
        case .none:
            return false
        case .allCharacters:
            return true
        case .words:
            guard let contextBeforeInput, let last = contextBeforeInput.last else { return true }
            return last.isWhitespace
        case .sentences:
            guard let contextBeforeInput, !contextBeforeInput.isEmpty else { return true }
            guard let last = contextBeforeInput.last else { return true }
            if last == "\n" || last == "\r" { return true }
            guard last.isWhitespace else { return false }
            guard let boundary = contextBeforeInput.reversed().first(where: { !$0.isWhitespace }) else { return true }
            return ".!?。！？".contains(boundary)
        }
    }
}

public struct KeyboardSurfaceEnvironment: Equatable, Sendable {
    public var isPad: Bool
    public var isLandscape: Bool
    public var usesAccessibilityTextSize: Bool

    public init(isPad: Bool, isLandscape: Bool, usesAccessibilityTextSize: Bool) {
        self.isPad = isPad
        self.isLandscape = isLandscape
        self.usesAccessibilityTextSize = usesAccessibilityTextSize
    }
}

public enum KeyboardSurfaceMetrics {
    /// A deterministic starting height for the ordinary typing surface. The
    /// content remains scrollable while the container adapts to device class,
    /// orientation, and accessibility text size.
    public static func height(keySize: KeyboardKeySize, environment: KeyboardSurfaceEnvironment) -> Double {
        let base: Double
        if environment.isPad {
            switch keySize {
            case .compact: base = 252
            case .standard: base = 276
            case .large: base = 300
            }
        } else if environment.isLandscape {
            switch keySize {
            case .compact: base = 244
            case .standard: base = 260
            case .large: base = 276
            }
        } else {
            switch keySize {
            case .compact: base = 244
            case .standard: base = 260
            case .large: base = 284
            }
        }

        guard environment.usesAccessibilityTextSize else { return base }
        return base + (environment.isPad ? 32 : environment.isLandscape ? 16 : 28)
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
