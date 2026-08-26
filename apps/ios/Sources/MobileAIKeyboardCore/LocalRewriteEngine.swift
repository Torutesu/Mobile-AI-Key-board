import Foundation

public struct LocalRewriteEngine: Sendable {
    private let locking: EntityLocking

    public init(locking: EntityLocking = EntityLocking()) { self.locking = locking }

    /// Deterministic offline fixture for W1/W2. It is intentionally not an LLM and never accesses the network.
    public func politeRewrite(_ input: String) -> RewriteResult? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let entities = locking.entities(in: trimmed)
        let substitutions: [(String, String)] = [
            ("よろしく", "よろしくお願いいたします"),
            ("お願いします", "お願いいたします"),
            ("教えて", "お知らせいただけますでしょうか"),
            ("できますか？", "可能でしょうか。"),
            ("できますか?", "可能でしょうか。"),
            ("ありがとう", "ありがとうございます")
        ]
        var output = locking.maskAndRestore(trimmed) { value in
            var transformed = value
            for (from, to) in substitutions { transformed = transformed.replacingOccurrences(of: from, with: to) }
            return transformed
        }
        if !output.hasSuffix("。") && !output.hasSuffix("！") && !output.hasSuffix("！") && !output.hasSuffix("?") && !output.hasSuffix("？") { output += "。" }
        return RewriteResult(original: trimmed, rewritten: output, preservedEntities: entities, fieldFingerprint: locking.fingerprint(trimmed))
    }

    public func punctuationRewrite(_ input: String) -> RewriteResult? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let entities = locking.entities(in: trimmed)
        var output = locking.maskAndRestore(trimmed) { value in
            value
                .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"[ \t]*([、。！？!?])"#, with: "$1", options: .regularExpression)
        }
        if !output.hasSuffix("。") && !output.hasSuffix("！") && !output.hasSuffix("!") && !output.hasSuffix("?") && !output.hasSuffix("？") { output += "。" }
        return RewriteResult(original: trimmed, rewritten: output, preservedEntities: entities, fieldFingerprint: locking.fingerprint(trimmed))
    }
}
