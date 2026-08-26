import Foundation

public struct EntityLocking: Sendable {
    public init() {}

    /// Detects high-confidence entities locally. Values are never emitted to telemetry.
    public func entities(in text: String) -> [String] {
        let patterns = [
            #"https?://[^\s]+"#,
            #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            #"\d{4}[-/]\d{1,2}[-/]\d{1,2}"#,
            #"\b\d+(?:\.\d+)?\b"#,
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

    public func fingerprint(_ text: String) -> String {
        // Stable, content-derived field snapshot without introducing a crypto dependency in the extension.
        var hash: UInt64 = 14695981039346656037
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return String(format: "%016llx", hash)
    }
}
