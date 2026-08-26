import Foundation
import CryptoKit

public struct EntityLocking: Sendable {
    public init() {}

    /// Detects high-confidence entities locally. Values are never emitted to telemetry.
    public func entities(in text: String) -> [String] {
        let patterns = [
            #"https?://[^\s]+"#,
            #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            #"\d{4}[-/]\d{1,2}[-/]\d{1,2}"#,
            #"\b\d+(?:\.\d+)?\b"#,
            #"@[A-Za-z0-9_]+"#,
            #"[一-龯々〆ヵヶ]{1,12}(?:さん|様|氏)"#,
            #"\b[A-Z]{2,}\b"#
        ]
        var found: [String] = []
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            expression.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match, let matchRange = Range(match.range, in: text) else { return }
                let value = String(text[matchRange])
                if !found.contains(value) { found.append(value) }
            }
        }
        let outermost = found.filter { candidate in
            !found.contains { other in other != candidate && other.contains(candidate) }
        }
        return outermost.sorted { text.distance(from: text.startIndex, to: text.range(of: $0)!.lowerBound) < text.distance(from: text.startIndex, to: text.range(of: $1)!.lowerBound) }
    }

    /// Masks detected entities before a deterministic transform and restores the exact bytes.
    /// This prevents rewrite substitutions from changing URL paths, email local-parts, dates,
    /// numbers, handles, honorific names, or uppercase identifiers.
    public func maskAndRestore(_ text: String, transform: (String) -> String) -> String {
        let values = entities(in: text)
        var masked = text
        var replacements: [(String, String)] = []
        for (index, value) in values.enumerated() {
            let marker = "\u{E000}\(index)\u{E001}"
            masked = masked.replacingOccurrences(of: value, with: marker)
            replacements.append((marker, value))
        }
        var transformed = transform(masked)
        for (marker, value) in replacements { transformed = transformed.replacingOccurrences(of: marker, with: value) }
        return transformed
    }

    public func fingerprint(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Binds an explicit selection to its bounded editor context. Hashing only
    /// the selected bytes is insufficient when the same text appears twice in
    /// one document and the caret moves between capture and Apply.
    public func selectionFingerprint(selectedText: String, before: String, after: String, contextLimit: Int = 96) -> String {
        let boundedLimit = max(0, min(contextLimit, 512))
        let payload = [
            "selection-v1",
            String(before.suffix(boundedLimit)),
            selectedText,
            String(after.prefix(boundedLimit))
        ].joined(separator: "\u{0}")
        return fingerprint(payload)
    }
}
