import Foundation

/// Defense-in-depth redaction for local capture review. It is deliberately conservative: a
/// detected secret blocks the run rather than silently mutating user text.
public struct LocalRedactor: Sendable {
    private let patterns: [(name: String, expression: String)] = [
        ("APIキー候補", #"\b(?:(?:sk|pk)[_-][A-Za-z0-9_-]{16,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AIza[A-Za-z0-9_-]{20,})\b"#),
        ("Bearerトークン候補", #"\bBearer\s+[A-Za-z0-9._~-]{16,}\b"#),
        ("カード番号候補", #"\b(?:\d[ -]?){13,19}\b"#),
        ("ワンタイムコード候補", #"\b\d{6}\b"#),
        ("秘密鍵候補", #"-----BEGIN [A-Z ]+PRIVATE KEY-----[\s\S]+?-----END [A-Z ]+PRIVATE KEY-----"#)
    ]

    public init() {}

    public func redact(_ text: String) -> RedactionResult {
        var redacted = text
        var detected: [String] = []
        for item in patterns {
            guard let expression = try? NSRegularExpression(pattern: item.expression) else { continue }
            let range = NSRange(redacted.startIndex..<redacted.endIndex, in: redacted)
            if expression.firstMatch(in: redacted, range: range) != nil {
                detected.append(item.name)
                redacted = expression.stringByReplacingMatches(in: redacted, range: range, withTemplate: "［検出した秘密情報］")
            }
        }
        return RedactionResult(redacted: redacted, detected: detected, blocked: !detected.isEmpty)
    }
}
